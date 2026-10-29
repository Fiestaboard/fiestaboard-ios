#!/usr/bin/env python3
"""Explicit local stdlib utility. Checks committed artifacts; never imports backend."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

METHODS = {'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'}
ACCEPTANCE = {'auth', 'oauth', 'conditional_writes', 'operation_fixtures', 'native_physical', 'topology'}


def check(root, release_ready=False):
    errors = []
    def require(condition, message):
        if not condition:
            errors.append(message)
    def read(relative):
        try:
            value = json.loads((root / relative).read_text())
            if not isinstance(value, dict):
                raise ValueError('must be an object')
            return value
        except (OSError, ValueError) as exc:
            errors.append(f'{relative}: {exc}')
            return {}
    docs = {name: read('Contracts/' + name + '.json') for name in ('snapshot', 'parity', 'operations', 'supported-servers')}
    if errors:
        return errors
    snap, parity, inventory, support = (docs[key] for key in ('snapshot', 'parity', 'operations', 'supported-servers'))
    for name, doc in docs.items():
        require(doc.get('schema_version') == 1, f'{name}: schema_version must be 1')
    source = snap.get('source', {})
    sha, version = source.get('commit'), source.get('version')
    require(isinstance(sha, str) and re.fullmatch('[0-9a-f]{40}', sha), 'invalid pinned source commit')
    require(isinstance(version, str) and bool(version), 'missing source version')
    for name in ('parity', 'operations', 'supported-servers'):
        require(docs[name].get('source_commit') == sha, f'{name}: source commit mismatch')
    generator = snap.get('generator', {})
    require(bool(re.fullmatch(r'sha256:[0-9a-f]{64}', str(generator.get('image', '')))), 'generator image must be content pinned')
    require(bool(generator.get('python')) and bool(generator.get('dependencies')), 'missing generator dependency environment')
    require(bool(generator.get('output_seed', {}).get('lock_sha256')), 'missing output seed metadata')
    def valid_evidence(item):
        if not isinstance(item,dict) or item.get('source_commit') != sha or not isinstance(item.get('path'),str):
            return False
        relative = Path(item['path'])
        target = (root/relative).resolve()
        if relative.is_absolute() or '..' in relative.parts or not target.is_relative_to(root.resolve()) or not target.is_file():
            return False
        return item.get('sha256') == hashlib.sha256(target.read_bytes()).hexdigest()
    evidence = snap.get('source_evidence', {})
    require(isinstance(evidence, dict) and bool(evidence), 'missing source evidence manifest')
    manifest_digest = hashlib.sha256(json.dumps(evidence, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    require(snap.get('source_manifest_sha256') == manifest_digest, 'source manifest hash mismatch')
    def sources(items, label):
        require(isinstance(items, list) and bool(items), f'{label}: source evidence required')
        if not isinstance(items, list):
            return
        for item in items:
            if not isinstance(item, dict):
                errors.append(f'{label}: invalid evidence object')
                continue
            path, line = item.get('path'), item.get('line')
            record = evidence.get(path, {}) if isinstance(path, str) else {}
            require(isinstance(path, str) and not path.startswith('/') and '..' not in Path(path).parts, f'{label}: invalid source path')
            require(bool(re.fullmatch('[0-9a-f]{64}', str(record.get('sha256', '')))), f'{label}: source path not attributed: {path}')
            require(record.get('source_commit') == sha, f'{label}: source evidence commit mismatch: {path}')
            require(item.get('source_commit') == sha, f'{label}: evidence reference source mismatch: {path}')
            require(item.get('sha256') == record.get('sha256'), f'{label}: evidence reference hash mismatch: {path}')
            require(type(line) is int and 1 <= line <= record.get('lines', 0), f'{label}: source line outside attributed file: {path}')
    artifact_docs = []
    artifacts = snap.get('artifacts', [])
    require(isinstance(artifacts, list), 'snapshot artifacts must be a list')
    registered_paths = {item.get('path') for item in artifacts if isinstance(item, dict) and isinstance(item.get('path'), str)} if isinstance(artifacts, list) else set()
    for relative in ('Contracts/current-source-ledger.json', 'Contracts/current-capabilities.json',
                     'Fixtures/contracts/current/bootstrap-control.json', 'Fixtures/contracts/current/board-control.json'):
        if (root / relative).exists():
            require(relative in registered_paths, f'{relative}: existing companion missing artifact registration')
    for item in artifacts if isinstance(artifacts, list) else []:
        require(valid_evidence(item), 'current artifact requires source-matching hashed evidence')
        if not valid_evidence(item):
            continue
        artifact = read(item['path'])
        artifact_docs.append(artifact)
        artifact_sha = artifact.get('source_commit', artifact.get('source', {}).get('commit'))
        require(artifact_sha == sha, f"{item['path']}: artifact source commit mismatch")
        def artifact_refs(node):
            if isinstance(node, dict):
                if 'path' in node and 'line' in node:
                    sources([node], item['path'])
                for child in node.values():
                    artifact_refs(child)
            elif isinstance(node, list):
                for child in node:
                    artifact_refs(child)
        artifact_refs(artifact)
        fixture_evidence = artifact.get('source_evidence', {})
        for path, digest in fixture_evidence.items():
            require(digest == evidence.get(path, {}).get('sha256'), f"{item['path']}: fixture source hash mismatch: {path}")
    schemas, operations_by_surface = {}, {}
    for surface, expected in [('public', 'Contracts/public-openapi.json'), ('internal', 'Contracts/mobile-internal-openapi.json')]:
        metadata = snap.get('schemas', {}).get(surface, {})
        require(metadata.get('path') == expected, f'{surface}: schema path mismatch')
        schema = read(expected)
        schemas[surface] = schema
        try:
            require(hashlib.sha256((root / expected).read_bytes()).hexdigest() == metadata.get('sha256'), f'{surface}: schema hash mismatch')
        except OSError:
            pass
        require(isinstance(schema.get('openapi'), str) and schema.get('openapi', '').startswith('3.'), f'{surface}: invalid OpenAPI document')
        require(schema.get('info', {}).get('version') == version, f'{surface}: version mismatch')
        found = {}
        for path, methods in schema.get('paths', {}).items():
            for method, operation in methods.items():
                if method not in METHODS:
                    continue
                oid = operation.get('operationId')
                require(isinstance(oid, str) and bool(oid) and oid not in found, f'{surface}: missing/duplicate schema operation ID {oid}')
                found[oid] = (method.upper(), path)
        operations_by_surface[surface] = found
        require(len(found) == metadata.get('operation_count'), f'{surface}: operation count mismatch')
        def walk(node):
            if isinstance(node, dict):
                ref = node.get('$ref')
                if isinstance(ref, str) and (ref.startswith('#') or not re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', ref)):
                    target = schema
                    try:
                        if not ref.startswith('#/'):
                            raise KeyError(ref)
                        for part in ref[2:].split('/'):
                            target = target[part.replace('~1', '/').replace('~0', '~')]
                    except (KeyError, TypeError, IndexError):
                        errors.append(f'{surface}: unresolved local $ref {ref}')
                for child in node.values():
                    walk(child)
            elif isinstance(node, list):
                for child in node:
                    walk(child)
        walk(schema)
    require('no compatibility promise' in schemas['internal'].get('info', {}).get('description', '').lower(), 'internal schema compatibility warning missing')
    rows, operations = parity.get('rows'), inventory.get('operations')
    require(isinstance(rows, list) and bool(rows), 'parity rows required')
    require(isinstance(operations, list) and bool(operations), 'operations required')
    if not isinstance(rows, list) or not isinstance(operations, list):
        return errors
    def unique(items, label):
        ids = [item.get('id') for item in items if isinstance(item, dict)]
        require(len(ids) == len(items) and all(isinstance(x, str) and x for x in ids) and len(ids) == len(set(ids)), f'{label}: duplicate/missing IDs')
        return set(ids)
    row_ids, op_ids = unique(rows, 'parity'), unique(operations, 'operations')
    for row in rows:
        require(all(key in row for key in ('id', 'area', 'workflow', 'web_sources', 'operation_ids', 'native_equivalent', 'verification', 'implementation_status')), f'parity {row.get("id")}: missing required fields')
        require(row.get('implementation_status') in {'planned', 'implemented', 'verified', 'blocked'}, f'parity {row.get("id")}: invalid implementation status')
        if row.get('implementation_status') == 'verified':
            proof = row.get('evidence', [])
            require(isinstance(proof, list) and bool(proof) and all(valid_evidence(e) for e in proof), f'parity {row.get("id")}: verified status requires current hashed evidence')
        sources(row.get('web_sources'), f'parity {row.get("id")}')
        mapped = row.get('operation_ids', [])
        require(isinstance(mapped, list) and len(mapped) == len(set(mapped)) and set(mapped) <= op_ids, f'parity {row.get("id")}: unknown/duplicate operation mapping')
        require(bool(mapped) or bool(row.get('native_equivalent')), f'parity {row.get("id")}: no-operation equivalence requires reason')
        for oid in mapped:
            op = next((o for o in operations if o.get('id') == oid), {})
            require(row.get('id') in op.get('parity_ids', []), f'parity {row.get("id")}: operation mapping is not reciprocal')
    for op in operations:
        label = f'operation {op.get("id")}'
        require(all(key in op for key in ('id','method','path','surface','auth','scope','side_effects','replay','web_sources','parity_ids','contract_status','verification_status','notes')), f'{label}: missing required fields')
        require(op.get('scope') in {'server','board','resource','public'}, f'{label}: invalid scope')
        require(op.get('side_effects') in {'none','configuration','hardware','external','mixed'}, f'{label}: invalid side effects')
        require(op.get('replay') in {'safe_read','explicit_only'}, f'{label}: invalid replay policy')
        require(op.get('contract_status') in {'candidate','supported','blocked'}, f'{label}: invalid contract status')
        require(op.get('verification_status') in {'schema_only','runtime_verified','untested','blocked'}, f'{label}: invalid verification status')
        require(isinstance(op.get('auth'), list) and bool(op.get('auth')) and all(isinstance(x,str) and x for x in op.get('auth', [])), f'{label}: auth description required')
        if op.get('contract_status') == 'supported' or op.get('verification_status') == 'runtime_verified':
            proof = op.get('evidence', [])
            require(isinstance(proof, list) and bool(proof) and all(valid_evidence(e) for e in proof), f'{label}: supported/runtime status requires current hashed evidence')
        sources(op.get('web_sources'), label)
        sources(op.get('backend_sources'), label + ' backend')
        mapped = op.get('parity_ids', [])
        require(isinstance(mapped, list) and bool(mapped) and len(mapped) == len(set(mapped)) and set(mapped) <= row_ids, f'{label}: missing/unknown/duplicate parity mapping')
        found = operations_by_surface.get(op.get('surface'), {}).values()
        require((op.get('method'), op.get('path')) in found, f'{label}: schema method/path absent')
        for pid in mapped:
            row = next((r for r in rows if r.get('id') == pid), {})
            require(op.get('id') in row.get('operation_ids', []), f'{label}: parity mapping is not reciprocal')
    for artifact in artifact_docs:
        if artifact.get('kind') != 'current-capabilities':
            continue
        candidates = artifact.get('operations', [])
        require(isinstance(candidates, list), 'capability operations must be a list')
        if not isinstance(candidates, list):
            continue
        require(unique(candidates, 'capabilities') == op_ids, 'capability/inventory operation IDs differ')
        for candidate in candidates:
            op = next((o for o in operations if o.get('id') == candidate.get('id')), {})
            for key in ('method', 'path', 'surface', 'contract_status', 'verification_status', 'auth', 'scope', 'side_effects', 'replay'):
                require(candidate.get(key) == op.get(key), f"capability {candidate.get('id')}: inventory {key} mismatch")
            surface = candidate.get('surface')
            require(candidate.get('schema_sha256') == snap.get('schemas', {}).get(surface, {}).get('sha256'), f"capability {candidate.get('id')}: schema hash mismatch")
            selected = schemas.get(op.get('surface'), {}).get('paths', {}).get(op.get('path'), {}).get(str(op.get('method', '')).lower(), {})
            declarations = {
                'schema_operation_id': selected.get('operationId'),
                'request_body': selected.get('requestBody'),
                'parameters': selected.get('parameters', []),
                'responses': selected.get('responses', {}),
                'declared_response_statuses': sorted(selected.get('responses', {})),
            }
            for key, expected in declarations.items():
                require(candidate.get(key) == expected, f"capability {candidate.get('id')}: schema {key} mismatch")
    blockers = []
    for label, doc in [('snapshot',snap),('supported-servers',support)]:
        require(isinstance(doc.get('blockers'), list) and all(isinstance(x,str) and x for x in doc.get('blockers', [])), f'{label}: blockers list required')
        blockers.extend(doc.get('blockers', []))
    coverage_ready = all(r.get('implementation_status') == 'verified' for r in rows) and all(o.get('verification_status') == 'runtime_verified' and o.get('contract_status') == 'supported' for o in operations)
    releases = support.get('releases')
    require(isinstance(releases, list) and bool(releases), 'supported release declarations required')
    for release in releases or []:
        require(release.get('version') == version and release.get('source_commit') == sha, 'unsupported/invented release source')
        require(release.get('status') in {'candidate','supported','unsupported'}, 'invalid release status')
        require(isinstance(release.get('evidence'), list), 'release evidence list required')
        if release.get('status') == 'supported' or release_ready:
            acceptance = release.get('acceptance', {})
            require(not blockers and coverage_ready, 'supported/release-ready claim has blockers or untested coverage')
            require(all(acceptance.get(key) == 'passed' for key in ACCEPTANCE), 'release acceptance categories incomplete')
            evidence_items = release.get('evidence', [])
            require(bool(evidence_items) and all(valid_evidence(e) for e in evidence_items) and ACCEPTANCE <= {e.get('category') for e in evidence_items if isinstance(e,dict)}, 'release requires source-matching hashed evidence')
    if release_ready:
        require(any(r.get('status') == 'supported' for r in releases or []), 'no supported release declared')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--release-ready', action='store_true')
    args = parser.parse_args()
    try:
        errors = check(args.root, args.release_ready)
    except (TypeError, ValueError, KeyError, AttributeError) as exc:
        errors = [f'invalid contract structure: {exc}']
    for error in errors:
        print('ERROR: ' + error, file=sys.stderr)
    if errors:
        return 1
    print('Release readiness passed.' if args.release_ready else 'Contract integrity passed. NOT release ready; run --release-ready for the separate acceptance gate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
