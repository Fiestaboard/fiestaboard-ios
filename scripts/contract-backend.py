#!/usr/bin/env python3
"""Explicit local stdlib utility: archive pinned source; backend runs only in Docker."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

BOOTSTRAP_IMAGE = 'sha256:77fc6a98ca7f16f15810fd0bd8b3b51e7a0ed81b90c38ce8ede492cd8a4caa62'
IMAGE = 'sha256:eade8ae94aad6b921665aa8e9f44eca135c9764d79b24ff103d0501403c71f37'
ROOT = Path(__file__).resolve().parents[1]
OMITTED = {'.env', 'data', 'config.json', 'auth.json'}


def prepare(repo, commit, destination):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('--commit must be a full immutable 40-character SHA')
    actual = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', commit + '^{commit}'], text=True).strip()
    if actual != commit:
        raise ValueError('resolved commit differs')
    if destination.exists():
        raise ValueError('destination must not exist (will not replace user files)')
    archive = subprocess.check_output(['git', '-C', str(repo), 'archive', '--format=tar', commit])
    destination.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        members = [m for m in tar.getmembers() if Path(m.name).parts[0] not in OMITTED]
        if any(Path(m.name).is_absolute() or '..' in Path(m.name).parts or m.issym() or m.islnk() for m in members):
            raise ValueError('unsafe archive member')
        # Reject links before extraction; works on Python versions predating filter=.
        tar.extractall(destination, members=members)


def container(source, image, extra, command):
    return ['docker','run','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
            '--tmpfs','/tmp:rw,nosuid,size=1g','--tmpfs','/app/data:rw,nosuid,size=64m','--workdir','/app','--env','PYTHONDONTWRITEBYTECODE=1',
            '--env','PYTHONPATH=/app','--env','HOME=/tmp','--env','FIESTABOARD_DATA_DIR=/tmp/contract-data',
            '--env','FIESTABOARD_OUTPUT_SEED_DIR=/opt/fiestaboard/seed/outputs',
            '--mount',f'type=bind,src={source},dst=/app,readonly',
            '--mount',f'type=bind,src={ROOT / "scripts"},dst=/contract-tools,readonly',
            *extra,'--entrypoint','python',image,*command]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare','export','test','build'])
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--commit',required=True)
    parser.add_argument('--destination',type=Path)
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--image',default=IMAGE,help='content ID sha256:... from a bootstrap or rebuilt image')
    parser.add_argument('--bootstrap',action='store_true',help='optimize build using verified local dependency substrate')
    parser.add_argument('--tag',default='fiestaboard-ios-contract:v10')
    parser.add_argument('--upstream',action='store_true',help='also run selected upstream auth cases (no bypass fixtures)')
    parser.add_argument('--current-controls',action='store_true',help='run only current-source board-control replay tests')
    args = parser.parse_args()
    if args.current_controls and (args.action != 'test' or args.upstream):
        parser.error('--current-controls requires test without --upstream')
    if args.action == 'prepare':
        if not args.destination:
            parser.error('prepare requires --destination')
        prepare(args.repo.resolve(),args.commit,args.destination.resolve())
        return
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', args.image):
        parser.error('--image must be an immutable content ID')
    with tempfile.TemporaryDirectory(prefix='fiestaboard-contract-') as tmp:
        source = Path(tmp)/'source'
        prepare(args.repo.resolve(),args.commit,source)
        (source/'data').mkdir(exist_ok=True)  # Empty mountpoint for image-declared ephemeral volume.
        if args.action == 'build':
            if args.bootstrap:
                actual = subprocess.check_output(['docker','image','inspect','fb-2354-test:latest','--format','{{.Id}}'],text=True).strip()
                if actual != BOOTSTRAP_IMAGE:
                    raise ValueError('bootstrap tag no longer matches pinned content ID')
            context = Path(tmp)/'build'
            context.mkdir()
            shutil.move(str(source),str(context/'backend'))
            filename = 'Dockerfile.bootstrap' if args.bootstrap else 'Dockerfile'
            shutil.copy(ROOT/'Tests/Integration'/filename,context/'Dockerfile')
            shutil.copy(ROOT/'Tests/Integration/dependencies.lock',context/'dependencies.lock')
            subprocess.run(['docker','build','--tag',args.tag,str(context)],check=True,env={**os.environ,'DOCKER_BUILDKIT':'0'})
            print(subprocess.check_output(['docker','image','inspect',args.tag,'--format','{{.Id}}'],text=True).strip())
        elif args.action == 'export':
            output = args.root.resolve()/'Contracts'
            output.mkdir(parents=True,exist_ok=True)
            extra = ['--mount',f'type=bind,src={output},dst=/contract-output']
            fixtures = args.root.resolve()/'Fixtures/contracts'
            if fixtures.is_dir():
                extra.extend(['--mount',f'type=bind,src={fixtures},dst=/contract-fixtures,readonly'])
            subprocess.run(container(source,args.image,extra,['/contract-tools/export-openapi.py',args.commit,args.image]),check=True)
        else:
            extra = ['--mount',f'type=bind,src={args.root.resolve() / "Tests/Integration"},dst=/contract-tests,readonly',
                     '--mount',f'type=bind,src={args.root.resolve() / "Fixtures/contracts"},dst=/contract-fixtures,readonly']
            command = ['-m','pytest','-c','/dev/null','-p','no:cacheprovider','--tb=short','-q','/contract-tests']
            if args.current_controls:
                command[-1] = '/contract-tests/test_current_board_controls.py'
            if args.upstream:
                # The upstream conftest auth bypass is not loaded into our proof.
                command = ['-m','pytest','-p','no:cacheprovider','--tb=short','-q',
                           'tests/test_auth_routes.py','tests/test_auth_device_routes.py','tests/test_auth_tv_permissions.py']
            subprocess.run(container(source,args.image,extra,command),check=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as exc:
        raise SystemExit(str(exc))
