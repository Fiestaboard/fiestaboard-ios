"""Host-executed migration controls for the Swift in-process fixture router."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path.home() / 'Library/Developer/FiestaBoard/ios/cx-i5-native-fixture-controls'

class NativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        main = BUILD / 'main.swift'
        main.write_text('''import Foundation
let router = try FixtureRouter(resourceURL: URL(fileURLWithPath: CommandLine.arguments[1]))
while let line = readLine() {
    let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let response = router.respond(method: input["method"] as? String ?? "GET", target: input["target"] as! String,
       headers: input["headers"] as? [String: String] ?? [:], body: try JSONSerialization.data(withJSONObject: input["body"] ?? [:]))
    let result: [String: Any] = ["status": response.status, "body": try JSONSerialization.jsonObject(with: response.body.isEmpty ? Data("null".utf8) : response.body, options: [.fragmentsAllowed]), "headers": response.headers]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .fragmentsAllowed]), encoding: .utf8)!)
}
''')
        cls.binary = BUILD / 'controls'
        subprocess.run(['swiftc', '-module-cache-path', str(BUILD/'modules'),
                        str(ROOT/'Tests/UITests/FixtureRouter.swift'),
                        str(ROOT/'Tests/UITests/FixtureBoardRoutes.swift'),
                        str(ROOT/'Tests/UITests/FixtureRenderRoutes.swift'), str(main), '-o', str(cls.binary)],check=True,capture_output=True,text=True)

    def run_sequence(self, inputs):
        result = subprocess.run([str(self.binary), str(ROOT/'Tests/UITests/FixtureResources/retained-ui.json')],
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
