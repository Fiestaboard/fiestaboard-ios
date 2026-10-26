# FiestaBoard iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking. This is a full-product milestone plan; expand each milestone into bounded implementation tickets after its contracts are frozen.

**Goal:** Release a native iPhone, iPhone Duo and iPad controller with complete web-app feature parity and adaptive Apple design.

**Architecture:** SwiftUI universal app with feature stores and local packages for transport/domain models, reusable rendering and testing. FiestaBoard retains business logic and hardware communication. Native adapters use supported public operations and an explicitly maintained contract for remaining first-party workflows.

**Tech Stack:** Swift 6, SwiftUI/Observation, Foundation URLSession, Network/Bonjour, Security/Keychain, TextKit for rich text, Swift Testing and XCTest UI tests. Default to Apple frameworks; introduce dependencies only for a measured gap.

**Spec:** [FiestaBoard iOS design](../specs/2026-10-25-fiestaboard-ios-design.md)

## Global constraints

- Repository: `fiestaboard-ios`; separate from existing web, TV and historical Swift repositories.
- First App Store release requires complete web-app feature parity; no feature deferral without the user's explicit scope change.
- Proposed deployment floor: iOS/iPadOS 26.0; build with Xcode/iOS SDK 27.1 or later and guard newer APIs.
- User wants all useful iPhone Duo poses; support continuous resizing, asymmetric safe areas and state preservation.
- Native content/editor UI, Apple system navigation/glass, server-owned evaluation/scheduling/plugins/hardware.
- GPT-6.1 Sol implements; GPT-6 Astra reviews architecture, high-risk work, integrated milestones and release.
- Pin server source/contracts; dirty checkout and running v9.14.9 are not a v10 release fixture.
- No production-device mutations in automated tests; isolated fixture servers and virtual outputs only.

## Review focus

1. Wrong-server/wrong-board writes after selection or pose changes: capture immutable target identity for each command and test interleaved responses.
2. Session leakage across same-host ports/prefixes or redirects: isolated credential contexts and adversarial redirect tests.
3. Silent loss of rich/unknown document fields or concurrent edits: lossless fixtures, omission/null assertions and atomic conflict detection.
4. HTTP success mistaken for hardware success; retry duplicates after timeout: test partial/held/silenced/outcome-unknown states and no automatic command replay.
5. Fold/resize/background destroys drafts or duplicates streams/pollers: state restoration and task-lifetime UI tests during in-flight work.

## Planned repository structure

```text
FiestaBoard.xcodeproj/                 universal app and UI-test schemes
App/FiestaBoardApp.swift               scene composition
App/Navigation/                       routes, tabs/sidebar, selection
App/Features/                         Connect, Home, Displays, Library, Editor,
                                      Collections, Schedule, Integrations,
                                      Assistant, Settings, Account, Diagnostics
App/Resources/                        assets, String Catalog, privacy manifest
Packages/FiestaBoardKit/
  Sources/Transport/                  URLs, sessions, errors, request policy, SSE
  Sources/Domain/                     explicit models and service protocols
  Sources/Services/                   versioned API adapters and repositories
  Sources/Documents/                  template/canvas model and serialization
  Tests/                             fixture and behavior tests
Packages/FiestaBoardRender/            geometry, flap/LED/layer rendering
Contracts/                           schemas, version matrix, operation ledger
Fixtures/                            sanitized JSON and golden render inputs
Tests/UITests/                       lifecycle, parity and accessibility flows
Tests/Integration/                   pinned disposable servers/virtual outputs
scripts/                             contract checks and simulator matrix
docs/parity.md                       every web workflow → native workflow/test
docs/release/                        review access, privacy, release evidence
```

Keep transport dependencies out of views. Each domain service consumes a deployment-scoped transport; each feature receives a service protocol and immutable server/board IDs. New packages must include macOS-compatible pure core tests where feasible, while app/render UI is tested on iOS Simulator.

## Milestone 0 — Freeze parity and prove the API contract

**Owner:** Sol investigator; Astra architecture review. Must finish before feature agents diverge.

