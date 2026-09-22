#!/usr/bin/env python3
"""Exercise the real manager and upstream native service in a disposable Docker VM.

Requires the sky image, BusyBox, dnsmasq-base, a read-only /repo mount, --privileged, and the
validated Lima host network. Never run in a container with an active zapret2.
Uses real PTYs, files, nfqws2 and nftables; no mocked service/installer callbacks.
"""
import gzip
import hashlib
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import tempfile
import time

REPO = Path('/repo')
SOURCE = Path('/tmp/zapret2-openwrt')
PERSIST = Path('/usr/lib/zapret2-openwrt')
COMMAND = Path('/usr/bin/zapret2')
if not Path('/.dockerenv').exists():
    raise SystemExit('Docker ONLY')
if any(p.exists() or p.is_symlink() for p in (SOURCE, PERSIST, COMMAND)):
    raise SystemExit('Use a disposable container without an installed manager')
if not shutil.which('busybox'):
    raise SystemExit('Install BusyBox inside the disposable test container first')
if not shutil.which('dnsmasq'):
    raise SystemExit('Install dnsmasq-base inside the disposable test container first')
if subprocess.run(['nft', 'list', 'table', 'inet', 'zapret2'], capture_output=True).returncode == 0:
    raise SystemExit('An existing zapret2 firewall is present; refusing to touch it')


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def check_public_assets():
    urls = (
        ('github', 'https://github.com/'),
        ('steam-avatar', 'https://avatars.steamstatic.com/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg'),
        ('spotify-avatar', 'https://image-cdn-fa.spotifycdn.com/image/ab67616100005174e2e8e7ff002a4afda1c7147e'),
        ('spotify-thumbnail', 'https://i.scdn.co/image/ab67616100005174e2e8e7ff002a4afda1c7147e'),
    )
    passed = True
    for name, url in urls:
        with tempfile.NamedTemporaryFile() as body:
            result = subprocess.run(['curl-http3', '-4', '--noproxy', '*', '-fsS',
                                     '--connect-timeout', '6', '--max-time', '15',
                                     '-o', body.name, url], capture_output=True, text=True)
            data = Path(body.name).read_bytes()
        valid = b'</html>' in data.lower() if name == 'github' else data.startswith(b'\xff\xd8\xff')
        ok = result.returncode == 0 and valid
        print(f"{'PASS' if ok else 'FAIL'}: {name}: exit={result.returncode}, bytes={len(data)}, {result.stderr.strip()}", flush=True)
        passed = passed and ok
    assert passed, 'Managed strategy must not break GitHub/Steam/Spotify assets'


root = Path(tempfile.mkdtemp(prefix='z2b-manager-'))
root.chmod(0o755)
base = root / 'base'
ui_pid = None
ui_fd = None
pending = b''
transcript = bytearray()
old_sysctl = run('sysctl', '-n', 'net.netfilter.nf_conntrack_tcp_be_liberal').strip()
dns_processes = []
dns_config = Path('/var/etc/dnsmasq.conf.z2b-test')
dns_hosts = Path('/tmp/hosts/zapret2-sky-discord')
user_hosts = Path('/tmp/hosts/z2b-test-preserved')
resolv = Path('/etc/resolv.conf')
old_resolv = resolv.read_text()
if any(p.exists() for p in (dns_config, dns_hosts, user_hosts)):
    raise SystemExit('Use a disposable container without existing DNS test files')


def check_dns(enabled):
    expected = {'162.159.138.232', '162.159.137.232', '162.159.128.233', '162.159.135.232'} if enabled else {'162.159.136.232'}
    for host in ('discord.com', 'updates.discord.com'):
        deadline = time.monotonic() + 3
        while True:
            answers = set(run('dig', '@127.0.0.1', '+short', '+time=1', '+tries=1', host, 'A').split())
            if answers == expected or time.monotonic() >= deadline:
                break
            time.sleep(.05)
        assert answers == expected, (host, answers, expected)
    assert run('dig', '@127.0.0.1', '+short', 'untouched.example', 'A').strip() == '192.0.2.55'
    assert run('dig', '@127.0.0.1', '+short', 'unlisted.discord.com', 'A').strip() == '162.159.136.232'


