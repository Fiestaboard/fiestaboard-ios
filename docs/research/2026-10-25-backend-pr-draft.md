# Backend draft PR handoff

Repository: `Fiestaboard/FiestaBoard`

Head: `codex/ios-api-access` (`dadbc191e`), based on `main` (`3a1d6e8b6`).

[Review the pushed branch](https://github.com/Fiestaboard/FiestaBoard/compare/main...codex/ios-api-access)

Title: **Add page revision preconditions for native editing**

Status: branch pushed; draft PR not created. The GitHub connector returned `MCP tool call requires approval, but approval policy is never`. Do not create a second PR if one has since been opened for this branch; use one ongoing draft PR for the native API work. No merge or production deployment was performed.

## Prepared PR description

Two editors can currently load the same page and silently overwrite each other. This branch adds optional page revision preconditions through the existing APIs, makes the web editor retain its original revision, and advertises the exact runtime page-edit protocol for native clients.

- Stored pages advertise read-only `edit_protocol: "page-revision-v1"` and expose opaque runtime revisions. Both runtime fields are excluded from disk. Conditional update/delete returns HTTP 412 when another writer changed the page.
- Legacy unconditional writes remain compatible and invalidate outstanding revisions.
- Restart, delete/recreate and backup restore invalidate old revisions. Restore retains the live owner so cached services cannot resurrect old content.
- Deletion follows the established cross-store lock order, including concurrent panel resizing.
- Web button/imperative saves and deletes carry the draft revision; background refetches do not replace it.

This is the single ongoing draft PR for native iOS API needs. Native page saving requires this advertised protocol, the loaded revision and explicit session opt-in; unpatched servers remain save-disabled. Collections/schedules, participating AI writers, and lossless document compatibility remain follow-ups documented in `docs/development/ios-api-access.md`. Existing internal APIs cover most remaining access needs; no separate mobile API namespace is added.

Validation:
- 523 focused Python tests pass, including 15 revision tests, storage kernel, resize, restore, pages, v1, operations and conventions.
- Full web suite: 259 files passed; 3,060 tests passed and 7 skipped, using exact lockfile dependencies, the corrected fixture mount and two workers.
- TypeScript, changed-file Ruff/Prettier and diff checks pass.
- New tests were observed failing before the implementation. Both review regressions were rechecked against the old implementation: lock timeout and schema-refusal failure, then passed with the fixes.
- Astra approved the bounded implementation after both findings were fixed and independently ran 63 revision/kernel tests.

Tests ran in disposable Docker containers without test network access or production hardware. The full Python suite was attempted but OOMed at 54% (exit 137); there is no full-Python-suite pass claim. The initial web run's fixture error and three failures are documented; the corrected complete rerun passes.


## Subsequent protocol verification

The additive protocol commit `dadbc191e` passed Astra specification/quality review with no findings. Latest backend checks: 522 focused/contract tests, including all 22 revision tests, schema honesty and response-shape goldens. Astra independently ran 75 tests. The earlier full web result above predates this runtime metadata addition; no web code changed in the addition. The full Python OOM limit still applies. The native draft independently consumes the protocol; this does not deploy the backend branch to any install.
