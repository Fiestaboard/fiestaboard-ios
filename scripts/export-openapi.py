#!/usr/bin/env python3
"""Container-only schema export. Import routes without entering ASGI lifespan."""
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys

OUT = Path('/contract-output')


def write(path, value):
    data = (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + '\n').encode()
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def collect_artifacts(expected_source_commit, out, fixture_root):
    # Existing companions must match; stale evidence cannot disappear from coverage.
    # Historical evidence stays committed separately and is never relabeled.
    artifacts = []
    for relative, local in [
        ('Contracts/current-source-ledger.json', out/'current-source-ledger.json'),
        ('Contracts/current-capabilities.json', out/'current-capabilities.json'),
        ('Fixtures/contracts/current/bootstrap-control.json', fixture_root/'current/bootstrap-control.json'),
    ]:
        if local.is_file():
            data = local.read_bytes()
            artifact = json.loads(data)
            source_commit = artifact.get('source_commit', artifact.get('source', {}).get('commit'))
            if source_commit != expected_source_commit:
                raise ValueError('companion source commit mismatch: ' + relative)
            artifacts.append({'path':relative,'source_commit':source_commit,'sha256':hashlib.sha256(data).hexdigest()})
    return artifacts


def main():
    artifacts = collect_artifacts(sys.argv[1], OUT, Path('/contract-fixtures'))
    from src.api_server import app
    from src.v1.visibility import build_internal_openapi

    metadata = {}
    for surface, name, schema in [('public','public-openapi.json',app.openapi()), ('internal','mobile-internal-openapi.json',build_internal_openapi(app))]:
        digest = write(OUT/name,schema)
        count = sum(method in {'get','put','post','delete','options','head','patch','trace'} for methods in schema['paths'].values() for method in methods)
        metadata[surface] = {'path':'Contracts/'+name,'sha256':digest,'operation_count':count}
    source_evidence = {}
    for path in sorted(Path('/app').rglob('*')):
        if path.is_file():
            data = path.read_bytes()
            source_evidence[str(path.relative_to('/app'))] = {'sha256':hashlib.sha256(data).hexdigest(),'lines':len(data.splitlines()),'source_commit':sys.argv[1]}
    seed = Path('/opt/fiestaboard/seed/outputs/outputs.lock.json')
    lock = seed.read_bytes()
    from src.outputs.seed import load_lock, tree_digest
    entries = load_lock(seed)
    for output_id, entry in entries.items():
        if tree_digest(seed.parent/output_id) != entry.tree_sha256:
            raise RuntimeError('seed tree mismatch: ' + output_id)
    source_lock = Path('/app/outputs.lock.json').read_bytes()
    seed_matches_source = json.loads(lock) == json.loads(source_lock)
    if not seed_matches_source:
        raise RuntimeError('image seed does not match pinned source lock')
    baseline = {}
    original = OUT/'archive/10.0.0/snapshot.json'
    if original.is_file():
        original_source = json.loads(original.read_text())['source']
        baseline = {'path':'Contracts/archive/10.0.0/snapshot.json','source_commit':original_source['commit'],'version':original_source['version']}
    write(OUT/'snapshot.json', {'schema_version':1,'source':{'commit':sys.argv[1],'version':app.version},
        'generator':{'image':sys.argv[2],'python':platform.python_version(),'architecture':platform.machine(),'implementation':platform.python_implementation(),
        'dependencies':sorted(d.metadata['Name']+'=='+d.version for d in importlib.metadata.distributions()),
        'output_seed':{'lock_sha256':hashlib.sha256(lock).hexdigest(),'outputs':json.loads(lock)['outputs'],'matches_source_lock':seed_matches_source,'source_lock_sha256':hashlib.sha256(source_lock).hexdigest(),'source_outputs':json.loads(source_lock)['outputs']},
        'source_preparation':'git archive; omit root .env, data, config.json, auth.json; no worktree files',
        'lifespan':'not entered; no startup hardware workers'},
        'baseline':baseline,'artifacts':artifacts,'schemas':metadata,'source_evidence':source_evidence,
        'source_manifest_sha256':hashlib.sha256(json.dumps(source_evidence,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
        'blockers':['HA upstream authentication untested','Provider-native OAuth completion pending','Cross-writer conditional revision/native acceptance pending','Full operation fixtures pending','Native physical-device verification pending','Proxy and ingress topology verification pending']})
    print('Exported normalized schemas: ' + ', '.join(f'{key}={value["operation_count"]}' for key,value in metadata.items()))


if __name__ == '__main__':
    main()
