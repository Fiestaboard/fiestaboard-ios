# Native collections implementation plan

> **For agentic workers:** use superpowers:subagent-driven-development. This is execution of the approved full-parity project; user already authorized continued implementation and parallel Sol workers with Astra review.

**Goal:** Deliver a testable native collection list/editor with all three selection modes, conditional CRUD, durable draft recovery, and merged-server contract evidence.

**Architecture:** Extend existing Kit, AppState and EditorState boundaries; transport stays in Kit, session ownership in BoardStore, draft transitions in EditorState, SwiftUI in App/Features/Collections.

**Tech Stack:** Swift 6, SwiftUI iOS 26+, Foundation/Combine, existing Xcode/SwiftPM toolchain.

**Spec:** ../specs/2026-10-27-native-collections-design.md and the approved 2026-10-25-fiestaboard-ios-design.md.

## Global constraints

- Work in the existing isolated `.worktrees/foundation` on codex/ios-foundation. Preserve main's user signing edits; do not regenerate the main Xcode project.
- Sol 6.1 implements; Astra independently reviews. Exclusive file ownership, no nested agents or commits of another owner's files. Coordinate interfaces early and commit only owned files.
- Native UI, system Form/List/navigation/glass, Dynamic Type/accessibility and resizable iPhone/iPad layouts. No UIKit/web wrappers, new external dependencies, or production/device mutations.
- Pin source 79edd37d2 / version10.1.7; backend imports/tests only in Docker. Do not change backend code in this milestone.
- Existing board controls keep their separate exact-version gate. No automatic write retry, hidden fresh-token fetch, or claim that a storage save confirms display output.
- Unknown fields/modes must not silently turn into supported writable content. This milestone promises known collection-field parity, not arbitrary raw JSON losslessness.

## Review focus

1. Same-URL reconnect, logout, delayed GET/save/delete, or multiple editor snapshots cannot redirect/authorize stale work.
2. Original revisions survive dirty refresh and local recovery; conflict/unknown outcomes preserve drafts, with explicit comparison/adoption.
3. Uncertain creation must not duplicate a collection on retry; delete-in-use/refused/missing cases remain distinguishable.
4. Mode changes, null configs, ordered rules/pages, Unicode names and membership validation match the backend rather than silently normalizing user input.
5. New/edit forms remain usable with empty libraries, long labels, Dynamic Type and narrow/wide windows; demo never contacts network.

## Frozen interfaces

Kit owner defines public Codable/Sendable/Equatable types with public initializers:
- `PageCollection`: id, name, pageIDs, selectionMode:String, time:CollectionIntervalConfig, variable:CollectionVariableConfig?, random:CollectionIntervalConfig?, revision:String?, editProtocol:String?, createdAt:String?, updatedAt:String?. Unknown mode strings decode read-only.
- `CollectionSelectionMode`: time, variable, random.
- `CollectionIntervalConfig(intervalSeconds:Int)`; `CollectionRule(expression:String,pageID:String)`; `CollectionVariableConfig(rules:[CollectionRule],defaultPageID:String,pollSeconds:Int)`.
- `CollectionInput`: mutable name, pageIDs, selectionMode:CollectionSelectionMode, time, variable, random; Codable, validates names by Unicode scalars1...100, nonempty unique non-collection member IDs, interval5...86400, variable poll2...600 and rule/default membership. Explicit nil configs encode JSON null in writes.
- `CollectionWriteAccess(writesOptedIn:Bool,canCreate:Bool,isSimulated:Bool)`.
- Service methods: `collectionAccess() async -> CollectionWriteAccess`; `collections() async throws -> [PageCollection]`; `collection(id:String) async throws -> PageCollection`; `createCollection(_ input:CollectionInput) async throws -> PageCollection`; `updateCollection(id:String,input:CollectionInput,expectedRevision:String) async throws -> PageCollection`; `deleteCollection(id:String,expectedRevision:String) async throws`.
- Safe disabled default protocol implementations keep existing unrelated mocks source-compatible; Live/Demo implement the actual operations. Errors add collectionConflict, collectionWritesDisabled, collectionReadbackRequired, collectionInUse, staleCollectionContext. Existing rejected(status:404) can signal missing resources.

Root AppState interfaces, consumed by the UI owner:
- `CollectionEditingContext`: deployment, generation, documentToken, collectionID:String?, originalRevision:String? (immutable).
- `CollectionEditorSnapshot`: context, collection:PageCollection?, pages:[Page], canSave:Bool, isDemo:Bool.
- BoardStore published collections:[PageCollection], collectionsLoading:Bool, collectionMessage:String?.
- BoardStore `refreshCollections() -> Task<Void,Never>`; `beginCollectionEditor(id:String?) async throws -> CollectionEditorSnapshot`; `saveCollection(_ input:CollectionInput,expectedRevision:String?,context:CollectionEditingContext) async throws -> CollectionEditorSnapshot`; `deleteCollection(expectedRevision:String,context:CollectionEditingContext) async throws`; `readbackCollection(context:CollectionEditingContext) async throws -> CollectionEditorSnapshot`.
- Session/document invalidation uses opaque local tokens and connection generation. SDK and Store keep write generations/readback barriers; list refresh does not replace editor context. Unknown-create list review is explicit and does not unlock the old draft for resubmission.

