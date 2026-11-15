"""Additive corpus integrity/comparison check; no backend imports or network."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent


def verify(root=ROOT):
    manifest = json.loads((root / 'manifest.json').read_text())
    assert manifest['source'] == {'commit': 'ff2415c4a646b55510f6f633c78915cdc9c333f2', 'version': '10.1.20'}
    for name, digest in manifest['artifacts'].items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    for name, count in manifest['case_counts'].items():
        actual = json.loads((root / name).read_text())
        previous = json.loads((ROOT.parent / 'current' / name).read_text())
        assert actual['source'] == manifest['source']
        assert len(actual['cases']) == count
        assert [c['id'] for c in actual['cases']] == [c['id'] for c in previous['cases']]
        changed = [a['id'] for a, b in zip(actual['cases'], previous['cases']) if a != b]
        assert changed == manifest['changed_case_ids'][name]
        # All differences are explicit server version metadata, not receipts.
        normalized = json.loads(json.dumps(actual['cases']).replace('10.1.20', '10.1.17'))
        assert normalized == previous['cases']
    return manifest


class IntegrityTests(unittest.TestCase):
    def test_manifest_and_receipt_comparison(self):
        verify()

    def test_changed_receipt_fails_integrity(self):
        import tempfile
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in ROOT.iterdir():
                if path.is_file():
                    shutil.copyfile(path, root / path.name)
            path = root / 'board-control.json'
            fixture = json.loads(path.read_text())
            next(c for c in fixture['cases'] if c['id'] == 'restore_ack')['response']['body']['device_observed'] = True
            path.write_text(json.dumps(fixture))
            with self.assertRaises(AssertionError):
                verify(root)


if __name__ == '__main__':
    unittest.main()
