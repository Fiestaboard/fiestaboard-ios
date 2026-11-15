"""Offline additive fixture integrity and required scenario checks."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parent

def verify():
    manifest=json.loads((ROOT/'manifest.json').read_text())
    for name,digest in manifest['artifacts'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
    fixture=json.loads((ROOT/'page-management.json').read_text())
    assert fixture['source']==manifest['source']
    assert fixture['source_evidence']==manifest['source_evidence']
    assert len(fixture['cases'])==48
    ids=[c['id'] for c in fixture['cases']]
    assert len(ids)==len(set(ids))
    for cid in ['basic.create_led','basic.stale_delete','references.collection_in_use','references.disabled_schedule_in_use','references.default_in_use','last_flagship.delete_last','last_led.delete_last','multi_active.after_led']:
        assert cid in ids,cid
    assert not re.search(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}',json.dumps(fixture['cases']))
    print('Verified 48 records, artifact/source bindings and required scenarios')

if __name__=='__main__': verify()