**Files:** Create `docs/parity.md`, `Contracts/operations.json`, `Contracts/supported-servers.json`, `Contracts/public-openapi.json`, `Contracts/mobile-internal-openapi.json`, `Fixtures/contracts/`, `Tests/Integration/compose.yml`, `scripts/check-contracts.py`. Any backend additions are isolated sibling-repo changes, with separate review.

**Interfaces:** Produce a ledger with method/path, request/response/error schema, authentication, target scope, side effects, idempotency, version range and parity-row ID. Produce the exact minimum supported release and an explicit unsupported-version policy. Proposed metadata files are build-time artifacts, not claimed existing server endpoints.

- [ ] Enumerate every web route/action and hidden capability-dependent flow from clean v10 plus selected merged refresh changes; mark each as required or a documented platform equivalent.
- [ ] Create disposable auth-on/auth-off/first-run servers with virtual split-flap, Note/array and pixel outputs; collect sanitized fixtures with source version/hash.
- [ ] Exercise cookie login, session management CSRF/Origin, proxy prefixes and HA upstream authentication. Record supported connection topologies and implement necessary backend/bridge support rather than declaring URL-prefix support sufficient.
- [ ] Prove native completion for OAuth `relay`, `device`, `key_exchange`, and `plex_pin`, headless/manual code-or-URL paste, app-registration fields, reconnect/disconnect, expiry/denial and AI-provider connections. Specify browser return versus status polling per flow; do not assume the backend already offers an app callback. Include local and prefixed deployments and interrupted/suspended authorization.
- [ ] Test public CRUD/control and every required internal operation; stabilize the mobile contract by explicit versioned endpoints or bounded first-party adapters plus server-release compatibility CI. Avoid legacy paths with the December 2026 sunset policy.
- [ ] Inventory every page/collection/schedule writer: public/internal routes, web editors, AI tools, imports/restores and background writers. Put atomic revision validation/advancement in shared persistence. Require preconditions for native and participating first-party web/editor/AI saves; define explicit replacement/force semantics separately. Legacy unconditional writes must advance revision but can still overwrite later: document this limit and reconcile it, rather than promising universal protection. Test web/native and AI/native in both save orders, including unconditional writers. Publish the resulting server minimum.
- [ ] Add native-client session labeling if necessary so the account UI does not misleadingly imply iOS retains the password. This does not require adopting TV enrollment or changing TV scopes.
- [ ] Run `python3 scripts/check-contracts.py`; expect every parity row mapped, every operation fixture validated, no unapproved internal dependency and no undefined supported release.
- [ ] Astra reviews the ledger, auth/proxy proof and backend changes; Sol resolves findings and commits this milestone.

**Exit:** Full parity is achievable against a named, reproducible server release; unresolved protocol gaps are explicit blockers to dependent tasks.

## Milestone 1 — Connect securely and establish a buildable app

**Files:** Create project/schemes, `Packages/FiestaBoardKit/Package.swift`, `Sources/Transport/{DeploymentURL,HTTPTransport,SessionVault,APIError,RequestPolicy}.swift`, `Sources/Domain/{ServerProfile,ServerCapabilities}.swift`, `App/Features/Connect/`, package transport tests, `App/Resources/Info.plist`, CI workflow.

**Interfaces:** `DeploymentURL` preserves scheme/host/port/basePath. `ServerProfile` combines that identity with discovery instance ID without merging credential scopes. `HTTPTransport.send(_ request: APIRequest) async throws -> APIResponse`; `APIRequest` carries method, relative path, body, timeout class and replay policy. `SessionVault` stores session material keyed to deployment identity. `APIError` distinguishes connectivity, auth, setup-required, validation, conflict, rate-limit, server failure and unknown outcome.

