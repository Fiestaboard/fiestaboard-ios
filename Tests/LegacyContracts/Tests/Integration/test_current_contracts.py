"""Replay scoped current-source HTTP/storage contracts in fenced Docker only.

No app lifespan, provider calls, hardware writes or deployment claims. Dynamic
ids, revisions and wall-clock metadata are replaced consistently for replay.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import tempfile
from unittest.mock import Mock, patch

SOURCE = 'b5eac069dce10945eac61e1fdadf6ee4a903ba08'
VERSION = '10.1.17'
FIXTURE = Path('/contract-fixtures/current/bootstrap-control.json')


def capture():
    if not Path('/.dockerenv').exists():
        raise RuntimeError('Backend imports require isolated Docker')
    with patch('src.display_runtime.get_service', return_value=None), tempfile.TemporaryDirectory(prefix='current-contracts-') as tmp:
        os.environ['FIESTABOARD_DATA_DIR'] = tmp
        os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
        from fastapi.testclient import TestClient
        import src
        from src.api_server import app
        from src.auth import service as auth, routes as auth_routes
        from src.settings.service import get_settings_service
        from src.pages.service import get_page_service
        from src.schedules.service import get_schedule_service
        from src.collections.service import get_collection_service
        from src import display_runtime
        from src.config_manager import get_config_manager
        assert src.__version__ == VERSION
        assert display_runtime.get_service() is None
        auth._service = auth.AuthService(Path(tmp)/'auth.json')
        auth_routes._FAILED_ATTEMPTS.clear()
        get_config_manager().set_general({'instance_name':'Fixture room'})
        client = TestClient(app)  # Never enter lifespan.
        settings = get_settings_service()
        settings.set_boards([{'id':'contract-board','device_type':'flagship','name':'Contract board'}])
        settings.set_output_target('ui')
        settings.set_schedule_enabled(False)
        aliases, counts = {}, {}
        cases = []

        def alias(value, kind):
            if value not in aliases:
                counts[kind] = counts.get(kind,0)+1
                aliases[value] = f'{kind}-{counts[kind]}'
            return aliases[value]

        def sanitize(value, key=''):
            if isinstance(value, dict):
                # Register opaque values before descending so references share aliases.
                for k,v in value.items():
                    if k in {'revision','default_page_revision','expected_revision'} and isinstance(v,str): alias(v,'revision')
                    elif k == 'id' and isinstance(v,str) and v != 'contract-board': alias(v,'collection' if v.startswith('collection:') else 'id')
                return {k: ('<redacted-fixture-password>' if k == 'password' else sanitize(v,k)) for k,v in value.items()}
            if isinstance(value,list): return [sanitize(v,key) for v in value]
            if isinstance(value,str):
                if key in {'created_at','updated_at'}: return '<timestamp>'
                for old,new in aliases.items(): value=value.replace(old,new)
                return re.sub(r'input_value=.*?, input_type=dict', 'input_value=<runtime model>, input_type=dict', value)
            return value

        def request(cid,method,path,body=None,status=200,headers=None):
            response=client.request(method,path,json=body,headers=headers)
            assert response.status_code==status,(cid,response.status_code,response.text)
            raw=response.json()
            sanitized=sanitize(raw)
            req={'method':method,'path':sanitize(path)}
            if body is not None: req['body']=sanitize(body)
            result={'status':status,'body':sanitized}
            for key in ['cache-control','retry-after']:
                if key in response.headers: result.setdefault('headers',{})[key]=response.headers[key]
            if 'set-cookie' in response.headers:
                cookie=response.headers['set-cookie']
                assert cookie.startswith(auth.SESSION_COOKIE_NAME+'=')
                parts=cookie.split('; ')
                result['cookie']={'name':auth.SESSION_COOKIE_NAME,'attributes':[p for p in parts[1:] if not p.lower().startswith('expires=')]}
            cases.append({'id':cid,'request':req,'response':result})
            return raw

        request('health','GET','/health')
        for mode in ['true','false',None]:
            if mode is None: os.environ.pop('FIESTABOARD_AUTH_ENABLED',None)
            else: os.environ['FIESTABOARD_AUTH_ENABLED']=mode
            name={'true':'enabled','false':'disabled',None:'undecided'}[mode]
            request('auth_'+name,'GET','/auth/status')
            request('discover_'+name,'GET','/discover')
        os.environ['FIESTABOARD_AUTH_ENABLED']='true'
        request('setup_required','GET','/v1/boards',status=409)
        request('login_before_setup','POST','/auth/login',{'username':'contract_admin','password':'fixture-password-123'},409)
        request('setup_validation','POST','/auth/setup',{'username':'contract_admin','password':'short'},422)
        request('setup','POST','/auth/setup',{'username':'contract_admin','password':'fixture-password-123'},201)
        request('setup_duplicate','POST','/auth/setup',{'username':'contract_admin','password':'fixture-password-123'},409)
        request('logout','POST','/auth/logout')
        request('protected_unauthenticated','GET','/v1/boards',status=401)
        request('login_wrong','POST','/auth/login',{'username':'contract_admin','password':'wrong'},401)
        request('login_session','POST','/auth/login',{'username':'contract_admin','password':'fixture-password-123'})
        request('auth_authenticated','GET','/auth/status')
        request('logout_again','POST','/auth/logout')
        request('login_persistent','POST','/auth/login',{'username':'contract_admin','password':'fixture-password-123','remember_me':True})
        request('login_https_cookie','POST','/auth/login',{'username':'contract_admin','password':'fixture-password-123'},headers={'X-Forwarded-Proto':'https'})
        # Use a fresh HTTP login after inspecting the Secure cookie; HTTP must
        # not send that cookie back. This fixture never stores cookie values.
        request('login_http_after_https','POST','/auth/login',{'username':'contract_admin','password':'fixture-password-123'})
        with patch('src.system.update_service._detect_hardware_model',return_value=None):
            request('version','GET','/version')
        request('boards_list','GET','/v1/boards')
        request('boards_detail','GET','/v1/boards/primary')
        request('board_missing','GET','/v1/boards/missing',status=404)
        request('board_patch_name','PATCH','/v1/boards/primary',{'name':'Renamed'})
        request('board_patch_null_noop','PATCH','/v1/boards/primary',{'name':None,'paused':None})
        request('board_restore_ui','POST','/v1/boards/primary/restore')
        request('board_patch_paused','PATCH','/v1/boards/primary',{'paused':True})
        request('board_restore_paused','POST','/v1/boards/primary/restore',status=409)
        service=Mock()
        with patch.object(display_runtime,'get_service',return_value=service):
            request('board_message_paused_preview','POST','/v1/boards/primary/message',{'text':'HELLO','if_paused':'preview','duration_minutes':5})
        assert settings.get_temporary_override() is None
        request('board_patch_resume','PATCH','/v1/boards/primary',{'paused':False})
        request('board_message_uninitialized','POST','/v1/boards/primary/message',{'text':'HELLO'},503)
        request('board_message_invalid','POST','/v1/boards/primary/message',{'text':'HELLO','characters':[[0]]},422)
        # Real stored page, unknown author extensions and null/omission semantics.
        page=request('page_create','POST','/v1/pages',{'name':'Document','type':'template','template':['Mixed Case {{red:HOT}} {{black/white:OPEN}} {{icon:sun}}'], 'future_page':{'nullable':None}},201)
        pid=page['id'];path='/v1/pages/'+pid
        request('page_get','GET',path)
        changed=request('page_sparse_update','PUT',path,{'name':'Renamed document','expected_revision':page['revision']})['page']
        assert changed['future_page']=={'nullable':None}
        request('page_stale_update','PUT',path,{'name':'Stale','expected_revision':page['revision']},412)
        request('page_stale_delete','DELETE',path+'?expected_revision='+page['revision'],status=412)
        request('page_clear_canvas','PUT',path,{'canvases':None,'expected_revision':changed['revision']})
        collection=request('collection_create','POST','/v1/collections',{'name':'Collection','page_ids':[pid]},201)
        cp='/v1/collections/'+collection['id']
        request('collection_update','PUT',cp,{'name':'Changed','expected_revision':collection['revision']})
        request('collection_stale_update','PUT',cp,{'name':'Stale','expected_revision':collection['revision']},412)
        schedule=request('schedule_create','POST','/v1/schedules',{'page_id':pid,'start_time':'10:00','end_time':'11:00'},201)
        sp='/v1/schedules/'+schedule['id']
        update=request('schedule_omission_preserves','PUT',sp,{'enabled':False,'expected_revision':schedule['revision']})
        assert update['end_time']=='11:00'
        request('schedule_null_clears','PUT',sp,{'end_time':None,'expected_revision':update['revision']})
        request('schedule_stale_update','PUT',sp,{'enabled':True,'expected_revision':schedule['revision']},412)
        default=request('default_get','GET','/schedules/default-page')
        request('default_set','PUT','/schedules/default-page',{'page_id':pid,'expected_revision':default['revision']})
        request('default_stale','PUT','/schedules/default-page',{'page_id':None,'expected_revision':default['revision']},412)
        request('board_patch_missing_default','PATCH','/v1/boards/primary',{'default_page_id':'missing'},404)
        request('board_patch_default_clear','PATCH','/v1/boards/primary',{'default_page_id':None})
        for case,body in [('flagship',{'device_type':'flagship'}),('note_array',{'device_type':'note_array','notes_wide':2,'notes_tall':2}),('panel',{'device_type':'panel','grid_rows':8,'grid_cols':16})]:
            request('render_'+case,'POST','/templates/render',{'template':['HELLO'],'board_id':'unknown-contract',**body})
        filled=request('render_filled_71','POST','/templates/render',{'template':['{{filled}}'],'device_type':'flagship','board_id':'unknown-contract'})
        assert filled['lines'][0].startswith('{71}')
        for _ in range(10): client.post('/auth/login',json={'username':'contract_admin','password':'wrong'})
        request('login_lockout','POST','/auth/login',{'username':'contract_admin','password':'wrong'},429)
        files=['src/auth/routes.py','src/auth/middleware.py','src/auth/service.py','src/service_api/routes.py','src/service_api/models.py','src/system/routes.py','src/v1/routes_boards.py','src/pages/models.py','src/pages/storage.py','src/collections/storage.py','src/schedules/storage.py','src/templates/routes.py']
        return {'schema_version':1,'source':{'commit':SOURCE,'version':VERSION},'source_evidence':{p:hashlib.sha256(Path('/app',p).read_bytes()).hexdigest() for p in files},'limits':'Isolated Docker, network none, no lifespan. UI-only output. Lazy runtime getter stubbed to None to prevent hardware initialization. Message preview substitutes only runtime service/client; never executes hardware/provider writes. Hardware model deliberately null. Discovery IDs, generated IDs, revisions and timestamps aliased; test passwords redacted. No deployment compatibility claim.','cases':cases}


def test_current_source_replay():
    # Fresh interpreter prevents previous auth tests' singleton stores or env
    # from contaminating the source replay. No backend imports on the host.
    subprocess.run([sys.executable, __file__, '--replay'], check=True)


if __name__=='__main__':
    actual=capture()
    if sys.argv[1:]==['--generate']:
        FIXTURE.parent.mkdir(parents=True,exist_ok=True)
        FIXTURE.write_text(json.dumps(actual,indent=2,ensure_ascii=False)+'\n')
        print(f'Generated {len(actual["cases"])} current-source cases')
    else:
        assert actual==json.loads(FIXTURE.read_text())
        print(f'Replayed {len(actual["cases"])} current-source cases')
