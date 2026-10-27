# Page saving and preview implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development. This continues the approved full-product plan and user instruction to keep implementing with parallel Sol agents and Astra review.

**Goal:** Make the native editor validate/preview templates and conditionally save supported edits, with a usable demo and preserved conflicts.

**Architecture:** Add a narrow `edit_protocol: "page-revision-v1"` runtime capability to the existing backend Page model. Native page writes require that exact protocol, a nonempty original revision, and explicit session opt-in. Board writes retain their separate exact-version gate. Save only changed `name` and fixed-slot `template` fields. Preview calls use existing evaluation endpoints, never `/render/live`.

**Tech stack:** Swift 6/SwiftUI/Combine/Foundation, pure document model, host-testable editor state, existing FastAPI/Pydantic backend.

**Spec:** Existing `../specs/2026-10-25-fiestaboard-ios-design.md`, bounded by this milestone and `TASKS.md`.

## Global constraints

- Full web parity remains the first-release goal; this wave implements supported page edits and template preview, not rich/canvas/collection editors.
- Sol 6.1 implements; Astra reviews. User authorized parallel owned tracks and one backend branch/draft PR.
- Preserve user signing edits on main and the original dirty FiestaBoard checkout. Work only in the existing isolated worktrees.
- No production/hardware mutations in automated tests. Backend tests/imports use disposable Docker.
- Keep exact Unicode/numeric/unknown document content, original revision, explicit local saves, and immutable deployment/page/board/session context.
- No automatic replay of saves, no refreshing a revision then silently reapplying an old edit.
- Existing Claude CLI attempts failed with expired authentication. No unchanged retry or credential modifications.
- The user explicitly requested `gh` for GitHub operations after the connector blocked creation. Draft PR [#2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373) now exists; update this single PR and do not merge or deploy without the applicable authorization.

## Review focus

1. Save conflict, timeout or late response must preserve local content; acknowledged storage is distinct from board delivery.
2. Reconnection to the same URL must invalidate old editor contexts; a different board or draft revision invalidates preview results.
3. A baseline revision belongs to loaded/recovered content; background reads do not silently advance it.
4. Unknown edit protocols and old servers remain unable to receive page PUT from native; page capability never broadens board control access.
5. Preview keeps geometry/metadata/canvas input fidelity and surfaces unsupported rich output rather than drawing a false flap approximation.

## Task 1 — Backend page protocol advertisement

Files: existing backend `src/pages/models.py`, `src/pages/storage.py`, `tests/test_page_revisions.py`, `docs/development/ios-api-access.md` on `codex/ios-api-access`.

- [ ] Test exact `edit_protocol` advertisement on stored-page reads and save replies, absence from disk, user input cannot override it, existing revisions/conflicts unchanged.
- [ ] Add runtime-only literal `page-revision-v1`, excluding it alongside revision from persistence; document narrow known-field partial saves and the absence of direct hardware delivery by page PUT.
- [ ] Run focused Docker suites and provide contract fixtures for native tests. Commit, Astra review, then push the same branch. No second PR.

## Task 2 — Native service and connection-scoped editor actions

Files: `Packages/FiestaBoardKit/**`, `Packages/FiestaBoardAppState/**` exclusively.

- [ ] Introduce typed changed-name/template save request, raw page receipt, template validation/render results and exact protocol/opt-in gating.
- [ ] Use existing cookie/redirect/no-replay transport; map HTTP412 to a specific page conflict. Preserve raw response data.
- [ ] Add immutable session generation to loaded editor context and expose save/validate/preview operations through BoardStore. Guard stale sessions, duplicate writes, unknown outcomes and 401 invalidation.
- [ ] Demo pages support persistent in-memory saves and deterministic conflict/unknown outcomes; label simulated validation/rendering accurately.
- [ ] Tests cover endpoint/body scope, old/protocol/version mismatch, explicit opt-in, Unicode payloads, conflicts/unknown outcomes, same-URL reconnection and stale previews. Commit and report stable interfaces early.

## Task 3 — Editor workflow and integration

Files: `Packages/FiestaBoardDocuments/**`, new `Packages/FiestaBoardEditorState/**`, `App/Features/Editor/**`, `App/Features/Library/**` exclusively. Root owns AppRoot/project/docs/UI tests integration.

- [ ] Extract or extend editor coordination into a host-testable state package; keep document values independent of networking.
- [ ] Add explicit server-save confirmation, captured local snapshot before a save, conflict and unknown-result states, explicit fetch/reload that preserves local work until chosen, and separate local-dirty versus server-dirty indicators.
- [ ] Freeze editing during confirmed save or correctly retain concurrent edits; undo must never resurrect an obsolete server revision after a successful save/reload.
- [ ] Validate and preview the current document on an explicit chosen board. Tag requests with document/board identity; ignore stale results. Show rendered lines, syntax/charset/canvas warnings and unsupported visual output honestly.
- [ ] Preserve local draft recovery, Unicode fidelity, close protection and resize continuity. Add meaningful host tests for asynchronous editor races and conflict recovery.
- [ ] Integrate and build unsigned Simulator/device and UI test target. Astra reviews combined native wave; fixes return to original owners. Land main preserving signing, update TASKS and evidence.