- [ ] Write failing tests for prefix construction, IPv6, secure-cookie behavior, separate ports/prefixes, redirect refusal, revoked/expired credentials, structured 409 variants and non-JSON/204 responses.
- [ ] Implement transport, isolated cookie sessions and Keychain persistence; never persist passwords or automatically retry mutations. Reuse audited TV abstractions with new iOS identifiers and license attribution.
- [ ] Add user-initiated Bonjour/manual connect, permission-denied recovery, first-run setup and explicit insecure-local transport status. Use `_http._tcp` with FiestaBoard product filtering and `/api/discover` instance identity.
- [ ] Implement per-operation timeouts: fast reads, potentially long hardware/admin operations, and streaming have distinct policies derived from the ledger. Ten seconds is not a universal timeout.
- [ ] Add native navigation placeholder destinations and preview fixtures, then run `swift test --package-path Packages/FiestaBoardKit` and unsigned iOS Simulator build. Expect all transport tests and app compilation to pass.
- [ ] Run auth/proxy/CSRF integration cases against milestone-0 servers; Astra reviews security boundary, Sol fixes, commit.

## Milestone 2 — Adaptive shell and renderer

**Files:** `App/Navigation/{AppRoute,SceneStore,AdaptiveShell}.swift`, `Packages/FiestaBoardRender/`, `App/Resources/Localizable.xcstrings`, `Tests/UITests/AdaptiveNavigationTests.swift`, rendering fixture tests.

**Interfaces:** `SceneStore` owns route, selection and presentation intent per scene. `BoardSnapshot` carries geometry, display family/charset, cells, bitmap layers and state timestamp. Renderer consumes snapshots without networking or hardware writes.

- [ ] Write failing golden tests for flagship/Note/arrays, arbitrary panel dimensions, LED case/icons/colors/layers, white-board behavior and malformed layer bounds.
- [ ] Extract/adapt TV geometry/render code; build static thumbnails first, then bounded live animations. Preserve true pixel/cell aspect ratios during resize.
- [ ] Implement standard adaptive navigation, clear server/board context, sheets/inspectors and native glass; initialize String Catalog coverage for all fourteen web locales.
- [ ] Add UI tests resizing while a draft/selection is active; test folded/open Duo, asymmetric vertical bars, Split View, compact iPad and large Dynamic Type. Assert route/selection/focus survive.
- [ ] Build a bounded editor feasibility prototype in `Prototypes/NativeEditor/` with representative split-flap and LED documents. Test token-adjacent insertion/deletion, multiline paste, input-method composition, grouped undo/redo, rich/plain switching and resize. Require canonical round-trip equivalence, stable token identity and unknown-node preservation. Astra reviews the model/TextKit boundary before milestone 4 or 5 is delegated; revise the approach if the gate fails.
- [ ] Run package tests and simulator UI suite, inspect light/dark/accessibility screenshots, profile a large thumbnail grid. Astra reviews native interaction quality, Sol fixes, commit.

## Milestone 3 — Home, board control and displays

**Acceptance split:** 3A (Home/control) depends on milestone 2 and can pass independently. 3B (display configuration/setup) additionally depends on 7A schema foundations. One display owner integrates the shared schema engine; no duplicate form implementation.

**Files:** `Sources/Domain/BoardService.swift`, `Sources/Services/{BoardRepository,MutationCoordinator,PollCoordinator}.swift`, `App/Features/{Home,Displays}/`, control and display integration/UI tests.

**Interfaces:** `BoardService.snapshot(boardID:) async throws -> BoardSnapshot`; `execute(_ command: BoardCommand, target: BoardTarget) async throws -> CommandOutcome`. `BoardTarget` fixes server+board identity. `CommandOutcome` represents acknowledged/sent/held/silenced/partial/failed/unknown, with server reason and warnings. `PollCoordinator` is injectable/cancellable and scoped to visible subscribers.

- [ ] Write tests switching server/board during polls and writes, silence 202, guard 409, pacing 429, partial 502, saved selection without physical send, background cancellation and timeout reconciliation.
- [ ] Implement actual-output dashboard, quick sends, active selection, pause/silence/temporary overrides/held output, service controls and return-to-schedule behavior according to the parity ledger.
- [ ] For 3B, implement display/panel library, add/setup/discovery/test/actions and configuration/playback using the accepted 7A interfaces. Sign off 3B after this integration; do not hold 3A waiting for forms.
- [ ] Implement viewer/share/deep-link equivalents; ensure controls name the target and destructive operations confirm scope.
- [ ] Verify virtual multi-board workflows, no duplicate writes and poll cadence/backoff; Astra reviews command semantics and visuals, Sol fixes, commit.

