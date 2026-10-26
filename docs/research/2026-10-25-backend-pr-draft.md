# Backend draft PR handoff

Repository: `Fiestaboard/FiestaBoard`

Head: `codex/ios-api-access` (`1514c274a`), based on `main` (`3a1d6e8b6`).

[Review the pushed branch](https://github.com/Fiestaboard/FiestaBoard/compare/main...codex/ios-api-access)

Title: **Add page revision preconditions for native editing**

Status: branch pushed; draft PR not created. The GitHub connector returned `MCP tool call requires approval, but approval policy is never`. Do not create a second PR if one has since been opened for this branch; use one ongoing draft PR for the native API work. No merge or production deployment was performed.

## Prepared PR description

Two editors can currently load the same page and silently overwrite each other. This first milestone adds optional page revision preconditions through the existing APIs and makes the web editor retain the revision it originally loaded.

- Stored pages expose opaque runtime revisions. Conditional update/delete returns HTTP 412 when another writer changed the page.
- Legacy unconditional writes remain compatible and invalidate outstanding revisions.
- Restart, delete/recreate and backup restore invalidate old revisions. Restore retains the live owner so cached services cannot resurrect old content.
- Deletion follows the established cross-store lock order, including concurrent panel resizing.
- Web button/imperative saves and deletes carry the draft revision; background refetches do not replace it.

This is the single ongoing draft PR for native iOS API needs. Native remote publishing is still disabled. Collections/schedules, participating AI writers, and lossless document compatibility remain follow-ups documented in `docs/development/ios-api-access.md`. Existing internal APIs cover most remaining access needs; no separate mobile API namespace is added.

Validation:
- 523 focused Python tests pass, including 15 revision tests, storage kernel, resize, restore, pages, v1, operations and conventions.
- Full web suite: 259 files passed; 3,060 tests passed and 7 skipped, using exact lockfile dependencies, the corrected fixture mount and two workers.
- TypeScript, changed-file Ruff/Prettier and diff checks pass.
- New tests were observed failing before the implementation. Both review regressions were rechecked against the old implementation: lock timeout and schema-refusal failure, then passed with the fixes.
- Astra approved the bounded implementation after both findings were fixed and independently ran 63 revision/kernel tests.

Tests ran in disposable Docker containers without test network access or production hardware. The full Python suite was attempted but OOMed at 54% (exit 137); there is no full-Python-suite pass claim. The initial web run's fixture error and three failures are documented; the corrected complete rerun passes.

