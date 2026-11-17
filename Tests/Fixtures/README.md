# I5 mobile HTTP recordings

`SOURCE.json` pins FiestaBoard #2470's immutable `f47da6e4e764fc2826f396210f013e45dc1a7fd8` baseline (including H10 #2432 `47cdc8d7f9d26c76cf046d8dfdf029c9b596830e`). Both PR heads were re-read with `gh pr view --json headRefOid,state` before recording. These are the approved I5 baseline contracts; this does not assert that the baseline equals today's later `v11` release head.

Run `scripts/contract-live.sh --record` to build that source archive in an isolated Docker image and record real FastAPI HTTP responses, unchanged. `scripts/contract-live.sh` verifies the live route statuses against the recorded contract. `python3 -m unittest Tests/Tooling/test_mobile_fixture_integrity.py` checks every SHA.

The recorder creates only the synthetic `contract_admin` account in temporary container storage. The mobile token in `device-login.json` was revoked before the container exited; no real account or credential is included. The expired response comes from advancing only that isolated session registry's injected clock, then making an actual protected request. Lockout is recorded after actual failed attempts. Response bytes are not patched or normalized.

`SessionPersistenceTests` and `MobileFixture` use separate synthetic protocol controls to test races, invalid headers and malformed/foreign credentials. They are not passed off as these recorded contracts. Legacy editor fixture shapes remain compatibility tests until the per-feature v11 route contracts replace them.