## Milestone 4 — Content library and lossless native editor

**Files:** `Sources/Documents/{PageDocument,TemplateToken,PagePatch,DocumentCodec,DraftStore}.swift`, `Sources/Domain/PageService.swift`, `App/Features/{Library,Editor}/`, rich editor bridge, `Tests/Documents/`, `Tests/UITests/EditorTests.swift`.

**Interfaces:** `PageDocument` preserves canonical template, line metadata, page type, geometry, canvases, transitions and unknown fields. `PagePatch` distinguishes unchanged/set/clear. `PageService.save(document:expectedRevision:) async throws -> PageDocument`; conflicts cannot silently overwrite. `PreviewService.render(document:target:revision:) async throws -> RenderResult` is side-effect free. Live-to-board uses the separate command interface.

- [ ] Write failing round-trip tests for every page type, rich/LED markup, escaped tokens, Unicode, formulas, color/icon nodes, metadata, unknown fields and explicit null clears.
- [ ] Implement library grid/list/search/filter, CRUD/duplicate/share/import/export/Picks and batch previews. Preserve geometry compatibility and orphan shapes.
- [ ] Implement document-based TextKit rich editing and native plain mode, token/variable pickers, cell painting, selection, clipboard and grouped undo/redo.
- [ ] Add persistent drafts, dirty navigation protection, restore/reload/duplicate conflict choices, changed-field saves and revision preconditions.
- [ ] Add debounced revision-tagged preview; ignore late results from old targets/drafts. Implement explicit timed live-to-board mode with stop/expiry/background rules matching the contract.
- [ ] Test fold/resize/scene restoration while editing, preview arriving out of order, concurrent web edit, keyboard/accessibility focus and lossless open-save across all golden documents.
- [ ] Run package/editor integration and UI tests; Astra reviews serialization, conflict behavior and actual touch editing before Sol fixes and commits.

## Milestone 5 — Canvas authoring

**Files:** `Sources/Documents/{CanvasDocument,CanvasPatch}.swift`, `App/Features/Editor/Canvas/`, canvas fixture tests and `CanvasInteractionTests.swift`.

**Interfaces:** `CanvasDocument` preserves the server model's area, bleed, scale, text-flow, palette, shapes/pixels and expression source. Canvas edits modify `PageDocument`; previews use milestone-4 `PreviewService` and display server-produced layers.

- [ ] Write tests for eight-canvas limit, area/coordinate conventions, expression preservation, clearing canvas data, byte-length validation and rendering issues.
- [ ] Implement Draw/Shapes/Source with touch and Pencil where available, zoom/pan, selection, grouped undo and keyboard-accessible numerical editing.
- [ ] Implement native visual authoring for every supported shape/source operation and accessible alternatives to drag gestures; do not replace this milestone with a JSON-only editor.
- [ ] Verify multi-layer output against the same server/web golden examples; resize/fold during a stroke and preserve valid undo state.
- [ ] Profile large canvases and preview cancellation; Astra reviews fidelity/usability, Sol fixes, commit.

## Milestone 6 — Collections and schedules

**Files:** `Sources/Domain/{CollectionService,ScheduleService}.swift`, corresponding repositories, `App/Features/{Collections,Schedule}/`, rule/timezone integration tests and calendar UI tests.

**Interfaces:** Versioned collection/schedule DTOs and revision-aware saves from the ledger; ordered IDs and explicit board timezone. Server remains authoritative for rule evaluation, active schedule and sun times.

- [ ] Write failing cases for ordering, duration/default references, time/random/variable rules, missing pages, timezone/DST gaps/overlap, midnight boundaries, sun offsets, recurrence and per-board silence interaction.
- [ ] Implement collection library/detail/editor with keyboard/touch reorder, rules and previews; distinguish resolved current member from configured collection.
- [ ] Implement native calendar and list, forms, drag/time resize, enable/defaults/conflict/gap displays and accessible equivalent actions.
- [ ] Test concurrent changes and return-from-background reconciliation, narrow/wide calendar usability and long localized labels.
- [ ] Run isolated scheduling fixtures and UI tests; Astra reviews semantics and native interaction, Sol fixes, commit.

