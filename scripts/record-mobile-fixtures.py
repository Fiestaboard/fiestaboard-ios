#!/usr/bin/env python3
"""Runs only inside the source-pinned Docker hub. Save real response bytes unchanged."""
import hashlib
import json
import os
from pathlib import Path

os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
os.environ['FIESTABOARD_DATA_DIR'] = '/tmp/cx-i5-data'
from fastapi.testclient import TestClient
from src.api_server import app
from src.auth import routes
from src.auth import service

out = Path('/fixtures')
out.mkdir(exist_ok=True)
auth = service.AuthService(Path('/tmp/cx-i5-auth.json'))
auth.create_initial_user('contract_admin', 'cx-fixture-password-only')
service._service = auth
routes._FAILED_ATTEMPTS.clear()
client = TestClient(app)
meta = {'client_id':'fiestaboard-ios','device_name':'CANON iPhone','app_version':'1.0'}
request_manifest = Path("/requests.json").read_bytes()
requests = {entry["id"]:entry for entry in json.loads(request_manifest)["requests"]}
recorded = []
def capture(name, method, path, expected, **kwargs):
    if requests[name] != {"id":name,"method":method,"path":path,"status":expected}:
        raise RuntimeError("request manifest drift: " + name)
    response = client.request(method, path, **kwargs)
    if response.status_code != expected:
        raise RuntimeError(f'{name}: expected {expected}, received {response.status_code}: {response.text}')
    file = name + '.json'
    (out / file).write_bytes(response.content)
    headers = {key:value for key,value in response.headers.items() if key.lower() in ('content-type','retry-after','date','cache-control')}
    recorded.append({'file':file,'method':method,'path':path,'status':response.status_code,'headers':headers,
                     'sha256':hashlib.sha256(response.content).hexdigest()})
    return response
capture('auth-status-signed-out','GET','/auth/status',200)
capture('device-login-invalid','POST','/auth/device/login',401,json={**meta,'username':'contract_admin','password':'incorrect-fixture-password'})
login = capture('device-login','POST','/auth/device/login',200,json={**meta,'username':'contract_admin','password':'cx-fixture-password-only'})
token = login.json()['access_token']
headers={'Authorization':'Bearer '+token}
capture('auth-status-mobile','GET','/auth/status',200,headers=headers)
capture('pairing-invalid','POST','/auth/pairing/claim',400,json={**meta,'pairing_code':'invalid-fixture-code'})
# Advance only this isolated hub's injected session-registry clock to produce
# a genuine expired-session response. Response bytes are never synthesized.
now = auth.sessions.clock_ms()
auth.sessions.clock_ms = lambda: now + 366 * 86400 * 1000
capture('device-session-expired','GET','/boards',401,headers=headers)
auth.sessions.clock_ms = lambda: now
capture('device-session-revoke','DELETE','/auth/device/session',200,headers=headers)
capture('device-session-revoked','GET','/boards',401,headers=headers)
# The recorded credential is revoked before leaving the isolated process.
for _ in range(10):
    client.post('/auth/device/login',json={**meta,'username':'contract_admin','password':'incorrect-fixture-password'})
capture('device-login-locked','POST','/auth/device/login',429,json={**meta,'username':'contract_admin','password':'cx-fixture-password-only'})
source={'hubRepository':'Fiestaboard/FiestaBoard','hubCommit':os.environ['CX_HUB_COMMIT'],
        'requestManifestSHA256':hashlib.sha256(request_manifest).hexdigest(),'recorder':'scripts/record-mobile-fixtures.py','method':'Docker built from immutable git archive; real FastAPI HTTP boundary',
        'credentialSafety':'Synthetic account only; recorded mobile token revoked before container exit', 'responses':recorded}
(out/'SOURCE.json').write_text(json.dumps(source,indent=2)+'\n')
print(f'Recorded {len(recorded)} unchanged HTTP responses')
