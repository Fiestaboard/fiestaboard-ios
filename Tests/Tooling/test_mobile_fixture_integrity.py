import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MobileFixtureIntegrity(unittest.TestCase):
    def test_actual_recorded_responses_match_source_sha_and_phone_contract(self):
        directory = ROOT / 'Tests/Fixtures'
        source = json.loads((directory / 'SOURCE.json').read_text())
        self.assertEqual(source['hubCommit'], 'f47da6e4e764fc2826f396210f013e45dc1a7fd8')
        self.assertEqual(source['requestManifestSHA256'], hashlib.sha256((directory/'requests.json').read_bytes()).hexdigest())
        expected = {'device-login':200,'device-login-invalid':401,'device-login-locked':429,
                    'device-session-expired':401,'device-session-revoked':401}
        for entry in source['responses']:
            data = (directory / entry['file']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(),entry['sha256'],entry['file'])
            name = Path(entry['file']).stem
            if name in expected:
                self.assertEqual(entry['status'],expected.pop(name))
        self.assertFalse(expected)
        login = json.loads((directory/'device-login.json').read_text())
        self.assertTrue(login['access_token'].startswith('fb_mob_'))
        self.assertEqual(login['scope'],'control')
        self.assertEqual(login['token_type'],'Bearer')
        self.assertIn('revoked',source['credentialSafety'])

    def test_historical_contracts_are_archived_and_excluded_from_native_runtime(self):
        for path in ['Contracts','Fixtures/contracts','scripts/bootstrap-contracts.py','scripts/contract-backend.py','scripts/export-openapi.py','scripts/check-contracts.py']:
            self.assertFalse((ROOT/path).exists(),path)
            self.assertTrue((ROOT/'Tests/LegacyContracts'/path).exists(),path)
        self.assertNotIn('LegacyContracts', (ROOT/'project.yml').read_text())
        for path in [*ROOT.glob('App/**/*.swift'), *ROOT.glob('Packages/*/Sources/**/*.swift'), *ROOT.glob('Tests/UITests/*.swift')]:
            self.assertNotIn('LegacyContracts',path.read_text(),str(path))