## Milestone 7A — Shared schema contracts and forms

**Dependencies/ownership:** Starts after milestone 2. One Sol owner defines `SchemaNode`, `SchemaDraft`, option-provider/action interfaces and shared project wiring. 3B consumes this accepted foundation; 7A does not depend on 3B.

**Files:** `Sources/Domain/{SchemaNode,IntegrationService,OutputService}.swift`, `App/Features/Integrations/`, `App/Shared/SchemaForm/`, OAuth coordinator, schema fixtures/tests.

**Interfaces:** Supported schema vocabulary and UI hints are enumerated from existing web fixtures; `SchemaDraft` preserves unknown fields and untouched secrets. Option providers and server actions are explicit ledger operations, not arbitrary URLs from untrusted schemas.

- [ ] Write tests covering all schema types/hints, conditional/dependent fields, nested data, dynamic options, secrets unchanged/set/clear, validation errors and unsupported schema behavior.
- [ ] Implement reusable native forms and documented option-provider/action interfaces with representative integration and output schemas.
- [ ] Verify the full schema vocabulary and secret preservation; Astra reviews shared schema contracts/security/usability, Sol fixes and commits 7A before consumers integrate.

## Milestone 7B — Integration workflows and OAuth

**Dependencies:** 7A and milestone-0 OAuth proof. **Files:** `App/Features/Integrations/`, OAuth coordinator and workflow integration/UI tests. **Interfaces:** Consume accepted 7A forms and ledger-defined start/completion/status operations; provider exchange/credentials remain on the server.

- [ ] Implement plugin instances/variables/demos, installed/marketplace/Git flows, update/uninstall/enable and provenance labels. Test unsupported plugins and install/update/restart recovery without blind retries.
- [ ] Implement all four OAuth flows (`relay`, `device`, `key_exchange`, `plex_pin`), headless/manual code-or-URL paste, app-registration fields, reconnect/disconnect and denial/expiry. Include AI-provider connections.
- [ ] Validate safe browser return and server-status reconciliation for each flow, including local/prefixed deployments. Resume an existing authorization after suspension instead of starting a duplicate; never assume every flow returns via an app callback.
- [ ] Verify integration parity and coordinate output-form integration with the 3B owner. Astra reviews workflows and auth completion evidence, Sol fixes, commit 7B.

## Milestone 8 — AI assistant and editor integration

**Files:** `Sources/Transport/SSEDecoder.swift`, `Sources/Domain/AssistantService.swift`, `App/Features/Assistant/`, editor action bridge, SSE and conversation tests.

**Interfaces:** `AssistantService.events(request:) -> AsyncThrowingStream<AssistantEvent, Error>` with typed text/status/tool/question/warning/done events plus tolerant unknown events. Server determines tools; native app renders/answers prompts and stages document changes as required by existing semantics.

- [ ] Write chunk-boundary, UTF-8, multi-line SSE, malformed event, interrupted stream, cancellation and duplicate-tool prevention tests.
- [ ] Adapt TV framing code, modernize deprecated endpoints, implement conversation/history/configuration plus global/editor presentations.
- [ ] Map editor effects to typed document actions and draft diffs; never port DOM selectors or web choreography literally.
- [ ] Test task lifetime through fold, keyboard, navigation and background; no automatic POST replay after uncertainty. Reconcile server state before offering retry.
- [ ] Verify all question/tool/save/approval flows from parity ledger; Astra reviews mutation safety and native UX, Sol fixes, commit.

## Milestone 9 — Complete administration and parity audit

**Files:** `App/Features/{Settings,Account,Diagnostics}/`, service adapters, import/export file handlers, `docs/parity.md`, admin integration/UI tests.

**Interfaces:** All settings/admin operations use ledger-specific outcomes and authorization; account/session mutations obtain fresh CSRF context. Backups use documented streaming/file contracts and platform file import/export.

