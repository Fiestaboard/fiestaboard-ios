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

The original pinned hubs have no atomic restore. `HostUndo/` separately records
34 responses from unmerged backend commit `6be367f4a76891d7b11a114a81a7d79f1b50534a`;
`requests-undo.json` binds the additive capability, opt-in cancel receipt and
atomic restore. It includes timed and indefinite restoration, unchanged original
start/expiry, and stale/used/wrong-display/auth/body refusals. Synthetic receipt
tokens are expired and the issuing mobile session was revoked before exit.
This supplemental host recording does not imply backend merge or deployment.
Old hubs remain unsupported for Undo. The client never reconstructs a cancelled
override or performs a GET followed by a content POST to emulate restoration.

`DockerUndo/` adds the same 34 actual HTTP cases from the exact reviewed backend
`6be367f4a76891d7b11a114a81a7d79f1b50534a`, after the local daemon recovered.
It ran in a new `cx-` image/container, read-only with networking disabled. SOURCE
records the image ID, immutable official Python base digest, actual Python
version and dependency-lock hash. Its environment file preserves installed
versions. This proves these authenticated API cases in Docker; it does not
claim physical display output, all fault cases, or whole-Home visual parity.
The original Docker13 and all host supplements remain unchanged.

The Docker driver now uses that pinned official base and the frozen minimal
runtime dependency lock instead of requiring the unavailable `fb21:local` image.
Set `CX_HOME_MANIFEST=Tests/Fixtures/Home/requests-undo.json` and
`CX_HOME_OUT=Tests/Fixtures/Home/DockerUndo` with the reviewed source pin to
record the additive contract. It uses a temporary empty Docker credential
configuration and preserves the selected daemon endpoint; it never logs in or
alters other Docker resources.
