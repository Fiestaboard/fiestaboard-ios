#!/usr/bin/env python3
"""Compare XcodeGen output in a disposable copy, preserving local signing edits."""
import argparse
import difflib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path('FiestaBoard.xcodeproj')


def project_files(root):
    project = root / PROJECT
    result = {PROJECT / 'project.pbxproj': (project / 'project.pbxproj').read_text()}
    schemes = project / 'xcshareddata/xcschemes'
    for path in sorted(schemes.glob('*.xcscheme')):
        result[path.relative_to(root)] = path.read_text()
    # Team selection is local user state. No other project differences are masked.
    pbx = PROJECT / 'project.pbxproj'
    result[pbx] = re.sub(r'(?m)^(\s*DEVELOPMENT_TEAM\s*=\s*)[^;]*;',
                         r'\1"";', result[pbx])
    return result


def check(root, xcodegen):
    original = project_files(root)
    with tempfile.TemporaryDirectory(prefix='fiestaboard-project-') as temporary:
        copy = Path(temporary) / 'checkout'
        shutil.copytree(root, copy, symlinks=True,
                        ignore=shutil.ignore_patterns('.git', '.build', '.reference', '.worktrees',
                                                      '.superpowers', 'xcuserdata', '__pycache__',
                                                      '.DS_Store'))
        # Generate from scratch so obsolete shared schemes cannot survive copying.
        shutil.rmtree(copy / PROJECT)
        result = subprocess.run([xcodegen, 'generate', '--spec', 'project.yml'], cwd=copy)
        if result.returncode:
            raise ValueError('project generation failed (original project untouched)')
        generated = project_files(copy)
    differences = []
    for path in sorted(original.keys() | generated.keys()):
        before = original.get(path, '').splitlines(keepends=True)
        after = generated.get(path, '').splitlines(keepends=True)
        if before != after:
            differences.extend(difflib.unified_diff(before, after, fromfile=str(path),
                                                     tofile='generated/' + str(path)))
    if differences:
        sys.stderr.writelines(differences)
        raise ValueError('project drift detected; regenerate deliberately in an isolated checkout and preserve signing')
    print('Project and shared schemes match XcodeGen; original project untouched (local Team ignored).')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--xcodegen', default='xcodegen')
    args = parser.parse_args()
    try:
        check(args.root.resolve(), args.xcodegen)
    except (OSError, ValueError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