- [ ] Write tests for session revocation/password changes, failed/partial backups, invalid restore data, disconnected Wi-Fi changes, long updates and restart/shutdown outcome reconciliation.
- [ ] Implement all remaining settings, location/time/MQTT/MCP/AI, account/session/device approval, Wi-Fi, update/rollback, backup/restore, debug/logs/cache/connection diagnostics and help flows.
- [ ] Make destructive operations explicit and recoverable where the server allows; preserve actual scope and do not promise rollback for irreversible actions.
- [ ] Complete all fourteen locales and native equivalents for browser-only behaviors; verify import/share/deep links and cancellation.
- [ ] Audit every parity row against running app and integration evidence; zero silently deferred functionality. Astra reviews the whole app and fixes are completed before release preparation.

## Milestone 10 — TestFlight and App Store release readiness

**Files:** `docs/release/{checklist,review-access,privacy,test-matrix}.md`, asset catalogs, privacy manifest, CI archive configuration, `scripts/test-simulator-matrix.sh`.

- [ ] Run the complete package, contract, integration and UI suites against minimum/current server releases and auth/topology variants.
- [ ] Test physical iPhone/iPad networking and available Duo hardware; use Duo simulator/Device Hub for every supported pose and resizing transition. Record gaps rather than claiming simulator coverage equals hardware validation.
- [ ] Exercise scene restoration, concurrent windows, offline errors, large libraries/canvases, energy/memory, VoiceOver, Dynamic Type, reduced motion/transparency, increased contrast and keyboard/Pencil.
- [ ] Resolve Apple team/bundle identity, pricing and store ownership; prepare accurate privacy declarations, support/privacy URLs, licensing and signing/archive checks.
- [ ] Prepare maintained reviewer access with virtual outputs, complete walkthrough and physical-device interaction video; optional full demo mode must label simulated output.
- [ ] Run TestFlight, triage actual feedback, then Astra reviews release diff plus complete evidence. Sol fixes blockers; re-run affected suites and integrated smoke tests.
- [ ] Prepare the submission package; publish only when the user instructs release. No current planning step publishes anything.

## Test commands and review evidence

Once milestone 1 creates the targets, CI must support these commands:

```sh
swift test --package-path Packages/FiestaBoardKit
swift test --package-path Packages/FiestaBoardRender
python3 scripts/check-contracts.py
xcodebuild -project FiestaBoard.xcodeproj -scheme FiestaBoard -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
scripts/test-simulator-matrix.sh
```

Render package UI-only tests run through iOS schemes if they cannot run as host Swift tests; the milestone must encode that split explicitly in CI. The simulator script discovers available devices/runtimes and fails when a required test configuration is missing. Integration tests target disposable servers only. Each commit/milestone includes commands, exit results, relevant screenshots and unresolved findings. Tests are defined by behavior and failure modes, not implementation mirrors.

## Agent scheduling and cost control

Run 0 → 1 → 2 serially to settle shared contracts and prove the editor approach. Then run 3A control and 7A schema foundations independently. After 7A, 3B displays and 7B integrations consume its accepted contracts. Document/editor (4) and collections/schedules (6) may run independently once their common domain interfaces settle; canvas (5) depends on 4, AI (8) depends on 4 and the OAuth foundation where used, administration (9) integrates all feature milestones, and release (10) follows full parity. Integration fixes and app/project wiring have one owner. Select at most two ready implementation tracks at any time.

Use **GPT-6.1 Sol, high reasoning** for implementation/investigation. Use **GPT-6 Astra, high reasoning** for contract/security/editor review and integrated milestone/release reviews. Give reviewers diffs, acceptance criteria and test evidence with a bounded source map, not the full conversation. Batch minor related tasks into coherent deliverables; avoid an expensive Astra call for every small file. Keep at most two implementers plus one reviewer/integrator active. Reuse the implementer for fixes; substantial fixes receive independent re-review.

The highest-cost areas are editor/canvas parity, schema-driven integration/output forms, API stabilization and real-device pose/accessibility QA. Assess throughput after milestone 2 before committing to a release date. Full parity is a substantial native product, not a styling exercise.
