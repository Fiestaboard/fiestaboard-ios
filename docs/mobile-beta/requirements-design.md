# FiestaBoard mobile beta: requirements and iOS design for Astra review

Date: 2026-10-31. Status: **Astra-approved architecture and corrected execution sequence; beta acceptance remains open**. Jeffrey delegated design decisions to the team with independent Astra critique and asynchronous screenshots. Parent coordinates that review. Implementation can follow accepted decisions without another user design-approval round. Publication destinations, distribution, device installation, live deployments, software installation, and security changes retain their separate boundaries.

## Current execution checkpoint — 2026-10-31

Active implementation is `/Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031`; the original Documents checkout is frozen after exact committed and dirty recovery verification. Parent-relayed Astra architecture/plan rulings are recorded in execution-plan.md and the SDD ledger. The historical discovery table below remains dated evidence, not current Git status. Core flexible contract fixtures now pin PR2395 head `864cfa6baccdf5b9f29db712442bf40fb3e79923`; this is source evidence, not a deployed-server claim.

Reader/physical geometry, verified page-draft ownership and native Pages/Collections/Schedule navigation slices are reviewed and tested. Native flexible text/Canvas authoring, conditional save/reopen and recovery are implemented; expanded inspector-label UX acceptance is still being completed. Collection durable ownership is the current parallel P5 package. Full schedule authoring, broader collections, display/system settings, integration/account administration and remaining accessibility/device matrix acceptance remain open. User conditionally authorized organization repository publication and CI at beta readiness; no publication or security change has occurred.

## Outcome and actual user requirements

Bring native iOS and Android clients to web feature parity, with requirements, design, tracked implementation and validated journeys through beta. iPhone and iPad are included; Apple Watch is excluded. Include iPhone Duo and Android phones, foldables and tablets. Keep navigation terminology mostly aligned with web. Make the editor natural to each OS and follow each platform's official design principles. Preserve useful existing work; avoid another framework or product reinvention. Send representative actual UI screenshots for optional asynchronous feedback.

The user has not chosen a minimum OS, distribution channel, repository publication destination, exact device set, or performance budgets. Proposals below are team decisions for review, not quoted user requirements. This document owns the iOS recovery and common parity semantics; the parallel Android stream owns Android architecture, Material guidance, implementation and device evidence.

## Recovered source and trustworthy baseline

