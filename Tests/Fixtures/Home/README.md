# I7 Home contract evidence

The 13 response files at this directory's root are unchanged HTTP bodies recorded
inside `cx-iosnext5-i7-contract`, from immutable hub commit
`f47da6e4e764fc2826f396210f013e45dc1a7fd8`. `SOURCE.json` binds their hashes,
request manifest and seeded scenario IDs. A synthetic mobile bearer made the
requests and was revoked; it never appears in these response files.

`HostSupplement/` and `HostV11/` contain separate supplemental recordings because
Docker's VM became read-only after the shared host disk filled. These are actual
FastAPI boundary responses from immutable runtime source archives in an isolated
host uv environment. They are **not Docker/C5 proof**. Their SOURCE files identify
respectively the old pin and v11 `e8306aca0df3ee26a693afe57760d83b1ec3c772`, and
`environment.txt` records installed versions. The current supplemental sets contain 19 responses each, including real 480-minute acceptance and 481-minute rejection. `requests-host.json` includes actual
mobile-authenticated page selection and actual 401 refusals for selection/cancel.
The original Docker recordings and manifest were preserved.

Run `bash scripts/contract-home-live.sh check` to exercise the Docker workflow
when Docker can create containers again. The supplemental driver is
`scripts/contract-home-host.sh`; it expects the isolated environment documented by
the recorded environment file under
`~/Library/Developer/FiestaBoard/ios/cx-iosnext5-i7-hub-venv`. Neither driver
publishes, uses physical display output or records a credential. Tooling validates
byte hashes, exact paths/statuses, manifest binding and distinct provenance.

The native UI `board-i7-*` namespace is explicitly synthetic. It uses recorded
H1/H2 field shapes without changing the retained legacy migration oracle. Its
frames and dates are UI controls, not additional live-hub response recordings.

The hub's cancel and restore interfaces have no conditional-create/restore
operation. The client deliberately supplies no race-prone Undo. Completing the
I7 Undo criterion needs an atomic restore receipt or create-if-no-current-override
contract. A GET followed by POST can overwrite an intervening replacement.
