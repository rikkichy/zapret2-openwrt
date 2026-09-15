#!/usr/bin/env python3
"""Exercise the real manager and upstream native service in a disposable Docker VM.

Requires the sky image, BusyBox, a read-only /repo mount, --privileged, and the
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
if subprocess.run(['nft', 'list', 'table', 'inet', 'zapret2'], capture_output=True).returncode == 0:
    raise SystemExit('An existing zapret2 firewall is present; refusing to touch it')


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


root = Path(tempfile.mkdtemp(prefix='z2b-manager-'))
root.chmod(0o755)
base = root / 'base'
ui_pid = None
ui_fd = None
pending = b''
transcript = bytearray()
old_sysctl = run('sysctl', '-n', 'net.netfilter.nf_conntrack_tcp_be_liberal').strip()


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
    (base / 'config').write_text((base / 'config.default').read_text() + '\nFWTYPE=nftables\nIFACE_WAN=lima0\nDISABLE_IPV6=0\nWS_USER=nobody\n')
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

    open_manager(SOURCE / 'service.sh')
    expect('Run guided setup?')
    send('y\n')
    expect('Choose strategy')
    send('2\n')
    expect('Start it afterwards?')
    send('y\n')
    finish_action()
    assert active() == 'sky'
    one_daemon()
    print('PASS: first setup selects sky and starts one native daemon', flush=True)

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
    install('2')
    assert active() == 'sky' and youtube.read_text() == edited
    one_daemon()
    print('PASS: reinstall adds shared host coverage without replacing edited lists', flush=True)

    install('1')
    assert active() == 'flat'
    one_daemon()
    install('2')
    assert active() == 'sky' and youtube.read_text() == edited and other.exists()
    one_daemon()
    print('PASS: sky -> flat -> sky preserves user lists and unrelated callbacks', flush=True)

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

    send('9\n')
    expect('Proceed?')
    send('y\n')
    os.waitpid(ui_pid, 0)
    os.close(ui_fd)
    ui_pid = ui_fd = None
    assert not entrypoint.exists() and other.exists() and youtube.read_text() == edited
    assert not (base / 'strategies/sky/strategy.args').exists()
    assert subprocess.run(['pidof', 'nfqws2'], capture_output=True).returncode != 0
    print('PASS: uninstall removes managed runtime and leaves user data intact', flush=True)
finally:
    if ui_pid is not None:
        os.kill(ui_pid, signal.SIGTERM)
        os.waitpid(ui_pid, 0)
        os.close(ui_fd)
    if (base / 'init.d/sysv/zapret2').exists():
        subprocess.run([str(base / 'init.d/sysv/zapret2'), 'stop'], capture_output=True)
    run('sysctl', '-w', 'net.netfilter.nf_conntrack_tcp_be_liberal=' + old_sysctl)
    print(transcript.decode(errors='replace'))
    if COMMAND.is_symlink() and os.readlink(COMMAND) == str(PERSIST / 'service.sh'):
        COMMAND.unlink()
    shutil.rmtree(SOURCE, ignore_errors=True)
    shutil.rmtree(PERSIST, ignore_errors=True)
    shutil.rmtree(root)
