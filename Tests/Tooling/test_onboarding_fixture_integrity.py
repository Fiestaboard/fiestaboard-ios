import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'Tests/Fixtures/Onboarding'


class OnboardingFixtureIntegrity(unittest.TestCase):
    def test_reset_contract_retains_original_source_and_all_seventeen_response_hashes(self):
        source = json.loads((DIRECTORY / 'SOURCE.json').read_text())
        requests = json.loads((DIRECTORY / 'requests.json').read_text())['requests']
        self.assertEqual(source['hubCommit'], 'f47da6e4e764fc2826f396210f013e45dc1a7fd8')
        self.assertEqual(source['dockerImageID'], 'sha256:c181d7a4afe23a7f2b0a704a1225ae81ba4a9d94dc56ef26395581ddfe575cf6')
        for field, path in [
            ('requestManifestSHA256', DIRECTORY / 'requests.json'),
            ('environmentSHA256', DIRECTORY / 'environment.txt'),
            ('recorderSHA256', ROOT / 'scripts/record-onboarding-fixtures.py'),
            ('dependencyLockSHA256', ROOT / 'Tests/Fixtures/Home/HostUndo/environment.txt'),
        ]:
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), source[field], field)
        contracts = []
        self.assertEqual(len(source['responses']), 17)
        for entry in source['responses']:
            self.assertEqual(hashlib.sha256((DIRECTORY / entry['file']).read_bytes()).hexdigest(), entry['sha256'], entry['file'])
            contracts.append({'id': Path(entry['file']).stem,
                              **{key: entry[key] for key in ['method', 'path', 'status']}})
        self.assertEqual(contracts, requests)

    def test_recorded_reset_does_not_mint_authority_and_both_mobile_tokens_are_revoked(self):
        source = json.loads((DIRECTORY / 'SOURCE.json').read_text())
        entries = {Path(entry['file']).stem: entry for entry in source['responses']}
        self.assertEqual(json.loads((DIRECTORY / 'reset-code-after-weak.json').read_text()), {'status': 'ok'})
        self.assertEqual(entries['device-session-after-reset']['status'], 401)
        self.assertEqual(entries['device-session-revoke']['status'], 200)
        self.assertEqual(entries['device-session-finally-revoked']['status'], 401)
        invalid = (DIRECTORY / 'reset-invalid-code.json').read_bytes()
        for name in ['reset-code-reused', 'reset-superseded-code', 'reset-expired-code']:
            self.assertEqual((DIRECTORY / (name + '.json')).read_bytes(), invalid, name)
        for name in ['reset-shared-lockout', 'device-login-shared-lockout']:
            self.assertEqual(entries[name]['status'], 429)
            self.assertEqual(entries[name]['headers']['retry-after'], '60')
