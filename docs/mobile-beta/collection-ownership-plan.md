# Collection Draft Ownership Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for this bounded package. Continue the existing mobile-beta ledger and review gates.

**Goal:** Keep collection drafts owned by their verified connection across login, restart and recovery, while preserving original unassigned files for export.

**Architecture:** Extend the existing page connection-scope pattern with a small scoped collection service result and immutable collection draft identity. Preserve current collection model, per-editor checkpoint files and retirement fingerprints. Use the existing native recovery destination for original-file export; no sync framework.

**Tech Stack:** Existing Swift6, Foundation, SwiftUI, package XCTest and synthetic UI fixture.

**Spec:** requirements-design.md and the approved `.superpowers/sdd/mobile-beta/collection-scope-design-review.md`; current source findings in next-parity-contract-findings.md. The Astra design review is authoritative for detailed ownership/acceptance rules.

## Global Constraints

- Active repo is /Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031; frozen original remains untouched.
- No new software, runtime, security or sync changes; no production actions, physical-device install, publication or merge.
- Durable identity uses deployment + verified installation ID + connection UUID + optional collection ID. Never credentials, display names, usernames or URL alone.
- Changing live connection generation/document token/write epochs remain mandatory; durable scope does not replace them.
- Original revision survives drafts/recovery;412 and uncertain writes never automatically retry.
- Unassigned/malformed/future archives remain exportable original bytes; never bind them to a new login.
- Unknown-field typed baselines remain read-only; no collection protocol/contract expansion here.
- One product implementer at a time. Controller owns generated project changes, actual simulator runs and aggregate evidence.

## Review Focus

1. Same URL with a new login or installation must never offer another connection's draft, including nil-ID creation drafts.
2. A late collection/content response after reconnect must be rejected even if durable scope is unchanged.
3. Serialized retirement lineage must not retire unrelated/unassigned/newer archive bytes.
4. Unknown-field read-only baseline must not become writable after archive encoding/decoding.
5. Malformed/future/unassigned files must remain visible for exact original export from connected and disconnected recovery routes.

### Task1: Verified collection ownership from service through durable recovery

**Files:** Service.swift and service adapters in FiestaBoardKit; CollectionContext.swift and existing collection operations in BoardStore.swift; CollectionDraft.swift and CollectionEditorModel.swift in EditorState; CollectionsView.swift loader. Extend existing Kit connection/service, AppState CollectionStoreTests and EditorState CollectionEditorTests/Archive tests. Split new focused helper files only where justified; no general refactor.

**Interfaces:** Add `ScopedCollectionDocument` with `collection: PageCollection?` and `scope: VerifiedConnectionScope`; add `scopedCollectionDocument(id: String?) async throws -> ScopedCollectionDocument` to FiestaBoardService with refusing default. Add captured scope to CollectionEditingContext/Snapshot. Add `CollectionDraftIdentity` produced from verified scope plus optional collection ID; pass it to model/archive instead of deployment-only matching. Keep displayed deployment separate from ownership. Preserve external mutation signatures unless necessary to carry immutable identity.

- [ ] Add failing service/real ConnectionModel→transport→BoardStore tests for verified create/read scope, same-origin new login, remembered restore, changed installation and late responses.
- [ ] Add failing archive/model tests for exact UTF8 scope matching, nil-ID creation, saved original revision, unknown-outcome non-replay, unsupported baseline recovery, malformed scope and per-scope lineage retirement with concurrent/newer versions.
- [ ] Run affected tests and record meaningful failures.
- [ ] Implement atomic scope/content capture and checks around awaits, immutable context scope, versioned checkpoint identity, exact matching at load AND recovery, original identity on every preservation callback. Legacy archives remain untouched and excluded from active recovery. Recheck lineage eligibility before retirement. After successful creation, retire the original nil-ID checkpoint lineage before moving to the acknowledged collection ID within the same immutable verified scope. An uncertain creation keeps nil identity and remains non-replayable; add creation acknowledgement → further edit → restart/recovery under the assigned-ID regression.
- [ ] Run affected full Kit/AppState/EditorState suites with existing isolated /tmp scratch paths; require exit0 and zero failures. Update exact commands/counts in task report, commit owned code. Controller reviews before next task.

### Task2: Collection inventory/export in native recovery

**Files:** CollectionDraft.swift inventory API (or focused adjacent file), LocalPageEditorLoader.swift existing LocalDraftRecoveryView, relevant native UI fixture/tests. Reuse existing native ShareLink with original file URL.

**Interfaces:** `CollectionDraftRecoveryEntry` carries stable file identity, original fileURL and optional safely decoded checkpoint plus readable reason for unassigned/malformed/future state. `CollectionDraftArchive.recoveryInventory()` returns every local recovery file, including retired versions for export; no mutation or adoption capability is exposed here.

- [ ] Add failing byte-identity and inventory tests for scoped, legacy, malformed and unknown-future archive formats; prove inventory does not rewrite or retire them.
- [ ] Implement inventory and native Collections section alongside Pages in connected/disconnected recovery. Show useful collection name/ID and ownership status without exposing secrets. Export original bytes; never JSONEncoder reconstruction.
- [ ] Add actual native same-scope recovery plus unassigned collection inventory/export-route journeys. Retain fixture isolation and readable control labels; avoid enclosing AX identifiers and automatic sibling Form actions.
- [ ] Run affected unit/tooling checks; controller runs phone/tablet UI and captures evidence. Independent Astra review, aggregate verification, update parity traceability and known limits. Commit only after relevant checks pass.

The parent has already delegated design/execution to Astra review, so no new user approval pause applies. Do not start this product package while flexible visible-label round4 is still being implemented; requirements preparation may proceed independently.