def open_manager(path):
    global ui_pid, ui_fd, pending
    pending = b''
    ui_pid, ui_fd = pty.fork()
    if ui_pid == 0:
        os.environ.update(ZAPRET_BASE=str(base), TERM='xterm', EDITOR='/usr/bin/tee')
        os.environ['PATH'] = str(root / 'bin') + ':' + os.environ['PATH']
        os.execvp('busybox', ['busybox', 'ash', str(path)])


def expect(text, timeout=30):
    global pending
    needle = text.encode()
    deadline = time.monotonic() + timeout
    while needle not in pending:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(f'Timed out waiting for {text!r}: {pending[-3000:]!r}')
        if select.select([ui_fd], [], [], remaining)[0]:
            chunk = os.read(ui_fd, 65536)
            if not chunk:
                raise AssertionError(f'Manager exited before {text!r}')
            transcript.extend(chunk)
            pending += chunk
    pending = pending.split(needle, 1)[1]


def send(text):
    os.write(ui_fd, text.encode())


def finish_action():
    expect('Press Enter')
    send('\n')
    expect('Select option')


def install(choice):
    send('1\n')
    expect('Choose strategy')
    send(choice + '\n')
    expect('Start it afterwards?')
    send('y\n')
    finish_action()


def active():
    for line in entrypoint.read_text().splitlines():
        if line.startswith('Z2B_STRATEGY='):
            return line.split('=', 1)[1]
    raise AssertionError('Installed strategy has no selection')


def one_daemon():
    pids = run('pidof', 'nfqws2').split()
    parents = [p for p in pids if (Path('/proc') / p / 'status').read_text().split('PPid:\t', 1)[1].splitlines()[0] not in pids]
    assert len(parents) == 1, f'Duplicate native daemons: {pids}'


def close_manager():
    global ui_pid, ui_fd
    send('0\n')
    os.waitpid(ui_pid, 0)
    os.close(ui_fd)
    ui_pid = ui_fd = None


