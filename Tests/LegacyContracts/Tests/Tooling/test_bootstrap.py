"""Exercise download/bootstrap behavior with real disposable Git repositories."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/bootstrap-contracts.py'


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bootstrap tests ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'upstream with spaces'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Tooling Tests')
        self.git('config', 'user.email', 'tooling@example.invalid')
        (self.repo / 'version.txt').write_text('pinned\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'pinned')
        self.commit = self.git('rev-parse', 'HEAD').strip()
        (self.repo / 'version.txt').write_text('later\n')
        self.git('commit', '-qam', 'later')
        self.snapshot = self.root / 'snapshot.json'
        self.snapshot.write_text(json.dumps({'source': {'commit': self.commit, 'version': 'test'}}))
        self.destination = self.root / 'fresh bootstrap'

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True)

    def run_bootstrap(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), '--snapshot', str(self.snapshot),
                               '--source-repository', str(self.repo), '--destination', str(self.destination),
                               *args], text=True, capture_output=True)

    def test_downloads_exact_metadata_commit_instead_of_repository_head(self):
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / 'source/version.txt').read_text(), 'pinned\n')
        receipt = json.loads((self.destination / 'bootstrap.json').read_text())
        self.assertEqual(receipt['source']['commit'], self.commit)
        self.assertNotIn('image', receipt)

    def test_existing_destination_is_never_reused_or_replaced(self):
        self.destination.mkdir()
        sentinel = self.destination / 'user data'
        sentinel.write_text('keep')
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must not exist', result.stderr)
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_existing_dangling_symlink_destination_is_refused(self):
        target = self.root / 'symlink target'
        self.destination.symlink_to(target, target_is_directory=True)
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must not exist', result.stderr)
        self.assertFalse(target.exists())

    def test_rejects_mutable_source_reference_before_creating_destination(self):
        self.snapshot.write_text(json.dumps({'source': {'commit': 'main', 'version': 'test'}}))
        result = self.run_bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('40-character', result.stderr)
        self.assertFalse(self.destination.exists())

    def test_test_requires_explicit_build_or_immutable_image(self):
        result = self.run_bootstrap('--test')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--build or --image', result.stderr)
        self.assertFalse(self.destination.exists())

    def test_build_tests_with_produced_image_not_a_preexisting_tag(self):
        # Only the external Docker runner is substituted; clone and receipt are real.
        runner = self.root / 'runner.py'
        log = self.root / 'runner-log.jsonl'
        image = 'sha256:' + 'a' * 64
        runner.write_text('import json, pathlib, sys\n'
                          f'log = pathlib.Path({str(log)!r})\n'
                          'with log.open("a") as f: f.write(json.dumps(sys.argv[1:]) + "\\n")\n'
                          f'print({image!r})\n')
        result = self.run_bootstrap('--build', '--test', '--runner', str(runner))
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ['build', 'test'])
        self.assertNotIn('--bootstrap', calls[0])
        self.assertEqual(calls[1][calls[1].index('--image') + 1], image)
        receipt = json.loads((self.destination / 'bootstrap.json').read_text())
        self.assertEqual(receipt['image'], image)


if __name__ == '__main__':
    unittest.main()
