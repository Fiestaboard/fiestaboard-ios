"""Host-executed migration controls for the Swift in-process fixture router."""
import json
import os
from pathlib import Path
import subprocess
import socket
import select
import time
import base64
import concurrent.futures
import urllib.request
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(os.environ.get('CX_NATIVE_FIXTURE_BUILD_DIR', str(Path.home() / 'Library/Developer/FiestaBoard/ios/cx-i5-native-fixture-controls')))

class NativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''import Foundation
let router = try FixtureRouter(resourceURL: URL(fileURLWithPath: CommandLine.arguments[1]), recordedURL: URL(fileURLWithPath: CommandLine.arguments[2]))
if CommandLine.arguments.count > 3 {
    let server = try FixtureHTTPServer(router: router)
    try server.requireReady()
    print(server.port); fflush(nil)
    while let command = readLine() {
        if command == "probe" {
            do { try server.requireReady(); print("ready") } catch { print("failed") }
        } else if command == "hold-onboarding" { server.holdOnboardingBootstrap(true); print("ok")
        } else if command == "release-onboarding" { server.holdOnboardingBootstrap(false); print("ok")
        } else if command == "onboarding-waiting" { print(server.onboardingBootstrapWaiting ? "waiting" : "idle")
        } else if command == "hold-handoff-pages" { server.holdOnboardingHandoffPages(true); print("ok")
        } else if command == "release-handoff-pages" { server.holdOnboardingHandoffPages(false); print("ok")
        } else if command == "handoff-pages-waiting" { print(server.onboardingHandoffPagesWaiting ? "waiting" : "idle")
        } else { server.setDropped(command == "drop"); print("ok") }
        fflush(nil)
    }
    exit(0)
}
while let line = readLine() {
    let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    if let status = input["readyStatus"] as? Int {
        let data = try JSONSerialization.data(withJSONObject: input["readyBody"] ?? [:])
        do { try FixtureHTTPServer.validateReadyResponse(status: status, body: data); print("true") }
        catch { print("false") }
        continue
    }
    let response = router.respond(method: input["method"] as? String ?? "GET", target: input["target"] as! String,
       headers: input["headers"] as? [String: String] ?? [:], body: try JSONSerialization.data(withJSONObject: input["body"] ?? [:]))
    let result: [String: Any] = ["status": response.status, "body": try JSONSerialization.jsonObject(with: response.body.isEmpty ? Data("null".utf8) : response.body, options: [.fragmentsAllowed]), "headers": response.headers, "raw": response.body.base64EncodedString()]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .fragmentsAllowed]), encoding: .utf8)!)
}
''')
        cls.binary = BUILD / 'controls'
        subprocess.run(['swiftc', '-swift-version', '6', '-module-cache-path', str(BUILD/'modules'),
                        str(ROOT/'Tests/UITests/FixtureRouter.swift'), str(ROOT/'Tests/UITests/FixtureHTTPServer.swift'),
                        str(ROOT/'Tests/UITests/FixtureBoardRoutes.swift'),
                        str(ROOT/'Tests/UITests/FixtureComposeRoutes.swift'),
                        str(ROOT/'Tests/UITests/FixtureRenderRoutes.swift'), str(main), '-o', str(cls.binary)],check=True,capture_output=True,text=True)

    def run_sequence(self, inputs):
        result = subprocess.run([str(self.binary), str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json'), str(ROOT/'Tests/Fixtures')],
          input=''.join(json.dumps(i)+'\n' for i in inputs),text=True,capture_output=True,check=True)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_compose_namespace_retains_recorded_h3_and_clipped_preview_evidence(self):
        prefix='/board-i8-compose-new/api/'
        auth={'authorization':'Bearer fb_mob_fixture_board-i8-compose-new'}
        request={'board_id':'tc001-fixture','template':['ABCDEFGHIJKLMNOPQRS'],
                 'line_metadata':[{'alignment':'left','wrap':False}], 'device_type':'panel',
                 'grid_rows':1,'grid_cols':8,'notes_wide':1,'notes_tall':1,
                 'diagnostics':True,'preview':{'data':'cached'}}
        result=self.run_sequence([
            dict(target=prefix+'discover'),
            dict(target=prefix+'v1/boards'),
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password','client_id':'fiestaboard-ios'}),
            dict(target=prefix+'version',headers=auth),
            dict(target=prefix+'v1/boards/tc001-fixture',headers=auth),
            dict(method='POST',target=prefix+'templates/render',headers=auth,body=request)])
        self.assertEqual(result[0]['body']['version'],'11.0.0-alpha.3')
        self.assertEqual(result[1]['status'],401)
        self.assertEqual(result[3]['body']['running_version'],'11.0.0-alpha.3')
        self.assertTrue(result[3]['body']['is_dev'])
        records=json.loads((ROOT/'Tests/Fixtures/Compose/operations-authenticated.json').read_text())['records']
        drawing=next(r['response']['drawing'] for r in records if r['case']=='drawing-tc001-fixture')
        self.assertEqual(result[4]['body']['drawing'],drawing)
        long=json.loads((ROOT/'Tests/Fixtures/Compose/long-led-authenticated.json').read_text())['records']
        preview=next(r for r in long if r['case']=='preview-plain-19')
        self.assertEqual(base64.b64decode(result[5]['raw']).decode(),preview['raw_response'])

    def test_compose_catalog_keeps_recorded_bytes_and_denies_array_hydration(self):
        prefix='/board-i8-compose-catalog/api/'
        auth={'authorization':'Bearer fb_mob_fixture_board-i8-compose-catalog'}
        records=json.loads((ROOT/'Tests/Fixtures/Compose/catalog-authenticated.json').read_text())['records']
        cases=['variables-local-provider','formula-functions','date-time-manifest','validate-valid','mobile-array-batch-denied']
        inputs=[dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'})]
        selected=[next(r for r in records if r['case']==case) for case in cases]
        for record in selected:
            inputs.append(dict(method=record['method'],target=prefix+record['path'][1:],headers=auth,body=record['request'] or {}))
        results=self.run_sequence(inputs)[1:]
        for record,result in zip(selected,results):
            with self.subTest(case=record['case']):
                self.assertEqual(result['status'],record['status'])
                self.assertEqual(base64.b64decode(result['raw']).decode(),record['raw_response'])
        self.assertEqual(results[-1]['status'],403)
        self.assertNotIn('displays',results[-1]['body'])

    def test_compose_unknown_uuid_is_not_replayed_or_shared_between_namespaces(self):
        # Full UUID namespace exercises the same scenario parser as XCUITest.
        namespace='board-i8-compose-unknown-aabbccdd-1234-4567-89ab-0123456789ab'
        prefix='/'+namespace+'/api/'
        auth={'authorization':'Bearer fb_mob_fixture_'+namespace}
        other='/board-i8-compose-other/api/'
        request={'protocol':'compose-intent-v1','request_id':'11223344-1234-4567-89ab-0123456789ab',
                 'template':['Keep this draft'],'line_metadata':[{'alignment':'left','wrap':False}],
                 'geometry':{'device_type':'flagship','notes_wide':1,'notes_tall':1},
                 'duration':{'kind':'minutes','minutes':120},'silence':'hold'}
        route='v1/boards/hall-1/compose'
        results=self.run_sequence([
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'}),
            dict(method='POST',target=prefix+route,headers=auth,body=request),
            dict(method='GET',target=prefix+route+'/'+request['request_id'],headers=auth),
            dict(method='POST',target=prefix+route,headers=auth,body=request),
            dict(method='GET',target=other+route+'/'+request['request_id'],headers=auth),
            dict(method='DELETE',target=prefix+'auth/device/session',headers=auth),
            dict(method='GET',target=prefix+route+'/'+request['request_id'],headers=auth)])
        self.assertEqual([r['status'] for r in results],[200,503,200,409,401,200,401])
        self.assertEqual(results[1]['body']['detail']['status'],'unknown')
        self.assertEqual(results[2]['body'],results[1]['body']['detail'])
        self.assertEqual(results[2]['body']['request_id'],request['request_id'])

    def test_compose_page_copy_keeps_display_state_and_exact_source_metadata(self):
        prefix='/board-i8-compose-copy/api/'
        auth={'authorization':'Bearer fb_mob_fixture_board-i8-compose-copy'}
        page={'name':'Keep exact','type':'template','template':['Keep {{red:This}}','第二行'],
              'line_metadata':[{'alignment':'right','wrap':True},{'alignment':'center','wrap':False}],
              'device_type':'flagship','notes_wide':1,'notes_tall':1}
        results=self.run_sequence([
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'}),
            dict(target=prefix+'v1/boards/hall-1',headers=auth),
            dict(method='POST',target=prefix+'pages',headers=auth,body=page),
            dict(target=prefix+'pages/synthetic-compose-page-1',headers=auth),
            dict(target=prefix+'v1/boards/hall-1',headers=auth),
            dict(target=prefix+'v1/pages',headers=auth)])
        self.assertEqual([r['status'] for r in results],[200,200,201,200,200,200])
        self.assertEqual(results[1]['body'],results[4]['body'])
        for key,value in page.items():
            self.assertEqual(results[2]['body'][key],value)
        self.assertEqual(results[2]['body'],results[3]['body'])
        self.assertEqual(results[5]['body']['pages'],[results[3]['body']])

    def test_compose_held_acknowledgement_can_be_polled_without_another_send(self):
        prefix='/board-i8-compose-held-new/api/'
        auth={'authorization':'Bearer fb_mob_fixture_board-i8-compose-held-new'}
        request={'protocol':'compose-intent-v1','request_id':'11223344-1234-4567-89ab-0123456789ab',
                 'template':['Deferred draft'],'duration':{'kind':'minutes','minutes':120},'silence':'hold'}
        route='v1/boards/hall-1/compose'
        results=self.run_sequence([
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'}),
            dict(method='POST',target=prefix+route,headers=auth,body=request),
            dict(target=prefix+'v1/boards/hall-1',headers=auth),
            dict(target=prefix+route+'/'+request['request_id'],headers=auth),
            dict(method='POST',target=prefix+route,headers=auth,body=request)])
        self.assertEqual([r['status'] for r in results],[200,202,200,200,409])
        self.assertEqual(results[1]['body']['status'],'held')
        self.assertFalse(results[1]['body']['sent'])
        self.assertIsNone(results[1]['body']['started_at'])
        self.assertEqual(results[2]['body']['compose_receipt']['request_id'],request['request_id'])
        self.assertEqual(results[3]['body']['status'],'sent')
        self.assertTrue(results[3]['body']['sent'])

    def test_compose_ambiguous_send_has_no_invented_receipt_but_retains_uuid_get(self):
        prefix='/board-i8-compose-ambiguous-new/api/'
        auth={'authorization':'Bearer fb_mob_fixture_board-i8-compose-ambiguous-new'}
        request={'protocol':'compose-intent-v1','request_id':'11223344-1234-4567-89ab-0123456789ab',
                 'template':['Keep ambiguous draft'],'duration':{'kind':'minutes','minutes':120},'silence':'hold'}
        route='v1/boards/hall-1/compose'
        results=self.run_sequence([
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'}),
            dict(method='POST',target=prefix+route,headers=auth,body=request),
            dict(target=prefix+route+'/'+request['request_id'],headers=auth),
            dict(method='POST',target=prefix+route,headers=auth,body=request)])
        self.assertEqual([r['status'] for r in results],[200,200,200,409])
        self.assertEqual(results[1]['body'],{})  # Synthetic malformed success, not a server receipt.
        self.assertEqual(results[2]['body']['status'],'unknown')
        self.assertEqual(results[2]['body']['request_id'],request['request_id'])

    def test_retained_route_behaviors_match_exported_migration_controls(self):
        cases=json.loads((ROOT/'Tests/Tooling/native-fixture-cases.json').read_text())['cases']
        # Each request owns fresh prefix state; exact legacy synthetic responses are compared.
        requests=[dict(method=c['method'],target='/board-'+c['scenario']+'-'+str(i)+'/api/'+c['route'],body=c['body']) for i,c in enumerate(cases)]
        # Authenticate each isolated namespace through the real fixture login route.
        inputs=[]
        for request in requests:
            prefix=request['target'].split('/api/')[0]
            inputs.append(dict(method='POST',target=prefix+'/api/auth/device/login',body={'username':'fixture_admin','password':'fixture-password','client_id':'fiestaboard-ios'}))
            request['headers']={'authorization':'Bearer fb_mob_fixture_'+prefix[1:]};inputs.append(request)
        results=self.run_sequence(inputs)
        for i,c in enumerate(cases):
            with self.subTest(scenario=c['scenario'],route=c['route'],body=c['body']):
                self.assertEqual(results[i*2+1]['status'],c['status'])
                self.assertEqual(results[i*2+1]['body'],c['response'])

    def test_i7_h2_fields_are_scoped_to_new_synthetic_cases(self):
        prefix='/board-i7-schedule-new/api/'
        result=self.run_sequence([
            dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password','client_id':'fiestaboard-ios'}),
            dict(target=prefix+'v1/boards/kitchen',headers={'authorization':'Bearer fb_mob_fixture_board-i7-schedule-new'})])[-1]
        self.assertEqual(result['status'],200)
        self.assertEqual(result['body']['next_change_reason'],'schedule')
        self.assertEqual(result['body']['next_page_id'],'morning')
        self.assertIsInstance(result['body']['next_change_at'],str)
        self.assertIsNone(result['body']['health']['reachable'])

    def test_bearer_is_bound_to_namespace_and_logout_revokes(self):
        prefix='/board-manual-a/api/'
        results=self.run_sequence([
          dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password','client_id':'fiestaboard-ios'}),
          dict(target=prefix+'v1/boards',headers={'authorization':'Bearer fb_mob_fixture_board-manual-a'}),
          dict(target='/board-manual-b/api/v1/boards',headers={'authorization':'Bearer fb_mob_fixture_board-manual-a'}),
          dict(method='DELETE',target=prefix+'auth/device/session',headers={'authorization':'Bearer fb_mob_fixture_board-manual-a'}),
          dict(target=prefix+'v1/boards',headers={'authorization':'Bearer fb_mob_fixture_board-manual-a'})])
        self.assertEqual([r['status'] for r in results],[200,200,401,200,401])
        self.assertTrue(results[0]['body']['access_token'].startswith('fb_mob_'))

    def test_revision_save_roundtrip_conflict_and_prefix_isolation(self):
        headers={'authorization':'Bearer fb_mob_fixture_board-manual-a'};prefix='/board-manual-a/api/'
        requests=[dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password','client_id':'fiestaboard-ios'}),
          dict(method='PUT',target=prefix+'v1/pages/hello',headers=headers,body={'expected_revision':'revision-hello','template':['EDITED'],'name':'Changed'}),
          dict(target=prefix+'v1/pages/hello',headers=headers),
          dict(method='PUT',target=prefix+'v1/pages/hello',headers=headers,body={'expected_revision':'revision-hello','name':'Stale'}),
          dict(target='/fixture-state/board-manual-a/pages/hello')]
        results=self.run_sequence(requests)
        self.assertEqual([r['status'] for r in results],[200,200,200,412,200])
        self.assertEqual(results[2]['body']['template'],['EDITED'])
        self.assertEqual(results[4]['body']['name'],'Changed')
        self.assertEqual(results[2]['body']['revision'],'revision-hello-saved-1')

    def test_runner_has_no_python_fixture_process(self):
        source=(ROOT/'scripts/test.sh').read_text()
        self.assertNotIn('python3 Tests/UITests/fixture_server.py',source)
        self.assertNotIn('TEST_RUNNER_FIXTURE_PORT',source)
        for path in (ROOT/'Tests/UITests').glob('*.swift'):
            text=path.read_text()
            self.assertNotIn('fixture_server.py',text,str(path))
            self.assertNotIn('TEST_RUNNER_FIXTURE_PORT',text,str(path))

    def test_recorded_variants_preserve_exact_bytes_status_and_headers(self):
        source=json.loads((ROOT/'Tests/Fixtures/SOURCE.json').read_text())
        requests=[dict(method=r['method'],target='/recorded-'+r['file'][:-5]+'/api'+r['path']) for r in source['responses']]
        results=self.run_sequence(requests)
        for r,result in zip(source['responses'],results):
            with self.subTest(file=r['file']):
                self.assertEqual(result['status'],r['status'])
                self.assertEqual(base64.b64decode(result['raw']),(ROOT/'Tests/Fixtures'/r['file']).read_bytes())
                self.assertEqual(result['headers'],r['headers'])

    def test_onboarding_auth_hold_releases_real_http_response_without_changing_auth_contract(self):
        process=subprocess.Popen([str(self.binary),str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json'),str(ROOT/'Tests/Fixtures'),'listen'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        def command(value):
            process.stdin.write(value+'\n');process.stdin.flush()
            self.assertTrue(select.select([process.stdout],[],[],3)[0], 'Fixture control must respond')
            return process.stdout.readline().strip()
        try:
            self.assertTrue(select.select([process.stdout],[],[],8)[0], 'Native listener must become ready')
            port=int(process.stdout.readline())
            baseline=urllib.request.urlopen(f'http://127.0.0.1:{port}/signin-unheld/api/auth/status',timeout=3)
            self.assertEqual(baseline.status,200)
            expected=json.load(baseline)
            self.assertEqual(command('hold-onboarding'),'ok')
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as worker:
                pending=worker.submit(urllib.request.urlopen,f'http://127.0.0.1:{port}/signin-i9-root-control/api/auth/status',timeout=6)
                try:
                    deadline=time.monotonic()+3
                    while command('onboarding-waiting') != 'waiting':
                        self.assertLess(time.monotonic(),deadline,'Auth HTTP request must reach hold')
                        time.sleep(0.01)
                    self.assertFalse(pending.done(),'Held auth/status must not complete before release')
                finally:
                    self.assertEqual(command('release-onboarding'),'ok')
                response=pending.result(timeout=3)
                self.assertEqual(response.status,200)
                self.assertEqual(json.load(response),expected)
        finally:
            process.stdin.write('release-onboarding\n');process.stdin.flush()
            process.stdin.close();process.wait(timeout=5);process.stdout.close();process.stderr.close()

    def test_post_status_pages_hold_preserves_real_authenticated_http_response(self):
        process=subprocess.Popen([str(self.binary),str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json'),str(ROOT/'Tests/Fixtures'),'listen'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        def command(value):
            process.stdin.write(value+'\n');process.stdin.flush()
            self.assertTrue(select.select([process.stdout],[],[],3)[0], 'Fixture control must respond')
            return process.stdout.readline().strip()
        try:
            self.assertTrue(select.select([process.stdout],[],[],8)[0], 'Native listener must become ready')
            port=int(process.stdout.readline()); base=f'http://127.0.0.1:{port}/signin-i9-root-pages-control/api/'
            login=urllib.request.Request(base+'auth/device/login',data=json.dumps({'username':'fixture_admin','password':'fixture-password'}).encode(),headers={'Content-Type':'application/json'})
            token=json.load(urllib.request.urlopen(login,timeout=3))['access_token']
            request=urllib.request.Request(base+'v1/pages',headers={'Authorization':'Bearer '+token})
            expected=json.load(urllib.request.urlopen(request,timeout=3))
            self.assertEqual(command('hold-handoff-pages'),'ok')
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as worker:
                pending=worker.submit(urllib.request.urlopen,request,timeout=6)
                try:
                    deadline=time.monotonic()+3
                    while command('handoff-pages-waiting') != 'waiting':
                        self.assertLess(time.monotonic(),deadline,'Authenticated pages HTTP request must reach hold')
                        time.sleep(0.01)
                    self.assertFalse(pending.done(),'Held pages must not finish before explicit release')
                finally:
                    self.assertEqual(command('release-handoff-pages'),'ok')
                response=pending.result(timeout=3)
                self.assertEqual(response.status,200);self.assertEqual(json.load(response),expected)
        finally:
            process.stdin.write('release-handoff-pages\n');process.stdin.flush()
            process.stdin.close();process.wait(timeout=5);process.stdout.close();process.stderr.close()

    def test_socket_fragmented_body_and_connection_drop(self):
        process=subprocess.Popen([str(self.binary),str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json'),str(ROOT/'Tests/Fixtures'),'listen'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            self.assertTrue(select.select([process.stdout],[],[],8)[0], "Native listener must become ready")
            port=int(process.stdout.readline())
            sock=socket.create_connection(('127.0.0.1',port),timeout=3)
            body=json.dumps(dict(username='fixture_admin',password='fixture-password',client_id='fiestaboard-ios')).encode()
            sock.sendall(b'POST /board-manual-socket/api/auth/device/login HTTP/1.1\r\nHost: fixture\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body[:3])
            time.sleep(0.02);sock.sendall(body[3:]);response=b''
            while True:
                chunk=sock.recv(65536)
                if not chunk:break
                response+=chunk
            sock.close();head,payload=response.split(b'\r\n\r\n',1)
            self.assertIn(b'HTTP/1.1 200',head)
            self.assertTrue(json.loads(payload)['access_token'].startswith('fb_mob_'))
            process.stdin.write('drop\n');process.stdin.flush();self.assertEqual(process.stdout.readline().strip(),'ok')
            sock=socket.create_connection(('127.0.0.1',port),timeout=3);sock.sendall(b'GET /ready HTTP/1.1\r\nHost: fixture\r\n\r\n')
            try:self.assertEqual(sock.recv(1024),b'')
            except ConnectionResetError:pass
            sock.close()
            process.stdin.write('probe\n');process.stdin.flush();self.assertEqual(process.stdout.readline().strip(),'failed')
            process.stdin.write('restore\n');process.stdin.flush();self.assertEqual(process.stdout.readline().strip(),'ok')
            sock=socket.create_connection(('127.0.0.1',port),timeout=3);sock.sendall(b'GET /ready HTTP/1.1\r\nHost: fixture\r\n\r\n')
            self.assertIn(b'HTTP/1.1 200',sock.recv(1024));sock.close()
            process.stdin.write('probe\n');process.stdin.flush();self.assertEqual(process.stdout.readline().strip(),'ready')
        finally:
            process.stdin.close();process.wait(timeout=5);process.stdout.close();process.stderr.close()

    def test_flexible_document_preserves_exact_large_integer_and_rejects_stale_revision(self):
        seed=json.loads((ROOT/'Tests/UITests/FixtureResources/retained-ui.json').read_text())
        original=seed['flexible']; blocks=original['blocks'];blocks[0]['text']='EDITED';blocks[1]['canvas']['content']['shapes'][1]['x']=7
        prefix='/flexible-unique/api/'
        results=self.run_sequence([
          dict(target=prefix+'v1/pages/flexible'),
          dict(method='PUT',target=prefix+'v1/pages/flexible',body={'expected_revision':'flex-r1','blocks':blocks,'style':None}),
          dict(target=prefix+'v1/pages/flexible'),
          dict(method='PUT',target=prefix+'v1/pages/flexible',body={'expected_revision':'flex-r1','name':'Stale'}),
          dict(method='POST',target=prefix+'pages/preview/flexible',body={'page':dict(type='flexible',blocks=blocks)}),
          dict(method='POST',target=prefix+'pages/preview/flexible',body={'board_id':'','page':dict(type='flexible',blocks=blocks)})])
        self.assertEqual([r['status'] for r in results],[200,200,200,412,200,404])
        self.assertEqual(results[0]['body']['blocks'][0]['extension']['large'],900719925474099312345678)
        self.assertEqual(results[2]['body']['blocks'],blocks)
        self.assertEqual(results[2]['body']['blocks'][1]['canvas']['content']['shapes'][1]['extension'],900719925474099312345678)
        self.assertEqual(results[4]['body']['message'],'EDITED')

    def test_mutable_board_actions_clear_override_and_restore_foreign_frame(self):
        prefix='/board-out-of-sync-actions/api/';h={'authorization':'Bearer fb_mob_fixture_board-out-of-sync-actions'}
        results=self.run_sequence([
          dict(method='POST',target=prefix+'auth/device/login',body={'username':'fixture_admin','password':'fixture-password'}),
          dict(target=prefix+'v1/boards/kitchen',headers=h),
          dict(method='POST',target=prefix+'v1/boards/kitchen/restore',headers=h),
          dict(target=prefix+'v1/boards/kitchen',headers=h),
          dict(method='PUT',target=prefix+'v1/boards/kitchen/active-page',headers=h,body={'page_id':'morning'}),
          dict(target=prefix+'v1/boards/kitchen',headers=h)])
        self.assertNotEqual(results[1]['body']['characters'],results[1]['body']['expected_characters'])
        self.assertEqual(results[3]['body']['characters'],results[3]['body']['expected_characters'])
        self.assertEqual(results[5]['body']['active_page_id'],'morning')
        self.assertIn('GOOD MORNING',results[5]['body']['text'])

    def test_ready_requires_http200_and_exact_native_fixture_identity(self):
        results=self.run_sequence([
            {'readyStatus':200,'readyBody':{'fixture':'native-onboarding'}},
            {'readyStatus':503,'readyBody':{'fixture':'native-onboarding'}},
            {'readyStatus':200,'readyBody':{'fixture':'wrong-service'}},
            {'readyStatus':200,'readyBody':{'fixture':'native-onboarding impostor'}},
            {'readyStatus':200,'readyBody':{}},
        ])
        self.assertEqual(results,[True,False,False,False,False])

    def test_native_fixture_readiness_never_skips_retained_journeys(self):
        for path in (ROOT/'Tests/UITests').glob('*.swift'):
            self.assertNotIn('XCTSkipUnless(ready',path.read_text(),str(path))
