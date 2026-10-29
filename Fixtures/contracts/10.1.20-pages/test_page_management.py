"""Fresh-process real HTTP/store evidence. Backend imports only in fenced Docker."""
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

SOURCE = {'commit':'ff2415c4a646b55510f6f633c78915cdc9c333f2','version':'10.1.20'}
FIXTURE = Path('/contract-fixtures/10.1.20-pages/page-management.json')
SCENARIOS = ['basic','references','last_flagship','last_led','multi_active']


def scenario(name):
    assert Path('/.dockerenv').exists(), 'Backend imports require Docker'
    with tempfile.TemporaryDirectory(prefix='pages-') as tmp:
        os.environ['FIESTABOARD_DATA_DIR'] = tmp
        os.environ['FIESTABOARD_AUTH_ENABLED'] = 'true'
        with patch('src.display_runtime.get_service', return_value=None):
            from fastapi.testclient import TestClient
            import src
            from src.api_server import app
            from src.auth import service as auth
            from src.settings.service import get_settings_service
        assert src.__version__ == SOURCE['version']
        auth._service = auth.AuthService(Path(tmp)/'auth.json')
        client = TestClient(app)
        assert client.post('/auth/setup',json={'username':'fixture_admin','password':'fixture-password-123'}).status_code == 201
        settings = get_settings_service()
        settings.set_output_target('ui')
        boards = [{'id':'contract-primary','name':'Primary','device_type':'flagship'},
                  {'id':'contract-secondary','name':'Secondary','device_type':'flagship'},
                  {'id':'contract-led','name':'LED','device_type':'panel','grid_rows':8,'grid_cols':16,'output':'fiestapanel'}]
        settings.set_boards(boards)
        aliases, counts, cases = {}, {}, []
        def alias(v,kind):
            if v not in aliases:
                counts[kind] = counts.get(kind,0)+1
                aliases[v] = f'{kind}-{counts[kind]}'
        def clean(v,key=''):
            if isinstance(v,dict):
                for k,x in v.items():
                    if k in {'revision','expected_revision'} and isinstance(x,str): alias(x,'revision')
                    if k in {'id','new_page_id','new_active_page_id'} and isinstance(x,str) and not x.startswith('contract-'): alias(x,'id')
                return {k:clean(x,k) for k,x in v.items()}
            if isinstance(v,list): return [clean(x,key) for x in v]
            if isinstance(v,str):
                if key in {'created_at','updated_at'}: return '<timestamp>'
                for old,new in aliases.items(): v=v.replace(old,new)
                return re.sub(r'input_value=.*?, input_type=dict','input_value=<runtime model>, input_type=dict',v)
            return v
        def request(cid,method,path,body=None,status=200):
            response=client.request(method,path,json=body)
            assert response.status_code==status,(name,cid,response.status_code,response.text)
            raw=response.json()
            result=clean(raw)
            req={'method':method,'path':clean(path),'headers':{'cookie':{'name':auth.SESSION_COOKIE_NAME,'present':'cookie' in response.request.headers}}}
            if body is not None: req['body']=clean(body)
            query=dict(parse_qsl(urlsplit(path).query))
            if query: req['query']=clean(query)
            cases.append({'id':name+'.'+cid,'request':req,'response':{'status':status,'body':result}})
            return raw
        def create(cid,led=False):
            body={'name':cid,'type':'template','device_type':'panel' if led else 'flagship','template':['Mixed {{red:HOT}}'], 'future_author':{'nullable':None,'values':[1,'keep']}}
            if led: body.update(grid_rows=8,grid_cols=16)
            return request(cid,'POST','/v1/pages',body,201)
        def delete(cid,page,status=200):
            return request(cid,'DELETE','/v1/pages/'+page['id']+'?expected_revision='+page['revision'],status=status)
        def get(cid,pid): return request(cid,'GET','/v1/pages/'+pid)
        def selection(cid):
            value={b['id']:settings.get_active_page_id(b['id']) for b in boards}
            # Store readback is explicit evidence in addition to HTTP receipts.
            cases.append({'id':name+'.'+cid,'store_readback':clean(value)})
            return value
        if name=='basic':
            flag=create('create_flagship'); led=create('create_led',True)
            assert get('get_flagship',flag['id'])==flag
            assert get('get_led',led['id'])==led
            request('invalid_name','POST','/v1/pages',{'name':'','type':'template'},422)
            request('invalid_panel_missing_grid','POST','/v1/pages',{'name':'Bad','type':'template','device_type':'panel'},422)
            request('invalid_panel_grid','POST','/v1/pages',{'name':'Bad','type':'template','device_type':'panel','grid_rows':0,'grid_cols':16},422)
            changed=request('rename','PUT','/v1/pages/'+flag['id'],{'name':'Renamed','expected_revision':flag['revision']})['page']
            delete('stale_delete',flag,412)
            assert get('after_stale',flag['id'])==changed
            delete('delete_flagship',changed);delete('delete_led',led)
            request('deleted_get','GET','/v1/pages/'+led['id'],status=404)
            request('missing_delete','DELETE','/v1/pages/missing?expected_revision=missing',status=404)
        elif name=='references':
            p=create('create')
            collection=request('collection_create','POST','/v1/collections',{'name':'Consumer','page_ids':[p['id']]},201)
            delete('collection_in_use',p,409)
            assert get('after_collection_refusal',p['id'])==p
            request('collection_delete','DELETE','/v1/collections/'+collection['id']+'?expected_revision='+collection['revision'])
            schedule=request('schedule_create','POST','/v1/schedules',{'page_id':p['id'],'start_time':'10:00','enabled':False,'board_id':'contract-secondary'},201)
            delete('disabled_schedule_in_use',p,409)
            assert get('after_schedule_refusal',p['id'])==p
            request('schedule_delete','DELETE','/v1/schedules/'+schedule['id']+'?expected_revision='+schedule['revision'])
            default=request('default_get','GET','/schedules/default-page?board_id=contract-primary')
            assigned=request('default_set','PUT','/schedules/default-page',{'page_id':p['id'],'board_id':'contract-primary','expected_revision':default['revision']})
            delete('default_in_use',p,409)
            assert get('after_default_refusal',p['id'])==p
            request('default_clear','PUT','/schedules/default-page',{'page_id':None,'board_id':'contract-primary','expected_revision':assigned['revision']})
            delete('delete_after_unreference',p)
        elif name in {'last_flagship','last_led'}:
            p=create('create',name=='last_led')
            for other in client.get('/v1/pages').json()['pages']:
                if other['id']!=p['id']: delete('remove_other_'+str(len(cases)),other)
            before=request('before','GET','/v1/pages');assert len(before['pages'])==1
            receipt=delete('delete_last',p)
            replacement=get('replacement',receipt['new_page_id'])
            assert replacement['device_type']==p['device_type']
            assert (replacement['grid_rows'],replacement['grid_cols'])==(p['grid_rows'],p['grid_cols'])
            request('after','GET','/v1/pages')
        elif name=='multi_active':
            p=create('create_flagship'); led=create('create_led',True)
            settings.set_active_page_id(p['id'],'contract-primary')
            settings.set_active_page_id(p['id'],'contract-secondary')
            settings.set_active_page_id(led['id'],'contract-led')
            selection('before')
            delete('delete_shared_active',p)
            state=selection('after_shared')
            assert state['contract-primary']==state['contract-secondary']!=p['id']
            assert state['contract-led']==led['id']
            receipt=delete('delete_led_active',led)
            state=selection('after_led')
            replacement=get('led_replacement',state['contract-led'])
            assert replacement['device_type']=='panel' and replacement['grid_rows']==8 and replacement['grid_cols']==16
            assert receipt['active_page_updated'] and receipt['default_page_created']
            request('after','GET','/v1/pages')
        return cases


