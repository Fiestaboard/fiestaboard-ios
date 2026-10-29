# Native Parity Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver and verify the complete native equivalent of FiestaBoard's web app, starting with finding/signing into/controlling the user's board and ending with a reproducible, release-ready universal app.

**Architecture:** Continue the approved SwiftUI client and server-owned runtime. Typed version-bounded adapters, deployment-scoped sessions, scene/document contexts and lossless local drafts connect native feature screens to existing APIs. Deliver vertical slices with isolated fixtures, independent review and real-device acceptance.

**Tech Stack:** Swift 6; iOS/iPadOS 26 minimum; repository toolchain Xcode/SDK 27.1; SwiftUI with selective UIKit/TextKit; URLSession/Network/Keychain; local Swift packages; Python contract tooling; isolated Docker backend tests; gh CLI.

**Spec:** [Native parity completion design](../specs/2026-10-28-native-parity-completion-design.md), extending the [approved original design](../specs/2026-10-25-fiestaboard-ios-design.md).

## Global Constraints

- Full web parity before the first App Store release; milestones are testable drafts, not reduced-scope release approval.
- Proposed reference 10.1.17/source `b5eac069dce10945eac61e1fdadf6ee4a903ba08`; current installed test version is unverified. Preserve 10.0.0 baseline and scoped 10.1.7 evidence separately.
- First test deployment `http://fiestapi.local:4420`; no credentials in source/docs/logs. Current read-only probe returned No route to host; networking/device interaction must resolve it.
- User-approved Swift/native Apple design, universal iPhone/iPad and all useful actual available geometry/input poses; no invented hinge APIs or hardware claims.
- Sol 6.1 implements; Astra independently reviews substantive auth/editor/concurrency changes, integrated milestones and release. At most two implementers plus integrator/reviewer. Opus CLI may contribute when authenticated; never claim an unsuccessful attempt contributed.
- Preserve user signing changes and dirty backend work. Do not regenerate the user's main project during normal builds. All backend imports/tests run in isolated Docker.
- Per-operation capabilities; no blanket version >= authorization. Original revisions, omitted/null semantics and unsupported-field protection remain mandatory.
- No automatic replay of ambiguous mutations, device effects, OAuth enrollments or AI turns. Server acknowledgement is not physically observed output.
- Follow [master checklist](../../native-parity-checklist.md); each accepted item gets commit/source/test/runtime/reviewer evidence. Do not mark old test results as fresh.
- The user approved this plan on October 28 for continuous end-to-end execution. Retain the chosen Sol/Astra execution method; do not pause between routine implementation tasks.
- Rich editing must support both split-flap and LED with separate source-backed rich/plain/IME/undo/preview/save/conflict/recovery/resize acceptance. Raw-only LED is not accepted.

## Review Focus

1. A current server connects successfully but its board controls remain disabled because different operations use different version/protocol gates. Pin in W0/W1 compatibility-policy tests and the physical J0 journey.
2. Same host with different port/prefix, changed install identity or a second scene inherits another deployment's cookie/draft/target. Pin in W1 session/context tests and W12 multiwindow UI tests.
3. A timeout/cancel arrives after the server applied a change; relaunch/reconnect refreshes a revision and replays stale work. Pin in every mutation adapter, especially W1/W2 controls, W5/W6 editing and W10 tools.
4. Preview/plugin/OAuth/SSE results arrive after server/resource/draft changes or partial failures. Pin request-generation tests in W4/W5/W7/W8/W10 and scene-switch integration tests.
5. A form/canvas/calendar appears correct in an ordinary simulator size but loses IME/focus/undo/required actions under keyboard, large text or resize. Pin W5 editor feasibility tests, W6 accessible calendar alternatives and W12 runtime geometry/input acceptance.

## Execution contract

This is the whole-program plan, not pretend finished API design for features whose current contracts are not yet refreshed. All waves below have concrete deliverables and acceptance IDs. At each wave boundary, the integrator freezes exact DTOs/signatures/fixtures and writes the small task briefs before delegation; the master checklist remains the complete scope. A task is complete only after its own implementation, negative tests, build and review. A milestone also needs the stated runtime/device proof; if it is blocked, mark that proof blocked and continue independent authorized tasks.

