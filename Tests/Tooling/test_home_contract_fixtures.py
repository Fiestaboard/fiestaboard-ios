"""Exact response provenance and the Docker/host evidence boundary for I7."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / 'Tests/Fixtures/Home'

class HomeContractFixtureTests(unittest.TestCase):
    def test_atomic_undo_responses_are_from_the_unmerged_immutable_backend(self):
        self.verify(HOME/'HostUndo', HOME/'requests-undo.json', 34, '6be367f4a76891d7b11a114a81a7d79f1b50534a')
        source = json.loads((HOME/'HostUndo/SOURCE.json').read_text())
        self.assertIn('not Docker C5 proof',source['method'])
        for name in ['undo-cancel','undo-restored','undo-indefinite-cancel','undo-empty-cancel']:
            entry = next(r for r in source['responses'] if r['file'] == name+'.json')
            self.assertEqual(entry['headers']['cache-control'],'no-store')

    def test_original_docker_responses_and_manifest_are_intact(self):
        self.verify(HOME, HOME/'requests.json', 13, 'f47da6e4e764fc2826f396210f013e45dc1a7fd8')
        source = json.loads((HOME/'SOURCE.json').read_text())
        self.assertTrue(source['method'].startswith('Docker'))

    def test_host_supplements_are_real_responses_with_distinct_provenance(self):
        for directory, commit in [('HostSupplement','f47da6e4e764fc2826f396210f013e45dc1a7fd8'),
                                  ('HostV11','e8306aca0df3ee26a693afe57760d83b1ec3c772')]:
            self.verify(HOME/directory, HOME/'requests-host.json', 19, commit)
            source = json.loads((HOME/directory/'SOURCE.json').read_text())
            self.assertTrue(source['method'].startswith('Host isolated'))
            self.assertIn('not Docker C5 proof', source['method'])
            for name in ['page-select-unauthorized','override-cancel-unauthorized']:
                entry = next(r for r in source['responses'] if r['file'] == name+'.json')
                self.assertEqual(entry['status'],401)

    def verify(self, directory, manifest_path, count, commit):
        source = json.loads((directory/'SOURCE.json').read_text())
        self.assertEqual(source['hubCommit'], commit)
        self.assertEqual(source['requestManifestSHA256'], hashlib.sha256(manifest_path.read_bytes()).hexdigest())
        manifest = json.loads(manifest_path.read_text())['requests']
        self.assertEqual(len(source['responses']), count)
        self.assertEqual({r['file'] for r in source['responses']}, {r['id']+'.json' for r in manifest})
        scenario = source['scenario']
        for response in source['responses']:
            body = (directory/response['file']).read_bytes()
            self.assertEqual(hashlib.sha256(body).hexdigest(), response['sha256'], response['file'])
            self.assertIsInstance(json.loads(body),dict)
            self.assertNotIn(b'fb_mob_',body,'Recorded responses must contain no session token')
            request = next(r for r in manifest if r['id']+'.json' == response['file'])
            self.assertEqual(response['method'],request['method'])
            self.assertEqual(response['status'],request['status'])
            self.assertEqual(response['path'],request['path'].replace('{kitchen}',scenario['kitchen']).replace('{desk}',scenario['desk']))
