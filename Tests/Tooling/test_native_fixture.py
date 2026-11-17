"""Host-executed migration controls for the Swift in-process fixture router."""
import json
import os
from pathlib import Path
import subprocess
import socket
import select
import time
import base64
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
                        str(ROOT/'Tests/UITests/FixtureRenderRoutes.swift'), str(main), '-o', str(cls.binary)],check=True,capture_output=True,text=True)

    def run_sequence(self, inputs):
        result = subprocess.run([str(self.binary), str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json'), str(ROOT/'Tests/Fixtures')],
          input=''.join(json.dumps(i)+'\n' for i in inputs),text=True,capture_output=True,check=True)
        return [json.loads(line) for line in result.stdout.splitlines()]

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
