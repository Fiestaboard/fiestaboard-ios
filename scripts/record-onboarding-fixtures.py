#!/usr/bin/env python3
"""Run inside an owned immutable Docker runtime; record original HTTP bytes, never fabricate replies."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
os.environ['FIESTABOARD_DATA_DIR'] = '/tmp/cx-i9-data'
from fastapi.testclient import TestClient
from src.api_server import app
from src.auth import routes, service
from src.auth.password_reset import RESET_TTL_MS

out = Path('/fixtures')
manifest = Path('/requests.json').read_bytes()
expected = {row['id']: row for row in json.loads(manifest)['requests']}
auth = service.AuthService(Path('/tmp/cx-i9-auth/auth.json'))
auth.create_initial_user('contract_admin', 'cx-fixture-password-only')
service._service = auth
routes._FAILED_ATTEMPTS.clear()
client = TestClient(app)
meta = {'client_id': 'fiestaboard-ios', 'device_name': 'CANON iPhone', 'app_version': '1.0'}
records = []
tokens = []

def capture(name, method, path, status, **kwargs):
    assert expected[name] == {'id': name, 'method': method, 'path': path, 'status': status}, name
    response = client.request(method, path, **kwargs)
    if response.status_code != status:
        raise RuntimeError(f'{name}: expected HTTP {status}, received {response.status_code}')
    filename = name + '.json'
    (out / filename).write_bytes(response.content)
    headers = {k: v for k, v in response.headers.items() if k.lower() in ('content-type', 'retry-after', 'date', 'cache-control')}
    records.append({'file': filename, 'method': method, 'path': path, 'status': response.status_code,
                    'headers': headers, 'sha256': hashlib.sha256(response.content).hexdigest()})
    return response

def login(name, password):
    response = capture(name, 'POST', '/auth/device/login', 200,
                       json={**meta, 'username': 'contract_admin', 'password': password})
    token = response.json()['access_token']
    tokens.append(token)
    return {'Authorization': 'Bearer ' + token}

def reset(name, code, password='cx-replaced-fixture-password', status=400, **extra):
    return capture(name, 'POST', '/auth/password-reset', status,
                   json={'code': code, 'new_password': password, **extra})

# Code creation and injected clocks seed only this isolated fixture process;
# every recorded result still crosses the actual FastAPI HTTP boundary.
try:
    before = login('device-login-before-reset', 'cx-fixture-password-only')
    reset('reset-invalid-code', 'fb_reset_invalid-contract')
    code, _ = auth.sessions.create_password_reset('contract_admin', RESET_TTL_MS)
    reset('reset-weak-password', code, 'short', 422)
    reset('reset-code-after-weak', code, status=200)
    reset('reset-code-reused', code)
    capture('device-session-after-reset', 'GET', '/boards', 401, headers=before)
    capture('login-old-password', 'POST', '/auth/device/login', 401,
            json={**meta, 'username': 'contract_admin', 'password': 'cx-fixture-password-only'})
    after = login('device-login-after-reset', 'cx-replaced-fixture-password')
    capture('auth-status-after-reset', 'GET', '/auth/status', 200, headers=after)
    old, _ = auth.sessions.create_password_reset('contract_admin', RESET_TTL_MS)
    auth.sessions.create_password_reset('contract_admin', RESET_TTL_MS)
    reset('reset-superseded-code', old)
    expired, _ = auth.sessions.create_password_reset('contract_admin', RESET_TTL_MS)
    clock = auth.sessions.clock_ms
    now = clock()
    auth.sessions.clock_ms = lambda: now + RESET_TTL_MS + 1
    try:
        reset('reset-expired-code', expired)
    finally:
        auth.sessions.clock_ms = clock
    reset('reset-extra-field', 'fb_reset_invalid-contract', status=422, username='contract_admin')
    reset('reset-password-too-long', 'fb_reset_invalid-contract', 'a' * 1025, 422)
    # Ten actual invalid reset requests exercise the shared IP failure counter.
    # Using password checks here makes the scenario depend on bcrypt throughput:
    # a slow runner can spread ten logins beyond the real 60-second window.
    routes._FAILED_ATTEMPTS.clear()
    for _ in range(10):
        response = client.post('/auth/password-reset', json={'code': 'fb_reset_invalid-contract', 'new_password': 'cx-replaced-fixture-password'})
        assert response.status_code == 400
    reset('reset-shared-lockout', 'fb_reset_invalid-contract', status=429)
    capture('device-login-shared-lockout', 'POST', '/auth/device/login', 429,
            json={**meta, 'username': 'contract_admin', 'password': 'cx-replaced-fixture-password'})
    capture('device-session-revoke', 'DELETE', '/auth/device/session', 200, headers=after)
    capture('device-session-finally-revoked', 'GET', '/boards', 401, headers=after)
finally:
    # Revoke even when a later assertion aborts recording; never publish live fixture authority.
    auth.sessions.clear_password_resets()
    for token in tokens:
        client.delete('/auth/device/session', headers={'Authorization': 'Bearer ' + token})

assert [row['file'][:-5] for row in records] == list(expected), 'request order/coverage drift'
environment = subprocess.check_output([sys.executable, '-m', 'pip', 'freeze'])
(out / 'environment.txt').write_bytes(environment)
source = {'hubRepository': 'Fiestaboard/FiestaBoard', 'hubCommit': os.environ['CX_HUB_COMMIT'],
          'requestManifestSHA256': hashlib.sha256(manifest).hexdigest(),
          'recorderSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'dependencyLockSHA256': hashlib.sha256(Path('/cx-dependencies.txt').read_bytes()).hexdigest(),
          'environmentSHA256': hashlib.sha256(environment).hexdigest(),
          'dockerImageID': os.environ['CX_DOCKER_IMAGE'], 'dockerBaseDigests': json.loads(os.environ['CX_DOCKER_BASE']),
          'method': 'Immutable git archive in separately built pinned Python Docker image; actual FastAPI HTTP boundary',
          'credentialSafety': 'Synthetic contract_admin only; reset codes cleared and both recorded mobile tokens revoked before exit',
          'setup': 'Internal code creation/clock only seed reset states; ten actual invalid reset requests seed shared IP lockout',
          'responses': records}
(out / 'SOURCE.json').write_text(json.dumps(source, indent=2) + '\n')
print(f'Recorded {len(records)} unchanged onboarding HTTP responses; synthetic authority revoked')
