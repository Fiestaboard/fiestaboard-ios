"""The generation check must never write the user's original project."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/check-project.py'


class CheckProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='project tests ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'checkout'
        self.project = self.root / 'FiestaBoard.xcodeproj'
        self.schemes = self.project / 'xcshareddata/xcschemes'
        self.schemes.mkdir(parents=True)
        (self.root / 'project.yml').write_text('name: FiestaBoard\n')
        self.pbx = self.project / 'project.pbxproj'
        self.pbx.write_text('DEVELOPMENT_TEAM = USERTEAM;\nPRODUCT_NAME = FiestaBoard;\n')
        (self.schemes / 'FiestaBoard.xcscheme').write_text('<Scheme version="1.7" />\n')
        (self.root / '.reference').mkdir()
        (self.root / '.build').mkdir()
        self.generator = Path(self.temp.name) / 'generator'

    def run_check(self, generated, scheme='<Scheme version="1.7" />\n', exit_code=0):
        self.generator.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\n'
                                  'assert not Path(".reference").exists()\n'
                                  'assert not Path(".build").exists()\n'
                                  f'assert Path.cwd() != Path({str(self.root)!r})\n'
                                  'Path("FiestaBoard.xcodeproj/xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)\n'
                                  f'Path("FiestaBoard.xcodeproj/project.pbxproj").write_text({generated!r})\n'
                                  f'Path("FiestaBoard.xcodeproj/xcshareddata/xcschemes/FiestaBoard.xcscheme").write_text({scheme!r})\n'
                                  f'raise SystemExit({exit_code})\n')
        self.generator.chmod(0o755)
        before = self.pbx.read_bytes()
        result = subprocess.run([sys.executable, str(SCRIPT), '--root', str(self.root),
                                 '--xcodegen', str(self.generator)], text=True, capture_output=True)
        self.assertEqual(self.pbx.read_bytes(), before)
        return result

    def test_local_development_team_is_ignored_without_changing_original(self):
        result = self.run_check('DEVELOPMENT_TEAM = "";\nPRODUCT_NAME = FiestaBoard;\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_non_signing_project_drift_fails(self):
        result = self.run_check('DEVELOPMENT_TEAM = "";\nPRODUCT_NAME = Wrong;\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('project.pbxproj', result.stderr)

    def test_shared_scheme_drift_fails(self):
        result = self.run_check(self.pbx.read_text(), '<Scheme version="2" />\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FiestaBoard.xcscheme', result.stderr)

    def test_generation_failure_does_not_modify_original(self):
        result = self.run_check('broken', exit_code=7)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('generation failed', result.stderr)

    def test_obsolete_shared_scheme_cannot_survive_from_the_copied_project(self):
        (self.schemes / 'Obsolete.xcscheme').write_text('<Scheme />\n')
        result = self.run_check(self.pbx.read_text())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Obsolete.xcscheme', result.stderr)


if __name__ == '__main__':
    unittest.main()
