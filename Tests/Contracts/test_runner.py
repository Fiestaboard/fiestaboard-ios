"""Run the local utility against a dirty repository, with hostile-looking paths."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RunnerTests(unittest.TestCase):
    def test_archive_uses_commit_not_worktree_or_private_config(self):
        with tempfile.TemporaryDirectory(prefix='archive space $ ') as tmp:
            repo = Path(tmp) / 'source'
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
            git('init', '-q')
            (repo/'safe.txt').write_text('committed\n')
            (repo/'.env').write_text('FAKE_PRIVATE=example\n')
            git('add', '.')
            git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture')
            sha = git('rev-parse','HEAD')
            (repo/'safe.txt').write_text('dirty\n')
            (repo/'untracked').write_text('private\n')
            dest = Path(tmp)/'export'
            result = subprocess.run(['python3',str(ROOT/'scripts/contract-backend.py'),'prepare','--repo',str(repo),'--commit',sha,'--destination',str(dest)], capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual((dest/'safe.txt').read_text(),'committed\n')
            self.assertFalse((dest/'.env').exists())
            self.assertFalse((dest/'untracked').exists())

    def test_refusing_mutable_commit_expression(self):
        result = subprocess.run(['python3',str(ROOT/'scripts/contract-backend.py'),'prepare','--repo','.', '--commit','HEAD','--destination','/tmp/not-created-contract'],cwd=ROOT,capture_output=True)
        self.assertNotEqual(result.returncode,0)


if __name__ == '__main__':
    unittest.main()
