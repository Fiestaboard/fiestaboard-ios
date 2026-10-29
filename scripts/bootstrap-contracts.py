#!/usr/bin/env python3
"""Download the committed source pin; optionally clean-build and test in Docker.

Only Git and Python's standard library execute locally. Backend imports and tests
remain inside contract-backend.py's isolated containers. No local substrate tag
or existing .reference/.build directory is used.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = 'https://github.com/Fiestaboard/FiestaBoard.git'


def bootstrap(args):
    snapshot = json.loads(args.snapshot.read_text())
    source = snapshot['source']
    commit = source['commit']
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('source.commit must be a full immutable 40-character SHA')
    if args.image and not re.fullmatch(r'sha256:[0-9a-f]{64}', args.image):
        raise ValueError('--image must be an immutable sha256 content ID')
    if args.test and not (args.build or args.image):
        raise ValueError('--test requires --build or --image')
    if args.build and args.image:
        raise ValueError('choose --build or --image, not both')
    if args.destination.exists() or args.destination.is_symlink():
        raise ValueError('destination must not exist (will not replace user files)')
    destination = args.destination.resolve()
    destination.mkdir(parents=True)
    repo = destination / 'source'
    subprocess.run(['git', 'init', '--quiet', str(repo)], check=True)
    git = ['git', '-C', str(repo)]
    subprocess.run([*git, 'remote', 'add', 'origin', args.source_repository], check=True)
    subprocess.run([*git, 'fetch', '--quiet', '--depth', '1', 'origin', commit], check=True)
    subprocess.run([*git, 'checkout', '--quiet', '--detach', 'FETCH_HEAD'], check=True)
    actual = subprocess.check_output([*git, 'rev-parse', 'HEAD'], text=True).strip()
    if actual != commit:
        raise ValueError('downloaded source does not match committed metadata')
    receipt = {'source': {'commit': commit, 'version': source['version']}}
    common = ['--repo', str(repo), '--commit', commit]
    image = args.image
    if args.build:
        # Unique tag is only a build output handle; all execution uses its content ID.
        result = subprocess.run([sys.executable, str(args.runner), 'build', *common,
                                 '--tag', 'fiestaboard-ios-contract:clean-' + uuid.uuid4().hex],
                                check=True, stdout=subprocess.PIPE, text=True)
        print(result.stdout, end='')
        lines = result.stdout.strip().splitlines()
        image = lines[-1] if lines else ''
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', image):
            raise ValueError('build did not return an immutable image ID on its final line')
    if image:
        receipt['image'] = image
    # Preserve a useful source/image receipt even if a later test fails.
    (destination / 'bootstrap.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if args.test:
        subprocess.run([sys.executable, str(args.runner), 'test', *common, '--image', image], check=True)
    print('Bootstrap receipt: ' + str(destination / 'bootstrap.json'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, default=ROOT / 'Contracts/snapshot.json')
    parser.add_argument('--source-repository', default=UPSTREAM,
                        help='upstream Git URL; use a local repository for offline tooling tests')
    parser.add_argument('--destination', required=True, type=Path, help='new disposable directory')
    parser.add_argument('--build', action='store_true', help='build clean Dockerfile, never bootstrap substrate')
    parser.add_argument('--test', action='store_true', help='run isolated boundary tests with the selected image')
    parser.add_argument('--image', help='already built immutable image ID (requires local Docker availability)')
    parser.add_argument('--runner', type=Path, default=ROOT / 'scripts/contract-backend.py')
    args = parser.parse_args()
    try:
        bootstrap(args)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
