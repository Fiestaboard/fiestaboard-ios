# Contract foundation verification

This implements the bounded 0A/0B foundation from the approved plan. Milestone 0 as a whole remains open, and there is no Swift application yet. The implementation uses GPT-6.1 Sol agents with independent GPT-6 Astra review.

## Delivered

- 81 grouped web workflows mapped to 198 required API operations: 22 public and 176 internal. Thirteen workflow rows have an explicit native equivalent without a server operation.
- Normalized public and internal OpenAPI snapshots from clean FiestaBoard 10.0.0 source, commit `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a`. The public schema contains 36 operations; the internal schema contains 278. The inventory selects the subset needed by the web workflows.
- Source provenance, schema hashes, dependency versions, output-seed validation, contract integrity checks, and a separate release-readiness gate.
- Docker-only backend execution from a clean Git archive, with read-only source, temporary data and network-disabled test/export containers. The active dirty web checkout and live board service were not modified.

## Verification performed

| Check | Result |
|---|---|
| `python3 -m unittest discover -s Tests/Contracts -v` | 25 passed |
| Isolated HTTP authentication suite | 10 passed |
| Selected upstream authentication suites | 67 passed |
| Default contract checker | Passed; explicitly reports NOT release ready |
| `--release-ready` | Expected exit 1: unresolved coverage, acceptance and support gates |
| Clean Docker build without the local bootstrap image | Passed |
| Public/internal schema export from the clean image | Byte-identical to committed schemas |

The clean build produced image `sha256:1f007c0360343d3d5b5263f04a370564dc36754fd61420b48a6ef7545981ff9d`. Both authentication suites and the independent export were run against that image. The committed snapshot records the separately validated bootstrap-built image; its provenance was not overwritten by this comparison. Build instructions explain how to reproduce and supply a new immutable image ID. Base-image tags and OS packages are not claimed to be byte-reproducible.

Both backend suites retain one upstream `FastAPI(root_path=...)` deprecation warning. These 77 authentication cases are not the whole backend test suite.

## Review corrections

Astra reviewed the initial foundation at `22862a7` and requested four corrections:

1. Classify the single-use OAuth callback as mutating and explicitly replayed only.
2. Require supported contracts for public operations as well as internal operations before release readiness can pass. Two public-operation regression cases failed before the fix and pass afterward; the positive fully evidenced fixture still passes.
3. Classify active-schedule reads that persist expired-override cleanup as configuration mutations.
4. Classify current-display reads that force provider rendering/cache updates according to their page-dependent behavior.

The focused correction also identified persisted expiry cleanup in session listing. All five entries/checks were corrected in `e891cea`, `0840c1a`, and `9447e7d`. The dependency audit separately corrected Pillow to 13.0.0 in `4d50a09`, satisfying the pinned source's requirement.

Astra's scoped rereview approved bounded tasks 0A/0B at `9447e7d` with no remaining material findings. It independently reproduced rejection of blocked/candidate public contracts and acceptance of the fully evidenced supported fixture. This approval does not extend to the remaining milestone, native app or release readiness.

## Remaining work

The candidate server is not an accepted app/server pairing. Operation-specific runtime fixtures, all-writer revision/precondition support, native OAuth lifecycle proof, actual Home Assistant authentication/topology proof, Swift implementation and physical-device validation remain open. All parity rows remain planned and operations remain candidates with schema-only verification; the targeted authentication evidence does not promote unrelated operations.

The next work is the remaining protocol foundation and native transport/app shell, following the dependency gates in the implementation plan. No production hardware writes, provider OAuth completion, App Store submission, or physical-device validation were performed in this slice.
