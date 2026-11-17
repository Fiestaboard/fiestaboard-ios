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
if 'override-duration-max' in requests:
    capture('override-duration-max','POST','/settings/temporary-override',200,json={'board_id':kitchen,'page_id':page_id,'duration_minutes':480,'revert_mode':'schedule'})
    capture('override-duration-too-long','POST','/settings/temporary-override',422,json={'board_id':kitchen,'page_id':page_id,'duration_minutes':481,'revert_mode':'schedule'})
if 'undo-capability' in requests:
    capture('undo-capability','GET',f'/settings/temporary-override?board_id={kitchen}',200)
    receipt = capture('undo-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}&undo=true',200).json()
    restore = {'board_id':kitchen,'undo_token':receipt['undo_token']}
    capture('undo-wrong-display','POST','/settings/temporary-override/undo',409,json={**restore,'board_id':desk})
    capture('undo-unauthorized','POST','/settings/temporary-override/undo',401,request_headers={},json=restore)
    capture('undo-extra-fields','POST','/settings/temporary-override/undo',422,json={**restore,'duration_minutes':480})
    capture('undo-restored','POST','/settings/temporary-override/undo',200,json=restore)
    capture('undo-used','POST','/settings/temporary-override/undo',409,json=restore)
    receipt = capture('undo-stale-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}&undo=true',200).json()
    capture('undo-newer-selection','PUT',f'/v1/boards/{kitchen}/active-page',200,json={'page_id':page_id})
    capture('undo-stale','POST','/settings/temporary-override/undo',409,json={'board_id':kitchen,'undo_token':receipt['undo_token']})
    capture('undo-indefinite-create','POST','/settings/temporary-override',200,json={'board_id':kitchen,'page_id':page_id,'revert_mode':'schedule'})
    receipt = capture('undo-indefinite-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}&undo=true',200).json()
    capture('undo-indefinite-restored','POST','/settings/temporary-override/undo',200,json={'board_id':kitchen,'undo_token':receipt['undo_token']})
    capture('undo-legacy-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}',200)
    capture('undo-empty-cancel','DELETE',f'/settings/temporary-override?board_id={kitchen}&undo=true',200)
if 'home-paused' in requests:
    from datetime import datetime, timedelta, timezone
    from src import silence_queue
    capture('pause-accepted','POST',f'/settings/board/{kitchen}/pause',200,json={'paused':True})
    capture('home-paused','GET',f'/v1/boards/{kitchen}',200)
    capture('resume-other-display','POST',f'/settings/board/{desk}/pause',200,json={'paused':False})
    capture('home-still-paused','GET',f'/v1/boards/{kitchen}',200)
    capture('pause-invalid-body','POST',f'/settings/board/{kitchen}/pause',422,json={'paused':'no'})
    capture('resume-unauthorized','POST',f'/settings/board/{kitchen}/pause',401,request_headers={},json={'paused':False})
    capture('resume-accepted','POST',f'/settings/board/{kitchen}/pause',200,json={'paused':False})
    capture('home-resumed','GET',f'/v1/boards/{kitchen}',200)
    clock = datetime.now(timezone.utc)
    silence_config = {'board_id':kitchen,'enabled':True,'mode':'freeze','show_queued_on_exit':True,
        'start_time':(clock-timedelta(hours=1)).strftime('%H:%M+00:00'),
        'end_time':(clock+timedelta(hours=1)).strftime('%H:%M+00:00')}
    capture('silence-config','PUT','/settings/silence-schedule',200,json=silence_config)
    capture('silence-empty','GET',f'/silence-status?board_id={kitchen}',200)
    # Seed actual typed domain intents; the GET computes the production summary.
    # This fixture does not pretend to send to an unconfigured physical output.
    silence_queue.hold(silence_queue.HeldSend.text('Package delivered',board_id=kitchen))
    capture('silence-held','GET',f'/silence-status?board_id={kitchen}',200)
    silence_queue.hold(silence_queue.HeldSend.text('New reminder',board_id=kitchen))
    capture('silence-replacement','GET',f'/silence-status?board_id={kitchen}',200)
    capture('silence-other-display','GET',f'/silence-status?board_id={desk}',200)
    capture('silence-holds-disabled','PUT','/settings/silence-schedule',200,json={**silence_config,'show_queued_on_exit':False})
    capture('silence-without-hold','GET',f'/silence-status?board_id={kitchen}',200)
    capture('silence-discard-forbidden','DELETE',f'/silence-queue?board_id={kitchen}',403)
    capture('pause-with-context','POST',f'/settings/board/{kitchen}/pause',200,json={'paused':True})
    capture('override-before-resume','POST','/settings/temporary-override',200,json={'board_id':kitchen,'page_id':page_id,'duration_minutes':180,'revert_mode':'schedule'})
    capture('silence-before-resume','GET',f'/silence-status?board_id={kitchen}',200)
    capture('resume-with-context','POST',f'/settings/board/{kitchen}/pause',200,json={'paused':False})
    capture('override-after-resume','GET',f'/settings/temporary-override?board_id={kitchen}',200)
    capture('silence-after-resume','GET',f'/silence-status?board_id={kitchen}',200)
revoke=client.delete('/auth/device/session',headers=headers)
assert revoke.status_code == 200, revoke.text
source={'hubRepository':'Fiestaboard/FiestaBoard','hubCommit':os.environ['CX_HUB_COMMIT'],
    'requestManifestSHA256':hashlib.sha256(request_manifest).hexdigest(),
    'recorder':'scripts/record-home-fixtures.py','method':os.environ.get('CX_RECORDING_METHOD','Docker built from immutable git archive; real FastAPI HTTP boundary'),
    'credentialSafety':'Synthetic account; mobile token never recorded and revoked before process exit',
    'scenario':{'kitchen':kitchen,'desk':desk,'pageID':page_id},'responses':recorded}
if 'home-paused' in requests:
    source['scenario']['heldSetup'] = 'Production silence_queue.HeldSend.text/hold; real GET summary; no physical send'
if os.environ.get('CX_DOCKER_IMAGE'):
    import importlib.metadata
    import platform
    source['dockerImage'] = os.environ['CX_DOCKER_IMAGE']
    source['dockerBase'] = json.loads(os.environ['CX_DOCKER_BASE'])
    source['pythonVersion'] = platform.python_version()
    source['dependencyManifestSHA256'] = hashlib.sha256(Path('/cx-dependencies.txt').read_bytes()).hexdigest()
    packages = sorted(f'{d.metadata["Name"]}=={d.version}' for d in importlib.metadata.distributions())
    (out/'environment.txt').write_text('\n'.join(packages)+'\n')
(out/'SOURCE.json').write_text(json.dumps(source,indent=2)+'\n')
print(f'Recorded {len(recorded)} unchanged Home HTTP responses')