def capture():
    cases=[]
    for name in SCENARIOS:
        result=subprocess.run([sys.executable,__file__,'--scenario',name],capture_output=True,text=True)
        assert result.returncode==0, (name,result.stderr)
        cases.extend(json.loads(result.stdout))
    files=['src/pages/routes.py','src/pages/models.py','src/pages/service.py','src/pages/storage.py','src/content_references.py','src/v1/routes_content.py','src/auth/middleware.py','src/settings/service.py','src/collections/service.py','src/schedules/storage.py']
    return {'schema_version':1,'kind':'candidate-page-management','source':SOURCE,'source_evidence':{p:hashlib.sha256(Path('/app',p).read_bytes()).hexdigest() for p in files},'limits':'Fenced Docker, network none, read-only clean source, temporary stores, fresh process per scenario, authenticated real middleware/routes/stores. No lifespan or display initialization, real config, hardware or providers. UI output target; lazy runtime getter stubbed None. Synthetic auth setup secrets never recorded. Selection fixtures use real settings setters to arrange references; store readbacks explicitly marked. No storage-I/O failure injection, live-deployment proof or physical-output observation.','cases':cases}


def test_replay():
    subprocess.run([sys.executable,__file__,'--replay'],check=True)


def test_reject_changed_receipt():
    expected=json.loads(FIXTURE.read_text())
    next(c for c in expected['cases'] if c['id']=='last_led.delete_last')['response']['body']['default_page_created']=False
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)/'changed.json';path.write_text(json.dumps(expected))
        result=subprocess.run([sys.executable,__file__,'--replay',str(path)],capture_output=True,text=True)
    assert result.returncode!=0
    assert 'Page management replay differs' in result.stderr


if __name__=='__main__':
    if sys.argv[1:2]==['--scenario']:
        print(json.dumps(scenario(sys.argv[2])))
    else:
        actual=capture()
        if sys.argv[1:]==['--generate']:
            FIXTURE.write_text(json.dumps(actual,indent=2,ensure_ascii=False)+'\n')
            print(f'Generated {len(actual["cases"])} page management records')
        else:
            expected=json.loads((Path(sys.argv[2]) if len(sys.argv)==3 else FIXTURE).read_text())
            assert actual==expected,'Page management replay differs'
            print(f'Replayed {len(actual["cases"])} page management records')
