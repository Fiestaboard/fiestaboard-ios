# Historical compatibility oracle — test-only archive

This directory preserves the prior 10.0/10.1.x source-bound contracts, immutable fixture bytes and their independent utility/editor compatibility controls. They are retired as live mobile wire authority in I5. App code, package source, Xcode resources and the current native UI fixture cannot import or launch this archive; a repository guard checks that boundary.

Current phone auth wire contracts live in `Tests/Fixtures/SOURCE.json` and are generated from actual requests to the immutable hub by `scripts/contract-live.sh`. Never hand-edit recordings or use this historical corpus to claim current hub compatibility.

The archived Python UI router is an oracle used only by historical tests. It is not the UI-test server and is never launched by `scripts/test.sh` or CI native jobs. Its synthetic editor fixtures remain clearly separated from actual hub recordings. The new native Swift fixture tests preserve behavior independently.

Run retained historical controls explicitly:

```sh
python3 -m unittest discover -s Tests/LegacyContracts/Tests/Contracts -v
python3 -m unittest discover -s Tests/LegacyContracts/Tests/Tooling -v
python3 Tests/LegacyContracts/scripts/check-contracts.py
```

The original internal directory layout and source pins are preserved so the oracles retain their independent meaning; archived `--release-ready` refusal remains historical evidence, not a current release gate. Legacy backend imports still run in Docker only if explicitly invoked from this archive. No archived tool is used to bootstrap the app or grant new v11 feature capabilities.
