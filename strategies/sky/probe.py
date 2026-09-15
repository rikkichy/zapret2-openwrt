#!/usr/bin/env python3
"""Docker-only, unauthenticated service probes. JSONL records include real failures.

Run via run.sh for the candidate, directly in the same Docker topology for a
baseline. This checks bodies, not video playback, WebSocket Hello, or live voice.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

if not Path('/.dockerenv').exists():
    sys.exit('Docker ONLY')

# Minimum completed body bytes and the transports each endpoint is tested on.
# Proton did not advertise h3. Anime365's TCP peer rejects forced TLS 1.3;
# test normal HTTPS negotiation there, while retaining the rejection evidence.
URLS = {
    'https://www.youtube.com/': (100000, ('tls12', 'tls13', 'h3')),
    'https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg': (10000, ('tls12', 'tls13', 'h3')),
    'https://discord.com/': (10000, ('tls12', 'tls13', 'h3')),
    'https://discord.com/api/v10/gateway': (1, ('tls12', 'tls13', 'h3')),
    'https://anime-365.ru/users/login': (100000, ('https', 'h3')),
    'https://smotret-anime.online/users/login': (100000, ('https', 'h3')),
    'https://proton.me/': (100000, ('tls12', 'tls13')),
    'https://account.proton.me/login': (5000, ('tls12', 'tls13')),
    'https://drive.proton.me/': (5000, ('tls12', 'tls13')),
    'https://calendar.proton.me/': (4000, ('tls12', 'tls13')),
    'https://pass.proton.me/': (4000, ('tls12', 'tls13')),
    'https://protonvpn.com/': (100000, ('tls12', 'tls13')),
}
PROTOCOLS = {
    'tls12': ['--http2', '--tlsv1.2', '--tls-max', '1.2'],
    'tls13': ['--http2', '--tlsv1.3'],
    'https': ['--http2', '--tlsv1.2'],
    'h3': ['--http3-only'],
}


def probe(item):
    attempt, protocol, url = item
    with tempfile.NamedTemporaryFile() as body:
        result = subprocess.run([
            '/usr/local/bin/curl-http3', '-4', '--noproxy', '*', '-sS',
            '--connect-timeout', '6', '--max-time', '15',
            *PROTOCOLS[protocol], '-o', body.name, '-w', '%{json}', url,
        ], capture_output=True, text=True, timeout=20)
        metrics = json.loads(result.stdout or '{}')
        status = metrics.get('http_code', 0)
        size = metrics.get('size_download', 0)
        ok = result.returncode == 0 and status == 200 and size >= URLS[url][0]
        if protocol == 'h3':
            ok = ok and metrics.get('http_version') == '3'
        if ok and url.endswith('/gateway'):
            ok = json.load(body).get('url') == 'wss://gateway.discord.gg'
    return {
        'attempt': attempt, 'protocol': protocol, 'url': url, 'ok': ok,
        'exit': result.returncode, 'status': status, 'bytes': size,
        'ip': metrics.get('remote_ip'), 'http_version': metrics.get('http_version'),
        'seconds': metrics.get('time_total'), 'error': result.stderr.strip(),
    }


if __name__ == '__main__':
    repeats = int(os.environ.get('REPEATS', '5'))
    if not 1 <= repeats <= 20:
        sys.exit('REPEATS must be between 1 and 20')
    passed = True
    # Bounded parallelism; each invocation creates a fresh connection, no retries.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for row in pool.map(probe, (
            (attempt, protocol, url)
            for attempt in range(1, repeats + 1)
            for url, (_, protocols) in URLS.items()
            for protocol in protocols
        )):
            print(json.dumps(row), flush=True)
            passed = passed and row['ok']
    sys.exit(0 if passed else 1)