EditorState/UI owner defines `CollectionEditorActions` with MainActor/Sendable async closures: save(CollectionInput,String?) -> PageCollection; delete(String) -> Void; compare() -> PageCollection?. A UI bridge captures and advances the Store context after acknowledgements/readback; model still passes its ORIGINAL expected revision, never the bridge's newer token. Comparison does not adopt server content until user confirmation. A missing comparison disables further old-draft writes and offers safe exit/copy. `CollectionsView(store:BoardStore)` is the App entry point; root adds its Library navigation link.

### Task 1: Kit collection domain, transport and demo

Owner A. Own Packages/FiestaBoardKit/** only; coordinate fixture usage with C. Do not change project files/AppState/UI.

- [ ] Write/run failing tests for wire fixtures, prefixes/colon IDs, create201/delete200{id}, original update/delete preconditions, receipt identity/protocol/revision, 400/404/409/412, missing protocol, unknown mode/version, opt-in, same-URL reconnect, auth loss, late GET vs save and uncertain create/update/delete. Use deterministic continuations, not sleeps.
- [ ] Implement frozen types/methods. Create gated to audited10.1.7 non-dev+opt-in; existing updates/deletes need original loaded protocol/revision. Preserve original supplied token across newer reads. Strict mutation acknowledgements, typed refusal vs unknown outcome, no replay.
- [ ] Implement in-memory Demo collection CRUD and fresh UUID generations without widening the existing demo board-control version gate. Support all modes and fixture-level conflict/unknown tests.
- [ ] Run full Kit tests, record red/green evidence and commit only owned files. Tell root/B exact interfaces early.

### Task 2: Native collection draft model and SwiftUI forms

Owner B. Own new EditorState Collection*.swift + tests, App/Features/Collections/** only. Root owns BoardStore/App chrome/project. Existing package dependencies remain unchanged.

- [ ] Write failing state tests: create/edit all modes, preserve page/rule order, invalid numeric input, original revision after refresh, overlapping edits/save/delete, 412/unknown/in-use/missing, compare vs adopt, cancellation, recovered original baseline, and no automatic create retry.
- [ ] Implement host-testable observable draft model/actions. Persist checkpoints including original baseline/revision and invalid user text; explicit recovered draft restore and clear-on-ack/discard. Different-server archives never load automatically. Do not rebase a recovered old draft onto a fresh token.
- [ ] Build accessible native list/search/create/edit/delete workflow, page/rule reorder and membership choices, intervals/default/poll controls, in-use errors, uncertainty/comparison/recovery and unsaved-navigation confirmation. Keep drafts through resize/background and provide local copy/preservation on session loss. Storage acknowledgement wording; no implicit board selection.
- [ ] Consume root Store interfaces through a captured bridge, disabling unknown-mode/protocol editing. Declare current source/controls fully enough for unknown read-only data to remain inspectable.
- [ ] Run all EditorState tests and build when root interfaces land; commit owned files. Do not change .pbxproj or project.yml.

### Task 3: Merged-server source/fixture evidence

Owner C. Own new Fixtures/contracts/collections-v1.json, Tests/Contracts/test_collections_fixture.py, docs/research/2026-10-27-collections-contract.md. No Kit/AppState/UI/backend edits.

- [ ] Verify merged PR ancestor/source79edd37d2 and exact version10.1.7. Inspect collection public routes/models/validation/null/error semantics and generate sanitized known-mode read/create/update/delete/conflict/in-use fixtures with isolated Docker TestClient/temp stores.
- [ ] Check canonical request shapes against actual backend, including ordered rules/pages, null inactive configs, Unicode scalar boundary, five-second/day duration, two-second/ten-minute polling, references and generation changes. No hardware/provider calls.
- [ ] Document runtime capability vs exact audited-create gate and unsupported/unknown behavior. Give A fixture path/contracts early and verify native fixture integrity. Do not declare full server release support or actual native HA/OAuth/device proof.
- [ ] Audit existing validate/render adapters against10.1.7 and report whether source/fixture evidence justifies adding that exact non-dev version. Root/A make the code decision after evidence; do not widen gates yourself.
- [ ] Commit owned evidence/test files and report commands/results/limits.

### Task 4: Connection boundary, navigation, integration and review

Owner root. Own AppState new CollectionContext.swift/BoardStore collection methods/tests, App/FiestaBoardApp.swift, project generation/build integration, TASKS.md and final docs.

- [ ] Pin context to generation/document/original revision; test cross-deployment and same-URL reconnect, delayed responses, dirty list refresh, cancelled writes, malformed ack, missing resource, changed auth and no duplicate POST. Share existing session/hardware boundaries without broadening them.
- [ ] Add Library Collections entry, regenerate project ONLY in isolated worktree when all files are present, and build unsigned Simulator/device + UI-test compilation. Run all package/contract checks. Execute UI tests only if simulator services available; report compiled vs executed honestly.
- [ ] Astra reviews core and integrated workflow, root routes findings to original owners and verifies fixes. Review must include uncertainty recovery, original-revision archive restore and narrow/wide accessibility behavior; source/build evidence does not substitute for interactive device acceptance.
- [ ] Update TASKS/docs for merged backend and actual native coverage; safely integrate to main preserving user's project/signing edits. Leave remaining scheduling/rich canvas/etc work visible.