| Source | Verified state | Consequence |
| --- | --- | --- |
| `/Users/jeffre/workspace/fiestaboard-ios` | `main`, `b2e49f91a0e2546cc090f941a2dd937c319c0fef`; no remote; only tracked modification is the Xcode project | Preserve the user's working/signing overlay. Do not publish its accumulated history without an agreed destination. |
| iOS `.worktrees/foundation` | `codex/ios-foundation`, same commit, clean at inspection | Old handoff's paused/uncommitted status has been superseded. Do not replay completed work. |
| Existing iOS project overlay | SHA256 `273c31880d0801475d483a7431c6a09e1457fd5f58ec65e23b30812a298aef49` | Same as deployment session; retain bytes during future integration. |
| Remote web `main` | `3669e60864a38df4738de20fafe7b72675a230a0`, version **10.3.2** | Proposed released-source parity reference. Task-local exact archive inspected. Shared local `main` and `next` refs were stale; the dirty web worktree is not this baseline. |
| Remote `next` | `5aabc252ab23ec76da4756b94bfca5af4542d301` | Separate integration branch, not an assumption of release equivalence. |
| [Core PR 2395](https://github.com/Fiestaboard/FiestaBoard/pull/2395) | Open draft to `next`, head `1a94b34b90213648433fe7bf90b77be8c9300de3` | Track flexible documents as an explicit pending dependency. Do not equate it with deployed main. |
| Native contract ledger | `Contracts/parity.json`: 84 IDs, source `b5eac069...` (10.1.17); scoped later 10.1.20 fixtures | Stable IDs are worth retaining. A current 10.3.2 semantic/schema refresh remains required. |

`evidence/baseline.json` records exact hashes. `parity-inventory.json` and CSV retain all 84 original workflow IDs, historical operation IDs and source references, observed native state, and current-source file changes. These are discovery records, not 84 newly verified contracts. Historical line references must not be treated as current line numbers.

Prior evidence: October 29 editor report records 314 Swift tests and selected actual iPhone/iPad simulator flows, including rich/source authoring and correction of focus/scroll issues. This task's previous deployment built/signed the same commit, reran 314 Swift plus 71 tooling/contract tests, and installed 0.1 (1) on Jeffrey's iPhone 17 Pro. Launch then failed because the device was locked. That is installation evidence, not complete device UX or server compatibility acceptance. No tests/builds have been rerun merely for this discovery.

## Findings: what to keep and what is missing

| Capability | Current iOS evidence | Gap against current web |
| --- | --- | --- |
| Connection/auth | Bonjour discovery, saved metadata, explicit remembered session/Keychain, bootstrap/setup/login/logout, scene generation fencing | Physical LAN/permission acceptance; full tablet auth coverage; HA ingress authentication; current-server pairing |
| Home/control | Board selection, grid output, text/page send, pause/schedule/fallback/restore, captured-target and unknown-result barriers | Full service/current/selected/scheduled/held/silence/temporary override state; external output actions; complete pixel rendering |
| Displays | Read-only list/detail and select; controls elsewhere | Native add/edit/delete/output marketplace, schema actions, credentials, geometry, panel/kiosk, per-display playback settings |
| Pages | List/search, templates create/delete, details, local edit, revision guards | Filters/sort, duplicate/import/export/Picks, all types, accurate saved/batch previews and flexible authoring |
| Editor | Lossless raw JSON, sparse changes, TextKit token attachments, rich/source, row operations, formatting, persistent recovery, explicit conflict comparison | LED text-range formatting/catalogs, Canvas layers/drawing/shapes/sources, flexible blocks, full IME/paste/undo, exact preview and physical-device proof |
| Collections | Native CRUD, time/variable/random rules, ordered members, recovery/revision protection | Current-server adapter acceptance, native runtime/device matrix and mixed-document compatibility |
| Schedule | No complete native feature flow | CRUD/calendar/list/recurrence/sun/timezone/DST/overlap/gap validation; per-display behavior and silence |
| Integrations | No complete native feature flow | Marketplace/Git install, settings/remote options/secrets, instances, OAuth flow families, helper catalogs, demos/provenance, color rules/JSON mapper |
| Settings/account | Primarily app connection, opt-in and demo controls | General/account/network/AI/system/advanced, sessions/activation/MCP, backup/restore/updates/power/diagnostics |
| AI | No complete native feature flow | Providers/models, streaming chat, approvals/elicitation, history, staged generation and apply, interruption without replay |
| Navigation/platform | SwiftUI sidebar-adaptable tabs, scene-owned stores, bounded adaptive editor layout | Web taxonomy, deep links, import/share, comprehensive accessibility/localization and window/fold-state retention |

Specific source corrections matter. `CapabilityPolicy.swift` allows board operations only for exact 10.0.0/10.1.17/10.1.20 and create/delete only for 10.1.20. `Service.swift` still audits collection creation only at 10.1.7 and previews only at 10.0.0/10.1.2/10.1.7. The result is not one coherent supported current-server pairing. Do not resolve it by deleting version guards. `App/BoardOutputView.swift` draws supported flap grids up to 4,096 cells and explicitly lacks pixel/other charset rendering. `App/FiestaBoardApp.swift` has Home/Library/Displays/Settings; most server administration is absent. This is more than a visual refresh.

## Architecture proposal and alternatives

**Recommend extending the existing native SwiftUI app.** Retain `FiestaBoardKit` transport/auth/capability adapters; `FiestaBoardAppState` lifecycle and captured-target state; `FiestaBoardDocuments` lossless JSON/document editing/drafts; `FiestaBoardEditorState` editor/recovery/conflict state. Keep UIKit/TextKit only where native rich text requires it. Split the large app shell into feature routes as features arrive, without a broad preemptive rewrite.

Share with Android a versioned behavior specification, JSON fixtures, semantic editor operations, error/outcome vocabulary and acceptance journeys. Keep platform UI, text input, accessibility, lifecycle and secure storage native. No binary Swift/Kotlin sharing layer is proposed. Do not reproduce server template evaluation or plugin runtime in either client.

Alternatives considered: a web wrapper would shorten surface parity but does not satisfy the requested native editor and OS experience; a clean-sheet iOS rebuild would discard tested conflict, identity and raw-document handling. A shared cross-platform UI would add migration and input/accessibility risk without evidence it solves the hard editor problem. None is recommended.

API model: public operations where suitable; bounded first-party adapters for web-only operations. Pin both schema and behavior to one accepted beta server candidate. Capability records distinguish read, preview, write, document family, geometry, output mode and revision protocol. Unsupported operations explain the reason without hiding the destination. Authentication state, server identity and permission are separate from feature support. Preserve cookie scope, HTTPS/explicit local HTTP policy, CSRF/origin requirements and credential-free external document loads.

## Navigation and settings design decision for review

Canonical destinations follow inspected web source: **Home, Displays, Pages, Collections, Schedule, Integrations**, with **Picks, Help, Settings and Account** reachable as secondary destinations. Display detail uses **Overview, Settings, Playback**. System settings follow **General, Account, Network, AI, System, Advanced**; Network remains capability-driven. Board-specific transition/silence/schedule behavior/read/update cadence belongs to the chosen display. App-local connection/appearance preferences are clearly labeled rather than mixed into server settings.

Recommended shell: native `NavigationSplitView` with the full ordered destination sidebar at sufficient width, collapsing to a native destination list and detail stack at compact width. Keep the active section and server/display context visible; provide a labeled section-switch control and proper Back behavior. Retain destination paths, selection and editor state when changing width. This preserves all web names without forcing eight tabs into a phone or renaming Pages to Library. Default connected landing content is Home; the section list stays one standard navigation step away.

Alternative for Astra to evaluate: a small fixed tab set plus an explicit full destination browser. It improves frequent switching but risks hiding Collections/Integrations and inventing a new grouping. Apple advises against overflowing tabs. Prefer the consistent sidebar/list hierarchy unless actual compact-device usability evidence favors tabs. Do not commit to both shells or build custom browser-like chrome.

Use standard Form/List/detail screens for settings. Align fields, group by purpose, and use disclosure for advanced controls; avoid nested bordered cards. Keep display previews at their true aspect ratio, with consistent surrounding spacing rather than arbitrary fixed heights. Paused output remains visually quiet and explicitly labeled, with current frame versus intended content distinct. A paused state must not look like an active send or an error by color alone. This carries forward the user's earlier visual concerns without assuming another worker's unreviewed web redesign.

## Native editor contract

One document session owns the original raw document, baseline revision, selection, undo history, local checkpoint, target for evaluation and pending save. Changing layout does not recreate that session. Saving the document and showing it on a physical display are different actions. Auto-checkpoint local work; use deliberate server save and a separate named-target live action. Recovery must retain unknown fields, token spelling, Unicode, explicit nulls and original revision. Conflict comparison never silently retokens stale content. An unknown write outcome never automatically replays.

Phone: document content first, native text selection/keyboard controls, contextual insert/format toolbar, inspector presented as a native sheet or navigated detail. Tablet/open wide window: same document plus adjacent inspector when space permits. Use system selection, copy/paste, undo/redo, keyboard commands and accessible alternatives to drag gestures. Dynamic Type can collapse inspector columns independently of device model. Do not scale a desktop toolbar into a phone.

Keep separate editing adapters for legacy templates, Canvas documents and flexible semantic blocks; share document safety and preview services. A flexible text/Canvas/spacer block uses stable IDs, conditions, priority, styles and target restrictions from the core protocol, not guessed absolute positions. Canvas editing adds native tools only after the geometry/serialization contract is tested. Native drawing must emit interoperable server content, not an opaque OS-only drawing format. Dynamic variables remain visibly unresolved in design mode; exact evaluated geometry/pixels come from server preview. Presentation code must preserve ordinary/native output mode and exact RGB/geometry semantics.

Before editor completion, prove selection and marked text through Chinese/Japanese IME, emoji/graphemes, dictation, multiline paste, rich/source switching, formatting ranges, chip editing, system undo and local recovery. The current code's guarded marked text and selected clipboard serialization are foundations, not proof those journeys work end to end.

## Flexible JSON coordination: do not duplicate the companion

Reviewed handoff: `/Users/jeffre/Documents/Codex/2026-10-30/task-2/flexible-implementation-handoff.txt`.

Prepared `ios-flexible-reader.patch` is based on current iOS `b2e49f9`, changes four files (66 insertions, seven deletions), and has no publication destination. Inspection confirms it makes non-template read projections tolerant, keeps legacy identity/geometry strict, and substitutes a web-editor explanation for unsupported editing. It is **a mixed-library compatibility patch, not native flexible-editor parity**. Handoff reports 145 Kit tests and unsigned simulator build; that evidence was not rerun here. The patch is not present in the original checkout and was not applied.

First implementation intake: coordinate with its owner, verify exact base/current diff and patch hash, apply only once in an isolated mobile branch after review, and rerun affected decoding/UI plus the complete relevant suites. Include malformed future fields, mixed legacy/flexible lists, identity rejection, unknown-field preservation and unsupported-edit behavior. Do not publish unrelated native history or claim reader compatibility proves flexible mutation/rendering support.

Add explicit parity deltas beyond the inherited 84 IDs: `flexible_document_read`, `flexible_block_authoring`, `flexible_target_preview`, `physical_frame_modes`. Keep source reference at PR head until merge, then re-pin. Core merge/deployment and adapters' hardware acceptance remain separate. Readers must be ready before flexible documents appear in a shared library.

## Apple design principles translated to acceptance

Official pages were retrieved on 2026-10-31; local copies are under `evidence/apple-hig/`. These are testable product choices grounded in guidance, not a claim that using SwiftUI alone makes the experience native.

| Guidance | Application and proof |
| --- | --- |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Adapt to container, safe area, text size and locale; preserve hierarchy during resize. Test clipping, keyboard reachability and state retention at narrow/short/wide windows. |
| [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) | Navigation remains stable; actions live in toolbars. Review sidebar/list proposal against tab overflow and destination discoverability. |
| [Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados) | Use the additional space for meaningful document/inspector relationship, support keyboard/pointer and window changes; no enlarged phone-only layout. |
| [Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data) | Native controls, suitable keyboard, inline validation, paste/drop where useful, efficient keyboard navigation; test error correction without lost input. |
| [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Dynamic Type, VoiceOver names/order/actions, adequate contrast, non-color state, gesture alternatives. Adopt 44×44-point primary targets as our design target; Apple lists 44×44 default and 28×28 minimum, so do not misquote 44 as its universal minimum. |

Direct verification confirms [iPhone Duo specifications](https://www.apple.com/iphone-duo/specs/) and [Apple preparation guidance](https://developer.apple.com/iphone-duo/prepare/). The latter distinguishes iOS 27 dynamic resize from 27.1 edge-to-edge behavior. Build with the existing 27.1 toolchain, respect safe areas and window changes; do not derive point layouts from physical display dimensions. Open/closed transition must retain unsaved text, selection, undo, scroll position and pending action identity. Guidance existence does not establish app support.

## Beta acceptance and evidence model

Keep implementation, build, unit/contract tests, actual UI runtime, physical observation and beta acceptance separate. Every workflow record needs exact app/server revisions, fixtures, device/OS/window/input conditions, commands/results, screenshots for representative states, reviewer verdict and open limitations. Screenshots use synthetic servers/pages/accounts and contain no credentials or private content. A screenshot supplements interaction evidence.

Beta parity means every in-scope workflow and the four flexible deltas is implemented and validated, or has an explicit reviewed native equivalent. No silent omission because the web workflow is difficult. An intermediate demonstration build may be useful but is not the requested parity beta. Separate distribution readiness from functional beta acceptance.

Required cross-feature journeys:

1. Find/manual-connect → setup/sign-in → remember/relaunch → select display → see accurate status → compose/show with readback → pause/resume → logout/reconnect.
2. Integration setup/OAuth → variable selection → create/edit each page family → exact target preview → save/reopen → add to collection → schedule → confirm selected/resolved/reported state.
3. Edit with keyboard/IME and inspector → resize/rotate/fold → background/terminate/recover → concurrent edit conflict → compare → deliberate retry without loss or duplicate send.
4. Configure physical/virtual display → schema actions/settings → playback/silence → geometry compatibility → native/ordinary preview → controlled physical observation when separately authorized.
5. Account/session/activation → system settings/backup/restore/update/network recovery, including unavailable capability and refused operations.
6. AI generation/chat/tool approval → staged editor changes → reject/accept/save; cancel/reconnect must not replay a tool or create duplicate content.

Proposed quality gate: zero unresolved data-loss, credential-leak, wrong-target, duplicate-mutation or crash defects; no blocker on any required journey; accessibility and input defects affecting a core task block acceptance. Establish measured startup/editor/preview memory and responsiveness budgets with representative fixtures during the first slice; do not invent a performance pass from simulator build success.

## Device and topology matrix

| Target | Available evidence/environment | Required beta proof |
| --- | --- | --- |
| iPhone | Physical Jeffrey's iPhone 17 Pro paired; iPhone 18 Pro booted simulator; 17e/17/Air/Pro Max simulators listed on iOS 27.0 | Compact/large, portrait/landscape, software keyboard, large text, VoiceOver, lifecycle, physical LAN/Keychain; no new physical install authorized by this discovery |
| iPad | 13-inch Pro M5 simulator plus mini, Air 11/13 and A16; no physical iPad listed | Full and narrow/short windows, split/multiwindow, keyboard/pointer, accessibility, conflict between scenes; physical iPad and Pencil acceptance pending available hardware |
| iPhone Duo | Official device and SDK guidance verified; no configured Duo simulator or paired Duo in current inventory | Closed/open and repeated transition with keyboard/editor/modal in flight, safe areas and state retention; remain unverified until an actual compatible destination is available |
| Minimum OS | Project currently targets iOS/iPadOS 26; installed iOS simulator runtime is 27.0 | Team to preserve 26 target provisionally; actual minimum-OS run remains unavailable, not inferred from compilation |
| Android | Separate discovery lead | Phones/foldables/tablets, fold posture/window change, TalkBack, native text, lifecycle/process death; share journey IDs and exact server fixtures |

Exercise auth enabled/disabled/first-run, LAN hostname/IP, denied local-network permission, trusted HTTPS, deployment prefix, offline/timeout/auth expiry, server upgrade/restore identity change and two concurrent clients. HA ingress needs real authenticated topology proof rather than only a prefix mock. OAuth/provider and hardware checks require controlled accounts/devices and their specific authorization; independent implementation and fixture work continues while these are unavailable.

## Proposed sequence and review decisions

1. **R0: reconcile and review.** Accept this design with Astra; retire misleading stale status claims by linking current evidence without destroying historical logs. Freeze 10.3.2 plus explicit PR2395 delta; coordinate Android and editor UX owners.
2. **R1: current compatibility and first complete journey.** Refresh schemas/behavior fixtures, integrate the reader once, implement an accepted adapter, run connection/home/preview/save journeys on actual simulators. Capture first native screenshots.
3. **R2: navigation and settings foundation.** Implement accepted native hierarchy, display-scoped settings and shared schema-form semantics needed by outputs/integrations. Validate compact and wide journeys before expanding forms.
4. **R3: editor vertical slices.** Finish legacy input/preview, Canvas and flexible authoring as separate interoperable document types. Use failing tests at protocol/state boundaries, actual text-input UI tests and Astra review per slice.
5. **R4: connected workflows.** Collections/schedules, outputs/integrations/OAuth, system/account/AI with bounded parallel owners and shared fixture contracts. No screen-count completion claims.
6. **R5: beta evidence.** Full ledger, clone/build reproducibility, runtime device matrix, accessibility/localization/performance, controlled external checks; correct gaps before labeling beta. Distribution is a later authorized action.

Astra review priorities: coherent current-server policy; whether the compact section-list navigation is sufficiently discoverable; native text undo/serialization semantics; boundaries between page types; realistic beta gate and test matrix; no dropped old workflow IDs. Parent should bring Android architecture and separate editor UX findings into the same review. Preliminary reviewer constraints and verified contract traps are incorporated in `execution-plan.md`; a full verdict on this artifact is still pending.

## Assumptions and remaining decisions

- Proposed beta baseline is 10.3.2 plus the separately tracked flexible change, not every future web commit. Upstream deltas enter a dated intake ledger.
- Minimum iOS 26 is retained provisionally because it is the existing project target; support is unverified on that runtime.
- The native repository remains local and unpublished. Jeffrey now conditionally authorizes creating iOS/Android repositories in the FiestaBoard organization **once the betas are ready**, with CI and branch protection. A read-only organization list found existing `fiestaboard-tvos` and `fiestaboard-androidtv`, not an iOS or Android phone/tablet repository. Recheck before creation. Do not repurpose the TV apps. Exact repository/visibility/protection choices and actual system permission checks remain implementation-time inputs; publication does not authorize store distribution or device deployment.
- No new software, simulator runtime, entitlement, provisioning or security-setting change is authorized here. Missing Duo/minimum-OS/physical-iPad coverage remains an explicit evidence gap.
- Design/architecture approval is delegated to Astra review, not waiting on Jeffrey. Actual runtime screenshots will be delivered through a supported attachment channel; local paths alone are internal handoff artifacts.


## Approved implementation refinements — 2026-10-31

Astra approved the architecture and execution sequence. Critical path is reader/capability/revision/lossless/target-identity intake, minimal native shell, physical-frame goldens, then one flexible text/Canvas edit-preview-save-reopen journey before broad feature expansion. Refresh other endpoint contracts just before their native feature. See execution-plan.md for the current sequence and acceptance checks.

Cross-platform behavior must preserve intermediate numeric edits (empty/minus/decimal); hidden invalid fields keep Save blocked with a visible error route; Saved only represents an acknowledged snapshot and changes back to Unsaved on a new edit; keyboard and short-window controls remain scroll reachable.

Identity audit found request generations already exist in Service and BoardStore, with same-URL reconnect tests. Durable DraftIdentity currently lacks connection/account scope. The actual auth status contract has no immutable principal ID. Astra recommends a non-secret random connection UUID persisted alongside verified installation ID and cookies in the vault envelope, provisional until fresh restore verification succeeds. Fresh login/setup gets a new UUID; verified remembered restore retains it; ordinary same-session reconnect retains durable identity while changing operation epochs. Raw page bytes and verified scope must be captured atomically under service generation, then carried through PageDocumentSnapshot to the editor. Never derive identity from tokens, cookie hashes, display names or mutable username.

Migration must preserve existing URL/page-only draft files and expose an explicit unassigned-drafts recovery/export route. Do not silently reassociate them with a new login or just change filenames and orphan them. Cross-scope local recovery must not automatically make an old server revision writable. Implement and test this before claiming beta draft recovery/isolation. This is pending product work, not a production-authorization blocker.
