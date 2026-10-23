"""Validate the production Caddyfile and exercise private/public routes in Caddy."""
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import uuid

root = Path(__file__).resolve().parent
image = 'caddy:2-alpine'
env = {k: v for k, v in os.environ.items() if k not in
       ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH')}
docker = ['docker', '--host=unix:///var/run/docker.sock']

def run(*args):
    return subprocess.run(docker + list(args), env=env, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

run('run', '--rm', '-e', 'TETHERED_DOMAIN=localhost', '-v',
    f'{root / "Caddyfile"}:/etc/caddy/Caddyfile:ro', image,
    'caddy', 'validate', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile')

# Only replace TLS and upstream addresses; the access rules are the exact
# production rules. A second Caddy listener stands in for the backend.
config = (root / 'Caddyfile').read_text()
config, count = re.subn(r'\ttls \{\n\t\tissuer acme \{\n\t\t\tdisable_http_challenge\n\t\t\}\n\t\}\n', '', config)
assert count == 1
config = '{\n admin off\n}\n' + config.replace('server:8090', '127.0.0.1:8090').replace('centrifugo:8000', '127.0.0.1:8090')
config += '\n:8090 {\n respond "backend" 200\n}\n'
name = 'tethered-caddy-test-' + uuid.uuid4().hex[:10]
with socket.socket() as s:
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]

def status(path):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}' + path, timeout=2) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code

with tempfile.TemporaryDirectory(prefix='tethered-caddy-') as temp:
    path = Path(temp) / 'Caddyfile'
    path.write_text(config)
    try:
        run('run', '-d', '--name', name, '-e', 'TETHERED_DOMAIN=:8080',
            '-p', f'127.0.0.1:{port}:8080', '-v', f'{path}:/etc/caddy/Caddyfile:ro', image)
        for _ in range(50):
            try:
                if status('/api/health') == 200:
                    break
            except (OSError, urllib.error.URLError):
                pass
            time.sleep(0.1)
        assert status('/api/health') == 200, 'Caddy did not start'
        for target in ['/_', '/_/', '/_/index.html',
                       '/api/collections/_superusers',
                       '/api/collections/_superusers/auth-with-password',
                       '/api/collections/pbc_3142635823/auth-with-password',
                       '/api/collections/%5Fsuperusers/auth-with-password']:
            assert status(target) == 404, target
        for target in ['/api/health', '/api/collections/users/auth-with-password',
                       '/api/watch/token', '/connection/websocket', '/watch/room/']:
            assert status(target) == 200, target
        print('ok: Caddy validates; admin and superuser routes are private, app routes stay accessible')
    except Exception:
        print(run('logs', name).stderr[-2500:])
        raise
    finally:
        run('rm', '-f', name)
