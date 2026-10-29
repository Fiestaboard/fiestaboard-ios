"""Local stdlib utility tests: corrupted contracts must never pass integrity."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40


class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='contract checker ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'Contracts').mkdir()
        self.schema = {'openapi': '3.1.0', 'info': {'version': '10.0.0', 'description': 'No compatibility promise.'}, 'paths': {'/thing': {'get': {'operationId': 'readThing', 'responses': {'200': {'description': 'ok'}}}}}}
        self.docs = {
            'parity.json': {'schema_version': 1, 'source_commit': SHA, 'rows': [{'id': 'thing', 'area': 'test', 'workflow': 'Read', 'web_sources': [{'path': 'web/app.ts', 'line': 1}], 'operation_ids': ['readThing'], 'native_equivalent': 'Native screen', 'verification': 'planned', 'implementation_status': 'planned'}]},
            'operations.json': {'schema_version': 1, 'source_commit': SHA, 'operations': [{'id': 'readThing', 'method': 'GET', 'path': '/thing', 'surface': 'public', 'auth': ['session'], 'scope': 'resource', 'side_effects': 'none', 'replay': 'safe_read', 'web_sources': [{'path': 'web/app.ts', 'line': 1}], 'parity_ids': ['thing'], 'contract_status': 'candidate', 'verification_status': 'schema_only', 'notes': ''}]},
            'supported-servers.json': {'schema_version': 1, 'source_commit': SHA, 'releases': [{'version': '10.0.0', 'source_commit': SHA, 'status': 'candidate', 'evidence': []}], 'blockers': ['native pending']},
            'snapshot.json': {'schema_version': 1, 'source': {'commit': SHA, 'version': '10.0.0'}, 'generator': {'image': 'sha256:' + 'b'*64, 'python': '3.14.9', 'dependencies': ['fastapi==0.162.0'], 'output_seed': {'lock_sha256': 'c'*64}}, 'source_evidence': {'web/app.ts': {'sha256': 'd'*64, 'lines': 5}}, 'schemas': {}, 'blockers': ['fixtures pending']},
        }
        self.docs['snapshot.json']['source_evidence']['web/app.ts']['source_commit'] = SHA
        for doc, key in [('parity.json', 'rows'), ('operations.json', 'operations')]:
            for item in self.docs[doc][key]:
                for ref in item['web_sources']:
                    ref.update(source_commit=SHA, sha256='d' * 64)
        self.docs['operations.json']['operations'][0]['backend_sources'] = copy.deepcopy(self.docs['operations.json']['operations'][0]['web_sources'])
        self.sync_schemas()

    def sync_schemas(self):
        for surface, name in [('public', 'public-openapi.json'), ('internal', 'mobile-internal-openapi.json')]:
            data = (json.dumps(self.schema, indent=2, sort_keys=True) + '\n').encode()
            (self.root / 'Contracts' / name).write_bytes(data)
            self.docs['snapshot.json']['schemas'][surface] = {'path': 'Contracts/' + name, 'sha256': hashlib.sha256(data).hexdigest(), 'operation_count': 1}

    def run_check(self, *args):
        self.docs['snapshot.json'].setdefault('source_manifest_sha256', hashlib.sha256(json.dumps(self.docs['snapshot.json']['source_evidence'], sort_keys=True, separators=(',', ':')).encode()).hexdigest())
        for name, doc in self.docs.items():
            (self.root / 'Contracts' / name).write_text(json.dumps(doc))
        return subprocess.run([sys.executable, str(ROOT / 'scripts/check-contracts.py'), '--root', str(self.root), *args], capture_output=True, text=True)

    def test_wrong_source_evidence_commit_fails(self):
        self.docs['snapshot.json']['source_evidence']['web/app.ts']['source_commit'] = 'e' * 40
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_wrong_reference_hash_fails(self):
        self.docs['parity.json']['rows'][0]['web_sources'][0]['sha256'] = 'e' * 64
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_stale_reference_source_fails(self):
        self.docs['operations.json']['operations'][0]['web_sources'][0]['source_commit'] = 'e' * 40
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_supported_operation_requires_hashed_current_evidence(self):
        self.docs['operations.json']['operations'][0]['contract_status'] = 'supported'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_runtime_operation_requires_hashed_current_evidence(self):
        self.docs['operations.json']['operations'][0]['verification_status'] = 'runtime_verified'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_verified_row_requires_hashed_current_evidence(self):
        self.docs['parity.json']['rows'][0]['implementation_status'] = 'verified'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_wrong_source_manifest_hash_fails(self):
        self.docs['snapshot.json']['source_manifest_sha256'] = 'e' * 64
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_current_artifact_wrong_hash_fails(self):
        (self.root / 'fixture.json').write_text('{}')
        self.docs['snapshot.json']['artifacts'] = [{'source_commit': SHA, 'path': 'fixture.json', 'sha256': 'e' * 64}]
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_current_artifact_wrong_source_fails(self):
        content = json.dumps({'source_commit': 'e' * 40}).encode()
        (self.root / 'fixture.json').write_bytes(content)
        self.docs['snapshot.json']['artifacts'] = [{'source_commit': SHA, 'path': 'fixture.json', 'sha256': hashlib.sha256(content).hexdigest()}]
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_capability_schema_hash_mismatch_fails(self):
        artifact = {'source_commit': SHA, 'kind': 'current-capabilities', 'operations': [
            {'id': 'readThing', 'method': 'GET', 'path': '/thing', 'surface': 'public', 'schema_sha256': 'e' * 64}
        ]}
        content = json.dumps(artifact).encode()
        (self.root / 'capabilities.json').write_bytes(content)
        self.docs['snapshot.json']['artifacts'] = [{'source_commit': SHA, 'path': 'capabilities.json', 'sha256': hashlib.sha256(content).hexdigest()}]
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_valid_candidate_passes_integrity(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_files_fail(self):
        del self.docs['parity.json']
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_duplicate_parity_fails(self):
        self.docs['parity.json']['rows'] *= 2
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_duplicate_operation_fails(self):
        self.docs['operations.json']['operations'] *= 2
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_missing_parity_reference_fails(self):
        self.docs['operations.json']['operations'][0]['parity_ids'] = ['missing']
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_unknown_operation_fails(self):
        self.docs['parity.json']['rows'][0]['operation_ids'] = ['missing']
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_wrong_method_path_fails(self):
        self.docs['operations.json']['operations'][0]['method'] = 'POST'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_unresolved_local_ref_fails_even_with_updated_hash(self):
        self.schema['paths']['/thing']['get']['responses']['200']['schema'] = {'$ref': '#/components/schemas/Missing'}
        self.sync_schemas()
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_changed_schema_hash_fails(self):
        (self.root / 'Contracts/public-openapi.json').write_text('{}')
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_source_evidence_out_of_range_fails(self):
        self.docs['parity.json']['rows'][0]['web_sources'][0]['line'] = 900
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_invented_supported_release_fails_integrity(self):
        self.docs['supported-servers.json']['releases'][0]['status'] = 'supported'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_candidate_fails_release_readiness(self):
        self.assertNotEqual(self.run_check('--release-ready').returncode, 0)

    def test_non_operation_equivalence_requires_reason(self):
        row = self.docs['parity.json']['rows'][0]
        row['operation_ids'] = []
        row['native_equivalent'] = ''
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_authored_inventory_id_can_differ_from_schema_id(self):
        self.docs['operations.json']['operations'][0]['id'] = 'read_thing'
        self.docs['parity.json']['rows'][0]['operation_ids'] = ['read_thing']
        result = self.run_check()
        self.assertEqual(result.returncode,0,result.stderr)

    def test_one_sided_row_mapping_fails(self):
        extra = copy.deepcopy(self.docs['parity.json']['rows'][0])
        extra['id'] = 'other'
        self.docs['parity.json']['rows'].append(extra)
        self.assertNotEqual(self.run_check().returncode,0)

    def test_missing_backend_source_fails(self):
        del self.docs['operations.json']['operations'][0]['backend_sources']
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_missing_operation_auth_field_fails(self):
        del self.docs['operations.json']['operations'][0]['auth']
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_unknown_status_fails(self):
        self.docs['operations.json']['operations'][0]['verification_status'] = 'looks_good'
        self.assertNotEqual(self.run_check().returncode, 0)

    def test_duplicate_operation_mapping_fails(self):
        self.docs['parity.json']['rows'][0]['operation_ids'] *= 2
        self.assertNotEqual(self.run_check().returncode, 0)

    def make_release_ready(self):
        self.docs['snapshot.json']['blockers'] = []
        self.docs['supported-servers.json']['blockers'] = []
        self.docs['parity.json']['rows'][0]['implementation_status'] = 'verified'
        op = self.docs['operations.json']['operations'][0]
        op['verification_status'] = 'runtime_verified'
        op['contract_status'] = 'supported'
        release = self.docs['supported-servers.json']['releases'][0]
        release['status'] = 'supported'
        release['acceptance'] = {key:'passed' for key in ['auth','oauth','conditional_writes','operation_fixtures','native_physical','topology']}
        evidence = b'synthetic fully verified release fixture; not product proof\n'
        (self.root/'proof.txt').write_bytes(evidence)
        release['evidence'] = [{'source_commit':SHA,'path':'proof.txt','sha256':hashlib.sha256(evidence).hexdigest(),'category':category} for category in release['acceptance']]
        self.docs['parity.json']['rows'][0]['evidence'] = release['evidence']
        op['evidence'] = release['evidence']
        return release

    def test_fully_evidenced_release_ready_can_pass(self):
        release = self.make_release_ready()
        result = self.run_check('--release-ready')
        self.assertEqual(result.returncode,0,result.stderr)
        # A supported claim with only one acceptance category is insufficient.
        release['evidence'] = release['evidence'][:1]
        self.assertNotEqual(self.run_check('--release-ready').returncode,0)

    def test_public_blocked_contract_fails_release_readiness(self):
        self.make_release_ready()
        self.docs['operations.json']['operations'][0]['contract_status'] = 'blocked'
        self.assertNotEqual(self.run_check('--release-ready').returncode,0)

    def test_public_candidate_contract_fails_release_readiness(self):
        self.make_release_ready()
        self.docs['operations.json']['operations'][0]['contract_status'] = 'candidate'
        self.assertNotEqual(self.run_check('--release-ready').returncode,0)

    def test_integrity_message_does_not_claim_release_ready(self):
        result = self.run_check()
        self.assertIn('NOT release ready', result.stdout)

    def test_json_error_is_reported_without_traceback(self):
        self.run_check()
        (self.root / 'Contracts/parity.json').write_text('{')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/check-contracts.py'), '--root', str(self.root)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()
