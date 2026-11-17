"""Run the build wrapper with only the external Xcode build tool substituted."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BuildDraftTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='build draft ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/build-draft.sh', self.root / 'scripts/build-draft.sh')
        self.output = self.root / 'arguments.json'
        tool = self.root / 'xcodebuild'
        tool.write_text('#!/usr/bin/env python3\nimport json, pathlib, sys\n'
                        f'pathlib.Path({str(self.output)!r}).write_text(json.dumps(sys.argv[1:]))\n')
        tool.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.root) + os.pathsep + os.environ['PATH']}

    def run_build(self, *args):
        result = subprocess.run(['/bin/bash', str(self.root / 'scripts/build-draft.sh'), *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(self.output.read_text())

    def test_default_build_uses_live_scheme_unsigned_simulator(self):
        args = self.run_build()
        self.assertEqual(args[args.index('-scheme') + 1], 'FiestaBoard')
        self.assertEqual(args[args.index('-destination') + 1], 'generic/platform=iOS Simulator')
        self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
        self.assertEqual(args[-1], 'build')
        self.assertNotIn('-archivePath', args)

    def test_archive_uses_dedicated_archive_path(self):
        args = self.run_build('archive')
        self.assertEqual(args[-1], 'archive')
        self.assertEqual(args[args.index('-archivePath') + 1], str(Path.home() / 'Library/Developer/FiestaBoard/ios/FiestaBoard.xcarchive'))

    def test_unknown_mode_never_invokes_xcodebuild(self):
        result = subprocess.run(['/bin/bash', str(self.root / 'scripts/build-draft.sh'), 'unknown'],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