try:
    shutil.copytree('/opt/zapret2', base)
    # The installed openwrt-embedded release has *.lua.gz, not plain *.lua.
    # Keep the source-image test faithful to that layout; nfqws2 loads gzip itself.
    for lua_file in (base / 'lua').glob('*.lua'):
        lua_file.with_suffix('.lua.gz').write_bytes(gzip.compress(lua_file.read_bytes()))
        lua_file.unlink()
    shutil.rmtree(base / 'init.d/openwrt', ignore_errors=True)
    # Reproduce an existing upstream install, not just its disabled default.
    (base / 'config').write_text((base / 'config.default').read_text() + '\nFWTYPE=nftables\nIFACE_WAN=lima0\nDISABLE_IPV6=0\nWS_USER=nobody\nNFQWS2_ENABLE=1\nMODE_FILTER=none\n')
    user_hooks = root / 'user-hook-events'
    with (base / 'config').open('a') as config:
        config.write(f"user_up() {{ echo up >> '{user_hooks}'; }}\nuser_down() {{ echo down >> '{user_hooks}'; }}\nINIT_FW_POST_UP_HOOK=user_up\nINIT_FW_POST_DOWN_HOOK=user_down\n")
    custom = base / 'init.d/sysv/custom.d'
    custom.mkdir(exist_ok=True)
    entrypoint = custom / '50-zapret2-bypass'
    other = custom / '99-user-preserved'
    other.write_text('# unrelated user custom.d file\n')
    shutil.copytree(REPO, SOURCE, ignore=shutil.ignore_patterns('.git'))
    (SOURCE / '.lang').write_text('en\n')
    (root / 'bin').mkdir()
    run('busybox', '--install', '-s', str(root / 'bin'))
    run('sysctl', '-w', 'net.netfilter.nf_conntrack_tcp_be_liberal=1')
    # Two real dnsmasq processes: a deterministic bad upstream answer, and the
    # OpenWrt addn-hosts layout. All DNS changes are confined to this container.
    dns_config.parent.mkdir(parents=True, exist_ok=True)
    user_hosts.parent.mkdir(parents=True, exist_ok=True)
    user_hosts.write_text('192.0.2.55 untouched.example\n')
    upstream = root / 'upstream.conf'
    upstream.write_text('port=1053\nlisten-address=127.0.0.1\nbind-interfaces\nno-resolv\nno-hosts\nserver=127.0.0.53\naddress=/discord.com/162.159.136.232\n')
    dns_config.write_text('port=53\nlisten-address=127.0.0.1\nbind-interfaces\nno-resolv\nno-hosts\nserver=127.0.0.1#1053\naddn-hosts=/tmp/hosts\n')
    for config in (upstream, dns_config):
        dns_processes.append(subprocess.Popen(['dnsmasq', '--keep-in-foreground', '--conf-file=' + str(config), '--pid-file=', '--log-facility=-'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    time.sleep(.3)
    assert all(p.poll() is None for p in dns_processes), 'DNS test ports are unavailable'
    resolv.write_text('nameserver 127.0.0.1\n')
    check_dns(False)

    open_manager(SOURCE / 'service.sh')
    expect('Run guided setup?')
    send('y\n')
    expect('Choose strategy')
    send('2\n')
    expect('Start it afterwards?')
    send('y\n')
    finish_action()
    assert active() == 'sky'
    check_public_assets()
    one_daemon()
    print('PASS: first setup selects sky and starts one native daemon', flush=True)
    check_dns(True)
    assert user_hooks.read_text().splitlines()[-1] == 'up'
    run(str(base / 'init.d/sysv/zapret2'), 'stop')
    check_dns(False)
    assert user_hooks.read_text().splitlines()[-1] == 'down'
    # SysV leaves stderr inherited by the background daemon; do not capture it.
    subprocess.run([str(base / 'init.d/sysv/zapret2'), 'start'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    check_dns(True)
    assert user_hooks.read_text().splitlines()[-1] == 'up'
    discord_probe = subprocess.run(['python3', str(REPO / 'tools/test-sky-discord.py')],
                                   capture_output=True, text=True)
    print(discord_probe.stdout + discord_probe.stderr, flush=True)
    print('PASS: native start/stop installs/removes exact Discord DNS overrides; unrelated names preserved', flush=True)

    before = hashlib.sha256(entrypoint.read_bytes()).digest()
    send('1\n')
    expect('Choose strategy')
    send('0\n')
    finish_action()
    assert hashlib.sha256(entrypoint.read_bytes()).digest() == before
    one_daemon()
    print('PASS: cancellation preserves the installed strategy', flush=True)

    youtube = base / 'strategies/sky/youtube.txt'
    # A configured editor consumes stdin and edits the selected real file.
    edited = youtube.read_text() + '\n# user-owned list edit\n'
    send('7\n')
    expect('Select list')
    send('1\n')
    expect('Editing:')
    send(edited)
    send('\x04')
    finish_action()
    assert youtube.read_text() == edited

    # Upgrade an existing sky installation that predates the shared host group.
    (base / 'strategies/sky/shared.txt').unlink()
    native_args = base / 'strategies/sky/strategy.args'
    native_args.write_text(native_args.read_text().replace(f'--hostlist={base}/strategies/sky/shared.txt\n', ''))
    # Migrate the earlier DNS-only overlay without retaining its extra engine.
    config_file = base / 'config'
    config_file.write_text(config_file.read_text()
                           .replace('# BEGIN zapret2-openwrt strategy\nNFQWS2_ENABLE=0\n', '# BEGIN zapret2-openwrt Discord DNS\n')
                           .replace('# END zapret2-openwrt strategy', '# END zapret2-openwrt Discord DNS'))
    install('2')
    assert active() == 'sky' and youtube.read_text() == edited
    one_daemon()
    print('PASS: reinstall adds shared host coverage without replacing edited lists', flush=True)

    install('1')
    assert active() == 'flat'
    one_daemon()
    check_dns(False)
    install('2')
    assert active() == 'sky' and youtube.read_text() == edited and other.exists()
    one_daemon()
    print('PASS: sky -> flat -> sky preserves user lists and unrelated callbacks', flush=True)
    check_dns(True)

    # Exercise actual traffic through the installed native callback, not run.sh.
    for url in ('https://www.youtube.com/', 'https://discord.com/api/v10/gateway', 'https://anime-365.ru/users/login'):
        metrics = run('/usr/local/bin/curl-http3', '-4', '--noproxy', '*', '-fsS', '--max-time', '15', '-o', '/dev/null', '-w', '%{size_download}', url)
        assert int(metrics) > 0, url
        print(f'PASS: native sky completed {url} ({metrics} bytes)', flush=True)

    close_manager()
    shutil.rmtree(SOURCE)
    open_manager(COMMAND)
    expect('Select option')
    assert active() == 'sky'
    send('2\n')
    expect('Strategy: sky')
    finish_action()
    print('PASS: registered command retains sky without the temporary checkout', flush=True)

    install('1')
    before = entrypoint.read_bytes()
    args_file = PERSIST / 'strategies/sky/strategy.args'
    canonical = args_file.read_text()
    args_file.write_text(canonical + '\n--not-a-real-option\n')
    install('2')
    assert active() == 'flat' and entrypoint.read_bytes() == before
    one_daemon()
    args_file.write_text(canonical)
    print('PASS: invalid sky arguments roll back to the previous running strategy', flush=True)
    check_dns(False)
    install('2')
    check_dns(True)

    send('9\n')
    expect('Proceed?')
    send('y\n')
    os.waitpid(ui_pid, 0)
    os.close(ui_fd)
    ui_pid = ui_fd = None
    assert not entrypoint.exists() and other.exists() and youtube.read_text() == edited
    assert not (base / 'strategies/sky/strategy.args').exists()
    assert subprocess.run(['pidof', 'nfqws2'], capture_output=True).returncode != 0
    check_dns(False)
    assert not dns_hosts.exists()
    assert not (base / 'strategies/sky/discord-dns.sh').exists()
    restored = run('sh', '-c', 'ZAPRET_BASE="$1"; . "$1/config"; printf "%s" "$NFQWS2_ENABLE"', 'sh', str(base))
    assert restored == '1', 'Uninstall must restore the original upstream selection'
    print('PASS: uninstall removes managed runtime and leaves user data intact', flush=True)
    # Retain network failures, but still exercise rollback and uninstall first.
    assert discord_probe.returncode == 0, 'Discord network probe failed; see output above'
finally:
    if ui_pid is not None:
        os.kill(ui_pid, signal.SIGTERM)
        os.waitpid(ui_pid, 0)
        os.close(ui_fd)
    if (base / 'init.d/sysv/zapret2').exists():
        subprocess.run([str(base / 'init.d/sysv/zapret2'), 'stop'], capture_output=True)
    resolv.write_text(old_resolv)
    for process in dns_processes:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
    dns_config.unlink(missing_ok=True)
    user_hosts.unlink(missing_ok=True)
    run('sysctl', '-w', 'net.netfilter.nf_conntrack_tcp_be_liberal=' + old_sysctl)
    print(transcript.decode(errors='replace'))
    if COMMAND.is_symlink() and os.readlink(COMMAND) == str(PERSIST / 'service.sh'):
        COMMAND.unlink()
    shutil.rmtree(SOURCE, ignore_errors=True)
    shutil.rmtree(PERSIST, ignore_errors=True)
    shutil.rmtree(root)
