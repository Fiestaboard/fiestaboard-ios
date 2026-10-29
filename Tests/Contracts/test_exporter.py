"""Local companion validation tests; importing this utility imports no backend."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = 'a' * 40


class ExporterTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('contract_exporter', ROOT / 'scripts/export-openapi.py')
        self.exporter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.exporter)
        self.tmp = tempfile.TemporaryDirectory(prefix='companion export ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.out = self.root / 'Contracts'
        self.out.mkdir()
        self.fixtures = self.root / 'Fixtures/contracts'

    def test_existing_wrong_source_companions_fail_instead_of_disappearing(self):
        for relative in ['Contracts/current-source-ledger.json', 'Contracts/current-capabilities.json',
                         'Fixtures/contracts/current/bootstrap-control.json', 'Fixtures/contracts/current/board-control.json']:
            with self.subTest(path=relative):
                path = self.root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({'source': {'commit': 'e' * 40}}))
                with self.assertRaisesRegex(ValueError, 'companion source commit mismatch'):
                    self.exporter.collect_artifacts(SHA, self.out, self.fixtures)
                path.unlink()

    def test_empty_root_has_no_companions_to_register(self):
        self.assertEqual(self.exporter.collect_artifacts(SHA, self.out, self.fixtures), [])

    def test_current_companions_are_all_registered(self):
        for relative in ['Contracts/current-source-ledger.json', 'Contracts/current-capabilities.json',
                         'Fixtures/contracts/current/bootstrap-control.json', 'Fixtures/contracts/current/board-control.json']:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({'source_commit': SHA}))
        artifacts = self.exporter.collect_artifacts(SHA, self.out, self.fixtures)
        self.assertEqual(len(artifacts), 4)
        self.assertTrue(all(item['source_commit'] == SHA and len(item['sha256']) == 64 for item in artifacts))
