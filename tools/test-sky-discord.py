#!/usr/bin/env python3
"""Run with sky active in Docker; verify Discord with TCP timestamps disabled.

Uses public endpoints only. No login, live voice, or screenshare claim.
The dedicated VM's timestamp setting is restored even when a probe fails.
"""
import base64
import hashlib
import json
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import tempfile
from urllib.parse import urlsplit

if not Path('/.dockerenv').exists():
    raise SystemExit('Docker ONLY')


def receive(stream, length):
    data = bytearray()
    while len(data) < length:
        chunk = stream.read(length - len(data))
        if not chunk:
            raise EOFError('Gateway closed before sending a complete frame')
        data.extend(chunk)
    return bytes(data)


def gateway():
    host = 'gateway.discord.gg'
    address = socket.getaddrinfo(host, 443, socket.AF_INET, socket.SOCK_STREAM)[0][4]
    with socket.create_connection(address, timeout=12) as raw:
        with ssl.create_default_context().wrap_socket(raw, server_hostname=host) as conn:
            # RFC 6455 requires a 16-byte nonce.
            key = base64.b64encode(b'sky-discord-test!').decode()
            conn.sendall((f'GET /?v=10&encoding=json HTTP/1.1\r\nHost: {host}\r\n'
                          f'Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n'
                          'Sec-WebSocket-Version: 13\r\n\r\n').encode())
            with conn.makefile('rb') as stream:
                assert stream.readline().split()[1] == b'101', 'Gateway upgrade failed'
                headers = {}
                while (line := stream.readline()) != b'\r\n':
                    if not line:
                        raise EOFError('Incomplete upgrade headers')
                    name, value = line.decode().split(':', 1)
                    headers[name.lower()] = value.strip()
                expected = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
                assert headers.get('sec-websocket-accept') == expected
                first, second = receive(stream, 2)
                assert first == 0x81 and not second & 0x80, 'Expected unmasked text Hello'
                length = second & 127
                if length == 126:
                    length = struct.unpack('!H', receive(stream, 2))[0]
                elif length == 127:
                    length = struct.unpack('!Q', receive(stream, 8))[0]
                assert length <= 65536, 'Unexpected Hello size'
                hello = json.loads(receive(stream, length))
                assert hello['op'] == 10 and hello['d']['heartbeat_interval'] > 0
                print(json.dumps({'check': 'gateway-websocket-hello', 'ok': True}), flush=True)


def https(url, kind, expected_sha256=None):
    with tempfile.NamedTemporaryFile() as body:
        result = subprocess.run(['curl-http3', '-4', '--noproxy', '*', '-fsS',
                                 '--connect-timeout', '8', '--max-time', '25',
                                 '-o', body.name, url], capture_output=True, text=True)
        assert result.returncode == 0, (url, result.stderr)
        data = Path(body.name).read_bytes()
        if kind == 'gateway':
            assert json.loads(data)['url'] == 'wss://gateway.discord.gg'
        elif kind == 'png':
            assert data.startswith(b'\x89PNG\r\n\x1a\n')
        elif kind == 'manifest':
            manifest = json.loads(data)
            assert manifest['full']['host_version'] and manifest['required_modules']
        elif kind == 'module':
            assert hashlib.sha256(data).hexdigest() == expected_sha256
        else:
            assert b'</html>' in data.lower(), url
        print(json.dumps({'check': kind, 'url': url, 'bytes': len(data), 'ok': True}), flush=True)
        return data


old = subprocess.check_output(['sysctl', '-n', 'net.ipv4.tcp_timestamps'], text=True).strip()
try:
    subprocess.run(['sysctl', '-w', 'net.ipv4.tcp_timestamps=0'], check=True)
    manifest = json.loads(https(
        'https://updates.discord.com/distributions/app/manifests/latest'
        '?channel=stable&platform=osx&arch=arm64&platform_version=26.6.2'
        '&client_version=90413&install_id=00000000-0000-4000-8000-000000000001', 'manifest'))
    module = manifest['modules']['discord_utils']['full']
    parsed = urlsplit(module['url'])
    assert parsed.scheme == 'https' and parsed.hostname.endswith('.discordapp.net')
    https(module['url'], 'module', module['package_sha256'])
    https('https://discord.com/api/v10/gateway', 'gateway')
    https('https://discord.com/', 'html')
    https('https://cdn.discordapp.com/embed/avatars/0.png', 'png')
    gateway()
    https('https://example.com/', 'html')
finally:
    subprocess.run(['sysctl', '-w', f'net.ipv4.tcp_timestamps={old}'], check=True)