Each task follows: (1) read listed source/contracts; (2) add a behavior regression/fixture that fails meaningfully where appropriate; (3) implement the bounded result; (4) run relevant tests/build; (5) obtain Astra review/fix/recheck; (6) commit and link evidence. Do not add tests that only repeat a reversible copy edit. Do not wait for every provider/device to implement the next unrelated feature.

## Ownership and file map

Existing files/packages stay authoritative. New names below are proposed file boundaries to freeze in each wave brief; they are not claims that code already exists.

| Owner | Existing touch points | New focused units |
| --- | --- | --- |
| Contract owner | Contracts/*.json; Fixtures/contracts; Tests/Contracts; Tests/Integration; scripts/{contract-backend,export-openapi,check-contracts}.py | current source manifest, operation fixtures, snapshot migration/evidence tooling |
| Kit/connection owner | FiestaBoardKit/{DeploymentURL,Transport,Service,Models,FiestaBoardError}.swift | Bootstrap.swift, ServerDiscovery.swift, SessionVault.swift, ServerCatalog.swift, CapabilityPolicy.swift and corresponding package tests |
| App integrator | App/FiestaBoardApp.swift; FiestaBoardAppState/BoardStore.swift; project.yml/project.pbxproj; Info.plist; UI tests | Features/Connection; AppState/ConnectionModel.swift; typed AppRoute/scene restoration; split root feature views |
| Content owner | Documents and EditorState packages; App/Features/Editor,Library,Collections | focused page/collection/schedule repositories/edit state; editor bridge and feature views |
| Rendering owner | App/BoardOutputView.swift; AppState/BoardTables.swift | shared rendering models/views/golden fixtures, LED/panel/canvas presentation |
| Schema/integration owner | Kit transport/domain boundaries | SchemaForm state/views; Features/Integrations; OAuth flow coordinator and browser adapter |
| AI/settings owner | Kit transport; AppState resource contexts | SSE parser/chat state; Features/AI; Features/Settings,Account,Diagnostics |
| Reviewer/integrator | TASKS.md; checklist; docs/research | dated evidence, runtime test plans, CI and release runbooks |

Never assign two agents the same shared file. The integrator owns root navigation, Store public API and project generation. Parallel tasks consume a frozen shared interface and own disjoint files. Reuse the isolated foundation worktree if clean; no new worktree needed merely to write another plan.

## Dependency and delivery order

| Wave | Runnable result | Requires | Parallel opportunity | Exit acceptance |
| --- | --- | --- | --- | --- |
| W0 | Current audited contracts, owned ingress feasibility/integration and reproducible project/CI | current source archive | contract refresh, ingress and repository/bootstrap audit | F0; inventory integrity with release gate still red; actual ingress proof may remain externally blocked |
| W1 | Find server → sign in → select board → send → reopen/logout | bounded W0 auth/control contracts | discovery/catalog vs session/bootstrap after interfaces freeze | J0; real iPhone journey |
| W2 | Complete Home controls/override/held/silence state | W1 | remaining Home UI vs independent output-schema research | home/control rows; state-matrix proof |
| W3 | Empty install → configured physical/virtual outputs | W1 + schema vocabulary | schema engine vs output wizard after schemas freeze | displays/setup rows |
| W4 | Faithful previews and panel viewer | W0 geometry + W3 models | flap/charset vs LED/canvas fixtures | renderer golden parity and viewer journey |
| W5 | All pages/Picks/sharing/rich/cell/canvas editors | W1,W3–W4 + document protocols | library CRUD vs TextKit feasibility; later disjoint canvas tools | full page/edit/import/display/export journey |
| W6 | Collections + schedules/defaults/silence/calendar | W1/W4 + revision adapters | collection acceptance vs schedule model/form | J1 collection/schedule journeys |
| W7 | Integrations/instances/forms/options/marketplace/helpers | W3 schema + W1 | catalog/actions vs specialized form widgets | configured plugin → variable → rendered output |
| W8 | Four provider authorization families and recovery | W1 sessions + W7 connection identities | fixtures vs native browser UI | each real flow and manual rescue |
| W9 | Account/sessions/device approvals/MCP | W1 headers/session context | account forms vs device/MCP after CSRF freezes | account/session cross-scene journey |
| W10 | AI configuration/stream/history/staging | W5,W7–W8; SSE transport | parser/history vs transcript/staging on frozen events | approved tool → staged diff → conditional save |
| W11 | Full settings/admin/network/backup/update/power/help | W1,W3 schema + revisions | independent settings groups | disposable-host admin/recovery journeys |
| W12 | Every workflow adaptive/accessibility/localized/lifecycle accepted | continuous from W1, final sweep after W11 | locale/resources vs device acceptance | Q0 and all native cross-cutting rows |
| W13 | Reproducible signed candidate/TestFlight/release evidence | all parity + W12 | assets/privacy vs final acceptance | R0; genuine release-readiness gate |

W9 can begin after W1 without waiting for W8; W11 independent settings can begin after shared schema/session work. W6 may run beside bounded W5 tasks when resources/files are disjoint. W12 is work in every wave, with a final sweep; it is not a postponed accessibility retrofit. Keep the first useful iPhone milestone ahead of broad administrative implementation.

## Task W0-A: Refresh current-web source and contracts

**Files:** modify Contracts inventory/checker and tests; create current source/fixture evidence in docs/research and Fixtures/contracts; preserve archived original evidence.

**Consumes:** exact upstream source commit and original 81-row/198-operation mapping. **Produces:** reviewed current route/workflow/operation ledger, exact candidate capability inputs, and runnable isolated fixtures for subsequent tasks.

- [ ] Re-export schemas in Docker and diff current routes, API clients, direct fetch/SSE/download/upload/browser/provider paths against the original baseline.
- [ ] Add fixtures for current auth/status/discover/version, board list/detail/message/restore/PATCH, page/document/collection/schedule/default revisions, errors and geometry.
- [ ] Migrate checker source/evidence handling with tests rejecting stale/wrong-source hashes, missing reciprocal mappings and unsupported status flips.
- [ ] Verify filled 71/editor and plugin-cache/breaker deltas plus newly enumerated color-rule/JSON-mapper/schema widgets.
- [ ] Run Tests/Contracts, integrity and isolated current-source behavior suite; Astra accepts exact adapter scope before version gates change.

## Task W0-B: Make the project reproducible and automate checks

**Files:** README.md, Tests/Integration/README.md, scripts/build-draft.sh, project.yml, shared schemes, proposed scripts/bootstrap-contracts.py and .github/workflows/native.yml.

**Consumes:** W0-A source manifest and existing committed project. **Produces:** fresh-clone runbook/bootstrap, normal/demo schemes, CI artifacts and a signing-preserving project check.

- [ ] Record tools/dependencies/source download/image build path; verify without local substrate tags, .reference or .build.
- [ ] Add normal onboarding versus explicit demo/test schemes; verify archive/profile arguments.
- [ ] Add package/contract/build and actual UI-runtime jobs on compatible runners; isolated Docker jobs use disposable state only.
- [ ] Compare project generation in a disposable copy so normal builds never overwrite user Team settings.
- [ ] Execute clean checkout proof and record any unexecuted CI/device requirements honestly.

## Task W0-C: Authenticated ingress access and native integration

**Files:** Tests/Integration topology/auth fixtures and runbook; Kit deployment/transport/session boundary; proposed Features/Connection/UpstreamSignInView.swift only if a browser bridge is required; dated topology evidence.

**Consumes:** actual HA deployment/access configuration when available, W0-A auth contracts and the existing proxy-path fixture. **Produces:** a reviewed authorized native access route or a tested upstream-authentication/browser-bridge implementation, plus an explicit externally blocked physical proof if real ingress access is unavailable. This has a named connection/transport owner; it is not merely a late QA request.

- [ ] Inspect actual upstream login/redirect/cookie/session/CSRF requirements; distinguish HA browser authentication, FiestaBoard login and a separately operator-exposed native endpoint.
- [ ] Compare feasible authorized native access routes using real configuration; do not infer that Web browser login automatically transfers cookies into URLSession or disable TLS/origin protection to make it work.
- [ ] Build the chosen route/bridge in the native connection lifecycle when needed, including return/resume, expiry/logout, prefix and credential isolation; if infeasible without upstream API work, identify the exact gap and propose that bounded change.
- [ ] Test local authorized/denied/expired/cross-origin proxy cases without real credentials and obtain Astra auth-boundary review. A rewriting-only fixture still cannot satisfy actual HA acceptance.
- [ ] Complete actual HA authorization/reconnect proof with its operator when access is supplied; otherwise keep Q0-16/I0-05 blocked and continue direct-LAN W1 and unrelated waves. No silent HA parity exemption.

## First-slice interface decisions

Freeze these planned interfaces in the W1 briefs after W0 source fixtures; new DTO field definitions must match that evidence. Existing service call sites remain compatible until the integrator migrates them.

- Bootstrap adapter: `bootstrap() async throws -> BootstrapSnapshot`; result distinguishes identity/health/auth/setup/capability state, not a single connected Boolean. Named auth-status fields remain server-derived.
- Discovery boundary: `ServerDiscovering.candidates() -> AsyncThrowingStream<DiscoveredServer, Error>` with cancellation ending the browse; DiscoveredServer carries the normalized deployment candidate and discover identity, never a trusted session.
- Saved servers: `ServerCatalog.list() async throws -> [SavedServer]`, `upsert(_ server: SavedServer) async throws`, `remove(id: UUID) async throws`; SavedServer includes deployment identity, optional observed installation ID, display alias and preferred board, no password/cookie.
- Secret boundary: `SessionVault.load(for: DeploymentURL) async throws -> Data?`, `save(_ material: Data, for: DeploymentURL) async throws`, `remove(for: DeploymentURL) async throws`; opaque versioned cookie/session material is only produced/consumed inside transport/session code, not UI or documents.
- Auth boundary: add explicit `rememberMe: Bool` login without breaking existing mocks; separate preference/setup input DTOs; cookie snapshot/import obey generation, expiry, domain/path/Secure and deployment association.
- Capability policy: `CapabilityPolicy.evaluate(version: VersionInfo, protocols: Set<String>) -> ServerCapabilities`; ServerCapabilities is per operation and combined with session opt-in/resource original context, never a global write-enabled shortcut.
- Scene connection model exposes states for server selection, browsing, bootstrap/setup/login, loading/connected and recoverable error; generation rejects late connection results. BoardStore retains immutable target/document context behavior.

## Task W1-A: Bootstrap, error taxonomy and bounded transport headers

**Files:** Kit Bootstrap.swift, Transport.swift, Models.swift, FiestaBoardError.swift; BootstrapTests.swift/TransportTests.swift; isolated auth fixtures.

**Consumes:** W0 auth/discover/version/error fixtures. **Produces:** BootstrapSnapshot, typed auth/onboarding replies, scoped header/cache policy and preserved structured errors for later connection/admin/stream adapters.

- [ ] Add failing cases for healthy/no boards, startup 503, auth disabled/undecided/setup/login-required, JSON versus gatewayHTML,401/403/domain 409/412/429 and partial 502.
- [ ] Implement unauthenticated health/discover/auth-status before protected reads; retain server error detail without exposing credentials.
- [ ] Extend transport for explicit endpoint headers/no-store and exact Origin without accepting arbitrary credential override/cross-origin redirect. Fresh CSRF consumers arrive in W9.
- [ ] Test slow/cancelled bootstrap and switched server; optional library/state failures cannot turn successful login into an unusable shell.
- [ ] Run Kit/contract tests and device build; Astra review auth/error/credential boundaries.

## Task W1-B: Find and remember servers

**Files:** Kit ServerDiscovery.swift/ServerCatalog.swift/DeploymentURL.swift plus tests; App/Info.plist; Features/Connection/ServerPickerView.swift.

**Consumes:** W1-A identity DTOs and DeploymentURL. **Produces:** cancellable verified discovery candidates and a non-secret saved-server catalog.

- [ ] Add failing discovery/catalog cases for actual _http._tcp TXT filtering, unrelated HTTP services, duplicate/stale candidates, IPv6/ports, missing multicast and cancellation.
- [ ] Implement user-initiated browse → resolve → public discover verification, with manual/paste fallback and truthful permission troubleshooting.
- [ ] Add NSBonjourServices for the real service and local-network purpose; retain deliberate bounded localHTTP handling and system TLS validation.
- [ ] Test duplicate deployment normalization, changed installation identity, rename/edit/remove/preferred board and no secret serialization.
- [ ] Build UI and execute discovery/manual entry on real iPhone when accessible; preserve a pending physical case if environment cannot reach LAN.

## Task W1-C: Remember sign-in securely

**Files:** Kit SessionVault.swift/Transport.swift/Service.swift plus vault/cookie/session tests; AppState connection lifecycle and tests.

**Consumes:** per-deployment identity, bootstrap and validated server cookie/login behavior. **Produces:** explicit remember-me login and secure session restoration without storing a password.

- [ ] Add failing cases for no-consent memory-only mode, persisted session expiry, replaced cookies, wrong prefix/port/server, revoked account and locked/unavailable Keychain.
- [ ] Implement versioned cookie/session export/import under the vault boundary; cache is not authority, so revalidate bootstrap/auth on reopen.
- [ ] Separate logout/local disconnect/app termination; handle pending unreachable remote revocation and clearing all relevant scene/vault state.
- [ ] Test late login/logout, app restart, second window and credential isolation; reconnect never makes an old dirty draft writable.
- [ ] Astra reviews Keychain/cookie/generation boundaries; run auth contract, Kit/AppState and available lifecycle UI tests.

## Task W1-D: Native connection/onboarding flow

**Files:** Features/Connection/{ConnectionView,SignInView,SetupView}.swift; AppState/ConnectionModel.swift/tests; App/FiestaBoardApp.swift; UI connection tests.

**Consumes:** W1-A/B/C public interfaces. **Produces:** cold-launch server picker → bootstrap → setup/login → connected shell with safe intended route and explicit demo entry.

- [ ] Add UI/state cases for browse/manual entry, current test address, empty server/boards/library, wrong credentials/rate limit, setup preference and disabled auth.
- [ ] Implement validated address/identity/transport display, login/Remember sign-in, supported setup-token proof UI where required and actionable errors/cancel.
- [ ] Integrate persistent server/preferred-board selection and window state without restoring passwords or enabling mutations implicitly.
- [ ] Test keyboard/large text/focus/VoiceOver and rotation during login; remove stale capability copy as its owning features are integrated.
- [ ] Build normal/demo schemes and record actual UI runtime versus compilation evidence.

## Task W1-E: Current-version control policy and one complete send

**Files:** Kit CapabilityPolicy.swift/Service.swift/BoardControls.swift plus tests/fixtures; AppState BoardStore/tests; Home/control UI.

**Consumes:** W0 exact current command fixtures and W1 connection context. **Produces:** separately accepted board-message/selection/restore/configuration capabilities and immutable control results on the tested candidate.

- [ ] Add failing matrix for original 10.0.0, new audited candidate, scoped preview/collection capabilities, development/unknown releases, missing protocol and disabled opt-in.
- [ ] Implement only accepted per-operation support; include current-version collection creation/preview adoption where independently proven.
- [ ] Test target switch/primary change, pause/silence/held/refused/partial/malformed/timeout-after-apply and authentication loss after acknowledgement.
- [ ] Keep conditional defaults and schedule flags on their actual revision-safe contracts rather than mechanically using board PATCH for all settings.
- [ ] Astra reviews; run Kit/AppState/contract tests, app builds and one real J0 send/readback with the user at the correct moment.

## Task W1-F: Prove the complete first journey

**Files:** Tests/UITests connection/control suites, docs/draft-testing.md and new dated J0 evidence/runbook.

- [ ] Run J0 in isolated virtual-board fixtures, then actual normal-scheme app on iPhone against the confirmed installed test version.
- [ ] Resolve fiestapi.local reachability/local-network permissions with the user; inspect installed identity/version without publishing credentials.
- [ ] Complete find/login/select/read/confirmed-send/physical-observation/reopen/logout; no hardware step runs implicitly during CI.
- [ ] Repeat narrow iPad/window and accessible connection/control path; mark individual blocked cases while continuing W2/W3 independent work.
- [ ] Record runnable build instructions, reviewed commits and exact passed/unexecuted cases; integrate preserving all user signing settings.

## Remaining reviewable work packages

Each package below gets a bounded wave task brief, exact current DTOs and tests before code, using the execution contract above. Its checklist IDs supply full field/state acceptance; a package cannot be marked done just because its primary screen exists.

| Task | Files/units to create or extend | Consumes → produces | Required behavioral proof |
| --- | --- | --- | --- |
| W2-A Home/state | Kit home/control models; BoardStore; Features/Home | W1 control contexts → independent current/selected/scheduled/held/silence/service state | all home_state/home_commands states; optional read failure, stale reads, acknowledged write/readback loss |
| W2-B Overrides/control completion | Kit override/silence/service adapters; Features/Control | W2-A states → temporary/indefinite overrides, discard/refresh/start-stop/restore | temporary_override/board_control; duration/expiry/revert, unknown results, current target |
| W3-A Schema foundation/output widgets | typed schema state/tests; SchemaForm and board-widget views | source manifest/widget fixtures → reusable secret-preserving forms sufficient for complete output setup | nested arrays/objects, required/default/enum/null, sections/visible_when, mask/preserve/clear, timezone/page pickers, mode-cards/device-picker/tile-grid with draft/saved actions/returned fields/tile coordinates/uniqueness/geometry, dependent paginated remote options/current labels and stale cancellation; unsupported-widget explanation |
| W3-B Physical outputs/setup | output repositories; Features/Displays/Setup | W3-A → catalog/models/board setup/actions/configuration | board_configuration/board_setup/output_catalog/output_actions/output_board_creation/wizard_state; empty install through tested board |
| W3-C Panels/retarget | panel adapters/views and invalidation tests | geometry/action models → panel CRUD/presentation settings | panel_configuration; reference/retarget warnings, partial conversion and independent stale drafts |
| W4-A Renderer models/flap | BoardTables/BoardOutputView; renderer fixtures/tests | server-render output/charset → faithful model-specific draw data | glyph 62/filled 71, Note arrays, pigments, blank/unknown/malformed/oversize frames; screenshot/golden comparison |
| W4-B LED/canvas/white-board | renderer units/resources; panel viewer UI | W4-A normalized target data → spans/icons/fonts/pixel-layer composition | page_preview/panel_viewer/panel_presentation/panel_link_sharing; layers/scale/bleed, external viewer prefix, thumbnail and fullscreen |
| W5-A Page library/lifecycle | Kit page repository, Documents, Library/Picks/share UI | revision/document adapters → create/delete/duplicate/import/export/share/Picks | pages_crud/page_sharing/staff_picks/page_library_navigation; missing dependencies and ambiguous create/import |
| W5-B Rich editor feasibility | Documents/EditorState; UIKit bridge tests/view | lossless split-flap and LED docs → proven rich/plain/token/IME/caret/undo boundary for both | editor_document/editor_undo/template_authoring; separate split-flap/LED canonical round trips, supported output-specific formatting, token-adjacent/multiline/CJK/resize; choose alternative only if prototype fails |
| W5-C Full template/cell editor | EditorState + focused editor controls | accepted bridge, charsets → every text/cell/line editing action | editor_charset/template_authoring/editor_drafts; field preservation, geometry warnings, accessibility, interruption recovery |
| W5-D Canvas tools | canvas state/tests; Draw/Shapes/Source/management views | W4 rendering + W5 documents → eight-canvas authoring | canvas_management/canvas_draw/canvas_shapes/canvas_source; Pencil/touch/accessible cursor, undo and exact clear semantics |
| W5-E Preview/live/save integration | preview coordinator, conditional save/conflict UI | all editors → explicit preview/live mode and complete conditional save | page_preview/template_live_output; out-of-order renders, no silent live send, server-compare no retokening, local cleanup failure after ack |
| W6-A Collections completion | existing CollectionEditing/EditorState/Collections views | current contract + reviewed draft → full runtime accepted collections | collections/collection_rules_editor; schema duration reconciliation, member resolution, target selection, all recovery probes and UI accessibility |
| W6-B Schedule/default model | schedule adapters/draft state/tests | original schedule/default protocols → CRUD/toggle/form/validation | schedule_entries/schedule_validation; original tokens, explicit null, web/native both save orders, restore/recreate |
| W6-C Calendar/silence | calendar/list forms; silence/default UI | W6-B → recurrence/calendar/drag/accessibility/silence workflows | calendar_interaction/silence_configuration; DST/sun/overnight/polar/overlap/gap/default transitions |
| W7-A Integrations/instances | plugin repository; Integrations views | W3-A schemas → plugin/instance/config/variable/data/error/demo UI | plugins_configuration/plugin_instances/plugin_demo; scope isolation, color rules, cache/breaker recovery |
| W7-B Plugin options/mapper/helpers | plugin option contexts; JSON mapper/helper views | W3 complete shared form/options/output-widget primitives → instance-specific options/JSON mapping/integration helpers | plugin_options/integration_helpers; plugin-specific stale search/context, mask preservation, current labels and typed sample data; W3 output creation has no dependency on this task |
| W7-C Marketplace/docs | install/update repository; catalog/doc viewers | plugin schemas/action outcomes → registry/Git install/update/remove/readme | plugin_marketplace/external_plugin_documents; offline/provenance/partial/unknown actions and external cookie isolation |
| W8-A OAuth lifecycle | OAuth domain coordinator/browser adapter/fixtures | W1 sessions + plugin/provider IDs → pending/status/manual completion | oauth_connections/oauth_app_registration; app versus browser sessions, prefix, suspend/resume and saved client settings |
| W8-B Four flow presentations | separate relay/device/key-exchange/Plex states/views | W8-A → real flow-specific UI/poll/browser/manual rescue | oauth_relay_flow/oauth_device_flow/oauth_key_exchange_flow/oauth_plex_flow; real provider/user acceptance for each, no duplicate enrollment |
| W9-A Accounts/sessions | account/session adapter; CSRF tests; Account UI | W1 scoped headers/session → username/password/disable/revoke/list | account_credentials/session_management; fresh CSRF+Origin, replacement cookie/self revoke/all scenes |
| W9-B Enrollment/MCP | device approval and MCP adapters/views | W9-A admin context → activation/enrollment/token/instructions | device_activation/mcp_credentials/mcp_connector_instructions; expired/consumed codes, token gate, one-time plaintext and safe sharing |
| W10-A AI transport/config/history | SSE parser/tests; provider/conversation repositories | W1 transport + W8 provider auth → configuration/history/typed events | ai_configuration/ai_history; byte framing/all events/long history/persistence, no automatic turn replay |
| W10-B Chat/generation/staging | AI state/transcript/staging views; editor bridge | W10-A events + W5 original revisions → global/editor generation/tools/diffs | ai_generate/ai_chat/ai_staging; approvals/questions/cancel race, acknowledged tools after cancel, stale draft comparison |
| W11-A General/display/poll/location/MQTT | settings repositories/forms/tests | W3 schemas + W1 sessions → complete settings groups | general_settings/display_preferences/polling_preferences/location_settings/mqtt_settings/geolocation_permission; shared/local separation, polar/DST, restart/runtime distinctions |
| W11-B Backup/update/power/network | specialized upload/download/admin adapters/views | revisions/connection recovery → all administrative actions | backup_restore/system_updates/system_power/wifi_management; disposable restore/restart/network proof, partial/unknown/no replay |
| W11-C Diagnostics/help | diagnostics adapters/views/export | current server capabilities → diagnostics, explicit clear-message-cache mutation and truthful operator help | diagnostics/removed_debug_monitor; explicit hardware target, cache-clear POST support/outcome/readback/no replay, redacted output, unavailable API explanation |
| W12-A Native routes/lifecycle | typed route/scene persistence; Files/link handling | all feature screens → complete navigation/deep links/offline/install equivalent | route_navigation/deep_links/offline_recovery/pwa_installation; safe login return, deleted resources, cross-scene isolation |
| W12-B Design/accessibility/locales | string catalogs, UI focus/layout tests and theme | all waves → accepted native appearance/input/14 locales | appearance_theme/localization/accessibility/adaptive_device_poses; Q0 full runtime matrix |
| W13-A Distribution/assets | assets/privacy/notices/production configs/CI archive | accepted native workflows → signed reproducible candidate | R0 fresh clone, archive/install/update, privacy/ownership/license checks, maintained review access |
| W13-B Integrated release acceptance | supported-source evidence, checklist, TestFlight/runbooks | every prior acceptance → independently reviewed release artifact | --release-ready, real provider/topology/physical evidence, feedback closure; user final publishing decision |

## Verification commands and evidence

Use existing repository tooling with the exact accepted source/image; W0 updates source pins deliberately. Swift package command pattern: `swift test --package-path Packages/<package> --disable-sandbox` with writable task-specific module/scratch caches when this environment requires them. Run Kit/AppState/Documents/EditorState plus any new package. A suite passes only when the process exits 0 and reports the expected cases, not from log-file presence.

Run `python3 -m unittest discover -s Tests/Contracts -v`, `python3 scripts/check-contracts.py`, appropriate Docker-backed contract/fixture commands, and `scripts/build-draft.sh simulator`/`device`. UI runtime requires `xcodebuild test` with an actually available named device/runtime; `build-for-testing` is compilation evidence only. Do not invent a Simulator ID. Signed install/archive is a separate device/distribution check.

Every milestone evidence file records exact commands/toolchain/results, code/server commits/hashes, Astra verdict, observed UI/device/window/network and pending cases. Include Q0 regressions for every feature added. No production hardware/providers are contacted by automated isolated tests. When interactive runtime is unavailable, build and host proofs proceed, and the runtime checklist stays open.

## User interactions and continuation

The current blocking external fact is routing to `fiestapi.local:4420`, not app credentials. Obtain actual reachability/installed version during W1; do not block contract/UI implementation while waiting. Device prompts, physical-board observations, actual provider logins and authenticated HA topology require concrete prepared runbooks/builds. Repo/Apple ownership and final store assets are later inputs. Credentials stay outside documents and CI.

At each accepted wave update TASKS.md with current commit, checked evidence, exact blocked cases and next independent package. A blocked provider/device never justifies marking parity complete or stopping unrelated authorized work. Preserve the user's execution choice; after plan approval, continue without repeated permission requests for routine reversible implementation, review or integration. Publishing/deploying production remains a concrete separate action.

## Plan self-review and handoff

- [x] All 81 original workflow IDs occur in the master checklist and map to work packages; refreshed source additions are reconciled by W0-A.
- [x] First-controller journey includes actual current-version gates, reachability, discovery/login/secure reopen/logout and real output proof.
- [x] All five review-focus conditions have named task tests; source-only/UI-compiled evidence cannot close runtime requirements.
- [x] File ownership prevents concurrent edits to transport/Store/root/project; interfaces freeze before parallel delegation.
- [x] Astra builder check and independent completeness review resolve substantive planning gaps; user-only inputs are listed with an unblocked next task.
- [x] User approved the plan/order on October 28 and explicitly required split-flap plus LED rich editing. Sol/Astra executes continuously; later task briefs refine how, not full-parity scope.

Independent planning review: [Astra initial findings and final PASS](../../research/2026-10-28-parity-plan-review.md). No product implementation is accepted by these self-review checks.
