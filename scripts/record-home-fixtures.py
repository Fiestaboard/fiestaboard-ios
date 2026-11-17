#!/usr/bin/env python3
"""Record seeded I7 Home scenarios through the immutable hub's real HTTP boundary."""
import hashlib
import json
import os
from pathlib import Path

os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
data_root = Path(os.environ.get('CX_DATA_DIR', '/tmp/cx-i7-data'))
data_root.mkdir(parents=True, exist_ok=True)
os.environ['FIESTABOARD_DATA_DIR'] = str(data_root)
from fastapi.testclient import TestClient
from src.api_server import app
from src.auth import routes, service
from src.settings.service import get_settings_service

out = Path(os.environ.get('CX_FIXTURE_OUT', '/fixtures'))
out.mkdir(exist_ok=True)
auth = service.AuthService(data_root / 'auth.json')
auth.create_initial_user('contract_admin', 'cx-fixture-password-only')
service._service = auth
routes._FAILED_ATTEMPTS.clear()
client = TestClient(app)
login = client.post('/auth/device/login', json={'client_id':'fiestaboard-ios','device_name':'CANON iPhone','app_version':'1.0','username':'contract_admin','password':'cx-fixture-password-only'})
assert login.status_code == 200, login.text
headers = {'Authorization':'Bearer '+login.json()['access_token']}
settings = get_settings_service()
boards = settings.set_boards([
    {'id':'cx-kitchen','device_type':'flagship','name':'Kitchen board','output':'none'},
    {'id':'cx-desk','device_type':'note','name':'Desk Note','output':'none'},
]).boards
kitchen, desk = boards[0]['id'], boards[1]['id']
page = client.post('/v1/pages', headers=headers, json={'name':'Welcome','type':'template','device_type':'flagship','template':['WELCOME','','','','','']})
assert page.status_code == 201, page.text
page_id = page.json()['id']
settings.set_active_page_id(page_id, board_id=kitchen)
request_manifest = Path(os.environ.get('CX_REQUEST_MANIFEST', '/requests.json')).read_bytes()
requests = {entry['id']:entry for entry in json.loads(request_manifest)['requests']}
recorded=[]
def capture(name, method, path, expected, request_headers=None, **kwargs):
    expected_entry={'id':name,'method':method,'path':path.replace(kitchen,'{kitchen}').replace(desk,'{desk}'),'status':expected}
    assert requests[name] == expected_entry, (name,expected_entry,requests[name])
    response=client.request(method,path,headers=headers if request_headers is None else request_headers,**kwargs)
    assert response.status_code == expected, (name,response.status_code,response.text)
    filename=name+'.json'
    (out/filename).write_bytes(response.content)
    recorded.append({'file':filename,'method':method,'path':path,'status':expected,
        'headers':{k:v for k,v in response.headers.items() if k.lower() in ('content-type','date','cache-control')},
        'sha256':hashlib.sha256(response.content).hexdigest()})
    return response
if 'home-version' in requests:
    capture('home-version','GET','/version',200)
    capture('page-select','PUT',f'/v1/boards/{kitchen}/active-page',200,json={'page_id':page_id})
    capture('page-select-unauthorized','PUT',f'/v1/boards/{kitchen}/active-page',401,request_headers={},json={'page_id':page_id})
    capture('override-cancel-unauthorized','DELETE',f'/settings/temporary-override?board_id={kitchen}',401,request_headers={})
capture('home-boards','GET','/v1/boards',200)
capture('home-manual','GET',f'/v1/boards/{kitchen}',200)
capture('override-timed','POST','/settings/temporary-override',200,json={'board_id':kitchen,'page_id':page_id,'duration_minutes':180,'revert_mode':'schedule'})
capture('home-override','GET',f'/v1/boards/{kitchen}',200)
capture('active-override','GET',f'/schedules/active/page?board_id={kitchen}',200)
capture('override-detail','GET',f'/settings/temporary-override?board_id={kitchen}',200)
capture('other-display','GET',f'/v1/boards/{desk}',200)
capture('override-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}',200)
capture('override-canceled','GET',f'/settings/temporary-override?board_id={kitchen}',200)
capture('override-indefinite','POST','/settings/temporary-override',200,json={'board_id':kitchen,'page_id':page_id,'revert_mode':'schedule'})
capture('home-indefinite','GET',f'/v1/boards/{kitchen}',200)
capture('home-silence','GET',f'/silence-status?board_id={kitchen}',200)
capture('home-runtime','GET','/v1/status',200)
revoke=client.delete('/auth/device/session',headers=headers)
assert revoke.status_code == 200, revoke.text
source={'hubRepository':'Fiestaboard/FiestaBoard','hubCommit':os.environ['CX_HUB_COMMIT'],
    'requestManifestSHA256':hashlib.sha256(request_manifest).hexdigest(),
    'recorder':'scripts/record-home-fixtures.py','method':os.environ.get('CX_RECORDING_METHOD','Docker built from immutable git archive; real FastAPI HTTP boundary'),
    'credentialSafety':'Synthetic account; mobile token never recorded and revoked before process exit',
    'scenario':{'kitchen':kitchen,'desk':desk,'pageID':page_id},'responses':recorded}
(out/'SOURCE.json').write_text(json.dumps(source,indent=2)+'\n')
print(f'Recorded {len(recorded)} unchanged Home HTTP responses')
