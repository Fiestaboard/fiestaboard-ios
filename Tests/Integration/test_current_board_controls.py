"""Current board controls through real middleware, stores, executors and display passes.

Backend imports run in a fresh fenced Docker interpreter only. Deterministic
output clients replace the final driver boundary; no device output is observed.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from unittest.mock import patch
from urllib.parse import parse_qsl, urlsplit

SOURCE = 'b5eac069dce10945eac61e1fdadf6ee4a903ba08'
VERSION = '10.1.17'
FIXTURE = Path('/contract-fixtures/current/board-control.json')


def capture():
    if not Path('/.dockerenv').exists():
        raise RuntimeError('Backend imports require isolated Docker')
    with tempfile.TemporaryDirectory(prefix='board-controls-') as tmp:
        os.environ['FIESTABOARD_DATA_DIR'] = tmp
        os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
        # Prevent the lazy singleton from initializing clients while importing routes.
        with patch('src.display_runtime.get_service', return_value=None):
            from fastapi.testclient import TestClient
            import src
            from src.api_server import app
            from src import display_runtime
            from src.auth import service as auth
            from src.settings.service import get_settings_service
            from src.config_manager import get_config_manager
            from src.main import DisplayService, BoardRuntime
            from src.send_outcome import WriteResult, FrameRegion
            from src.led.charsets import BUILTIN_CHARACTER_SETS
            from src.outputs.cells import cells_to_json
            from src.panels.service import get_panel_service
            from src.panels.models import PanelCreate
            from src.time_service import TimeService
            from datetime import UTC, datetime
        assert src.__version__ == VERSION
        settings = get_settings_service()
        boards = [{'id':'contract-board','name':'Split flap','device_type':'flagship'},
                  {'id':'contract-led','name':'LED','device_type':'panel','grid_rows':8,'grid_cols':16,'output':'fiestapanel'},
                  {'id':'contract-array','name':'Array','device_type':'note_array','notes_wide':2,'notes_tall':1}]
        settings.set_boards(boards)
        get_panel_service().create_panel(PanelCreate(name='LED',render_style='led_matrix'), 'contract-led')
        settings.set_output_target('board')
        for board in boards:
            settings.set_schedule_enabled(False, board_id=board['id'])
        manager = get_config_manager()
        manager.migrate_silence_schedule_to_per_board()
        manager.migrate_silence_schedule_to_utc()
        provider_fetches = []

        class BoundaryClient:
            """Only the driver boundary is synthetic; outcomes are source WriteResult."""
            is_virtual = False
            use_cloud = False
            min_send_interval_ms = 0
            character_set = None
            def __init__(self, board_id, charset=None):
                self.board_id = board_id
                self.character_set = charset
                self.mode = 'sent'
                self.calls = []
            def set_output_runtime(self, output): self.output = output
            def clear_cache(self): self.output.frames.clear()
            def render(self, characters, **kwargs):
                self.calls.append({'board_id':self.board_id,'characters':characters,
                                   'force':kwargs.get('force',False),
                                   'cells':cells_to_json(kwargs['cells']) if kwargs.get('cells') is not None else None})
                if self.mode == 'timeout': raise TimeoutError('fixture output timeout')
                if self.mode == 'malformed': return {'malformed':'driver outcome'}
                outcomes = {'sent':WriteResult(True,True), 'unchanged':WriteResult(True,False),
                            'failed':WriteResult(False,False),
                            'throttled':WriteResult(True,False,throttled=True,retry_after_seconds=7,floor_seconds=15),
                            'superseded':WriteResult(True,False,superseded=True),
                            'partial':WriteResult(False,False,partial=True,failed_regions=(FrameRegion(0,15,3,15),))}
                result=outcomes[self.mode]
                if result.was_sent: self.output.frames.record_sent(characters, cells=kwargs.get('cells'))
                return result if kwargs.get('with_outcome') else (result.success,result.was_sent)

        clients = {b['id']:BoundaryClient(b['id'], BUILTIN_CHARACTER_SETS['led_5x7'] if b['id']=='contract-led' else None) for b in boards}
        service = DisplayService()  # Constructor only: no initialize(), run() or lifespan.
        service._primary_board_id='contract-board'
        service.runtimes={bid:BoardRuntime(client,bid,output_id='fiestapanel' if bid=='contract-led' else 'vestaboard') for bid,client in clients.items()}
        auth._service=auth.AuthService(Path(tmp)/'auth.json')
        client=TestClient(app)
        setup=client.post('/auth/setup',json={'username':'contract_admin','password':'fixture-password-123'})
        assert setup.status_code==201
        aliases, counts, cases = {}, {}, []
        def alias(value,kind):
            if value not in aliases:
                counts[kind]=counts.get(kind,0)+1
                aliases[value]=f'{kind}-{counts[kind]}'
            return aliases[value]
        def sanitize(value,key=''):
            if isinstance(value,dict):
                for k,v in value.items():
                    if k in {'revision','expected_revision','default_page_revision'} and isinstance(v,str): alias(v,'revision')
                    elif k=='id' and isinstance(v,str) and not v.startswith('contract-'): alias(v,'id')
                return {k:sanitize(v,k) for k,v in value.items()}
            if isinstance(value,list): return [sanitize(v,key) for v in value]
            if isinstance(value,str):
                if key in {'created_at','updated_at','expires_at','read_at'}: return '<timestamp>'
                for old,new in aliases.items(): value=value.replace(old,new)
                return re.sub(r'input_value=.*?, input_type=dict','input_value=<runtime model>, input_type=dict',value)
            return value
        def request(cid,method,path,body=None,status=200):
            before={bid:len(c.calls) for bid,c in clients.items()}
            response=client.request(method,path,json=body)
            assert response.status_code==status,(cid,response.status_code,response.text)
            raw=response.json()
            result={'status':status,'body':sanitize(raw)}
            if 'retry-after' in response.headers: result['headers']={'retry-after':response.headers['retry-after']}
            req={'method':method,'path':sanitize(path)}
            query=dict(parse_qsl(urlsplit(path).query))
            if query: req['query']=query
            req['headers']={'cookie':{'name':auth.SESSION_COOKIE_NAME,'present':'cookie' in response.request.headers}}
            if 'content-type' in response.request.headers:
                req['headers']['content-type']=response.request.headers['content-type']
            if body is not None: req['body']=sanitize(body)
            calls=[call for bid,c in clients.items() for call in c.calls[before[bid]:]]
            cases.append({'id':cid,'request':req,'response':result,'boundary_calls':sanitize(calls)})
            return raw
        def context(*args,**kwargs):
            provider_fetches.append('empty provider context')
            return {}
        fixed=datetime(2026,10,28,12,0,tzinfo=UTC)
        # These are output read/provider-fetch/clock boundaries, not handlers or
        # store/executor methods. Poll requests are recorded, never scheduled.
        refreshes=[]
        with patch.object(display_runtime,'get_service',return_value=service), \
             patch('src.api_server.get_service',return_value=service), \
             patch.object(service,'request_board_refresh',side_effect=lambda *a,**k:refreshes.append('requested')), \
             patch('src.plugins.registry.PluginRegistry.build_template_context',side_effect=context), \
             patch.object(TimeService,'get_current_utc',return_value=fixed), \
             patch.object(TimeService,'get_current_time',return_value=fixed):
            request('boards_list','GET','/v1/boards')
            for bid in clients: request('detail_'+bid,'GET','/v1/boards/'+bid)
            page=request('page_create','POST','/v1/pages',{'name':'Control page','type':'template','template':['HELLO']},201)
            pid=page['id']
            ledpage=request('led_page_create','POST','/v1/pages',{'name':'LED page','type':'template','device_type':'panel','grid_rows':8,'grid_cols':16,'template':['Mixed {{red:HOT}}']},201)
            for bid in ['contract-board','contract-led']:
                request('message_'+bid,'POST','/v1/boards/'+bid+'/message',{'text':'Mixed {{red:HOT}}'})
            base='/v1/boards/primary'
            for mode,status in [('unchanged',200),('failed',500),('throttled',429),('superseded',409),('partial',502),('timeout',500),('malformed',500)]:
                target='contract-array' if mode=='partial' else 'contract-board'
                clients[target].mode=mode
                request('message_'+mode,'POST','/v1/boards/'+target+'/message',{'text':'HELLO'},status)
                clients[target].mode='sent'
            clients['contract-board'].mode='throttled'
            request('message_timed_throttled','POST',base+'/message',{'text':'TIMED','duration_minutes':5},429)
            assert settings.get_temporary_override() is None
            clients['contract-board'].mode='sent'
            request('message_timed_ack','POST',base+'/message',{'text':'TIMED','duration_minutes':5})
            assert settings.get_temporary_override() is not None
            settings.clear_temporary_override()
            request('message_timed_secondary','POST','/v1/boards/contract-led/message',{'text':'TIMED','duration_minutes':5},400)
            request('message_timed_raw','POST',base+'/message',{'fill':0,'duration_minutes':5},400)
            settings.set_output_target('ui')
            request('message_ui','POST',base+'/message',{'text':'HELLO'})
            request('restore_ui','POST',base+'/restore')
            settings.set_output_target('board')
            request('patch_pause','PATCH',base,{'paused':True})
            request('message_paused','POST',base+'/message',{'text':'HELLO'},409)
            request('message_paused_preview','POST',base+'/message',{'text':'HELLO','if_paused':'preview','duration_minutes':5})
            assert settings.get_temporary_override() is None
            request('restore_paused','POST',base+'/restore',status=409)
            request('page_paused','PUT',base+'/active-page',{'page_id':pid})
            request('patch_resume','PATCH',base,{'paused':False})
            request('patch_schedule','PATCH','/v1/boards/contract-led',{'schedule_enabled':True})
            request('patch_auto_restore','PATCH','/v1/boards/contract-led',{'auto_restore':False})
            request('patch_null_scalars','PATCH','/v1/boards/contract-led',{'paused':None,'schedule_enabled':None,'auto_restore':None})
            silence={'enabled':True,'start_time':'00:00+00:00','end_time':'23:59+00:00','show_queued_on_exit':False}
            manager.set_silence_schedule_for_board('contract-board',silence)
            request('message_silenced','POST',base+'/message',{'text':'HELLO'},409)
            request('restore_silenced','POST',base+'/restore',status=409)
            manager.set_silence_schedule_for_board('contract-board',{**silence,'show_queued_on_exit':True})
            request('message_held','POST',base+'/message',{'text':'HELD'},202)
            from src import silence_queue
            assert silence_queue.peek('contract-board') is not None
            request('page_silenced','PUT',base+'/active-page',{'page_id':pid})
            request('message_override_silence','POST',base+'/message',{'text':'NOW','override_silence':True})
            assert silence_queue.peek('contract-board') is None
            manager.set_silence_schedule_for_board('contract-board',{'enabled':False})
            request('page_select','PUT',base+'/active-page',{'page_id':pid})
            clients['contract-board'].mode='failed'
            request('page_send_failed','PUT',base+'/active-page',{'page_id':pid})
            assert settings.get_active_page_id(board_id='contract-board')==pid
            request('restore_failed','POST',base+'/restore',status=500)
            clients['contract-board'].mode='sent'
            request('restore_ack','POST',base+'/restore')
            clients['contract-board'].mode='unchanged'
            request('restore_no_output','POST',base+'/restore')
            clients['contract-board'].mode='sent'
            request('page_led_select','PUT','/v1/boards/contract-led/active-page',{'page_id':ledpage['id']})
            request('detail_primary_after_led_select','GET',base)
            assert settings.get_active_page_id(board_id='contract-board')==pid
            request('restore_led_schedule_gap','POST','/v1/boards/contract-led/restore')
            request('patch_led_schedule_off','PATCH','/v1/boards/contract-led',{'schedule_enabled':False})
            request('restore_led','POST','/v1/boards/contract-led/restore')
            request('patch_led_pause','PATCH','/v1/boards/contract-led',{'paused':True})
            request('detail_primary_after_led_pause','GET',base)
            assert settings.is_paused(board_id='contract-board') is False
            request('patch_led_resume','PATCH','/v1/boards/contract-led',{'paused':False})
            request('page_incompatible','PUT','/v1/boards/contract-led/active-page',{'page_id':pid},400)
            request('page_missing','PUT',base+'/active-page',{'page_id':'missing'},404)
            request('page_unpin','PUT',base+'/active-page',{'page_id':None})
            request('message_missing_page','POST',base+'/message',{'page_id':'missing'},404)
            request('message_invalid_union','POST',base+'/message',{'text':'HELLO','fill':0},422)
            request('message_invalid_grid','POST',base+'/message',{'characters':[[0]]},400)
            request('message_missing_board','POST','/v1/boards/missing/message',{'text':'HELLO'},404)
            request('message_revert_without_duration','POST',base+'/message',{'text':'HELLO','revert_mode':'schedule'},400)
            primary_before=request('default_primary_before_led_set','GET','/schedules/default-page?board_id=contract-board')
            led_original=request('default_led_get','GET','/schedules/default-page?board_id=contract-led')
            led_changed=request('default_led_set','PUT','/schedules/default-page',{'page_id':ledpage['id'],'board_id':'contract-led','expected_revision':led_original['revision']})
            primary_after=request('default_primary_after_led_set','GET','/schedules/default-page?board_id=contract-board')
            assert primary_after['default_page_id']==primary_before['default_page_id']
            assert primary_after['revision']!=primary_before['revision']
            assert request('default_led_after_set','GET','/schedules/default-page?board_id=contract-led')==led_changed
            request('default_primary_invalidated_by_secondary','PUT','/schedules/default-page',{'page_id':None,'board_id':'contract-board','expected_revision':primary_before['revision']},412)
            request('default_led_clear','PUT','/schedules/default-page',{'page_id':None,'board_id':'contract-led','expected_revision':led_changed['revision']})
            original=request('default_get','GET','/schedules/default-page?board_id=contract-board')
            changed=request('default_set','PUT','/schedules/default-page',{'page_id':pid,'board_id':'contract-board','expected_revision':original['revision']})
            request('default_stale','PUT','/schedules/default-page',{'page_id':None,'board_id':'contract-board','expected_revision':original['revision']},412)
            request('default_missing_page','PUT','/schedules/default-page',{'page_id':'missing','board_id':'contract-board','expected_revision':changed['revision']},404)
            request('default_clear','PUT','/schedules/default-page',{'page_id':None,'board_id':'contract-board','expected_revision':changed['revision']})
            request('default_missing_board','PUT','/schedules/default-page',{'page_id':None,'board_id':'missing','expected_revision':changed['revision']},404)
            request('patch_missing_default','PATCH',base,{'default_page_id':'missing'},404)
            # Source is sequential, not atomic: pause persists before bad default ref.
            request('patch_nonatomic','PATCH',base,{'paused':True,'default_page_id':'missing'},404)
            request('detail_after_nonatomic','GET',base)
        for rt in service.runtimes.values():
            if rt.send_worker is not None: rt.send_worker.stop()
        files=['src/v1/routes_boards.py','src/v1/models.py','src/settings/routes.py','src/settings/service.py','src/schedules/routes.py','src/schedules/models.py','src/schedules/service.py','src/schedules/storage.py','src/ops/executors.py','src/displays/messages.py','src/board_guards.py','src/send_outcome.py','src/main.py','src/display_runtime.py','src/board_state.py','src/outputs/cells.py','src/outputs/frames.py','src/outputs/board_profile.py','src/templates/engine.py','src/plugins/registry.py']
        return {'schema_version':1,'kind':'current-board-controls','source':{'commit':SOURCE,'version':VERSION},
                'source_evidence':{p:hashlib.sha256(Path('/app',p).read_bytes()).hexdigest() for p in files},
                'limits':'Isolated Docker network none/read-only source/temp stores; no lifespan, initialization or hardware clients. Real authenticated middleware, handlers, stores, executor, page rendering and DisplayService passes. Final driver render/read-refresh and provider-context boundaries stubbed; fixed clock. sent=true is simulated output-boundary acceptance, never device observation. No real provider fetch, physical output, deployment compatibility or universal conflict protection.',
                'cases':cases,'boundary_evidence':{'hardware_sends':0,'real_provider_fetches':0,'provider_context_stub_calls':len(provider_fetches),'refresh_requests_stubbed':len(refreshes)}}


def test_current_board_controls_replay():
    subprocess.run([sys.executable,__file__,'--replay'],check=True)


def test_current_board_controls_replay_rejects_changed_receipt():
    expected=json.loads(FIXTURE.read_text())
    next(case for case in expected['cases'] if case['id']=='restore_ack')['response']['body']['device_observed']=True
    with tempfile.TemporaryDirectory(prefix='mutated-receipt-') as tmp:
        changed=Path(tmp)/'board-control.json'
        changed.write_text(json.dumps(expected))
        result=subprocess.run([sys.executable,__file__,'--replay',str(changed)],capture_output=True,text=True)
    assert result.returncode!=0
    assert 'Current-source board-control replay differs' in result.stderr


if __name__=='__main__':
    actual=capture()
    if sys.argv[1:]==['--generate']:
        FIXTURE.write_text(json.dumps(actual,indent=2,ensure_ascii=False)+'\n')
        print(f'Generated {len(actual["cases"])} board-control cases')
    else:
        expected=json.loads((Path(sys.argv[2]) if len(sys.argv)==3 else FIXTURE).read_text())
        assert actual==expected,'Current-source board-control replay differs from source-bound corpus'
        print(f'Replayed {len(actual["cases"])} board-control cases')
