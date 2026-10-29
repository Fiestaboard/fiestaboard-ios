# FiestaBoard iOS remaining work

This is the short current queue and durable milestone history. Full web-app feature parity is required before the first App Store release. Checkboxes mean the whole listed deliverable is accepted, not that a draft screen exists. `Contracts/parity.json` remains the source-bound release inventory; source/fixture tests alone do not make a workflow release-verified.

## Current status — October 28, 2026 (resumed)

The user resumed execution with a quality-first order: **setup/sign-in → board switching and page management → settings → rich content editing for both split-flap and LED**. Root drives implementation with bounded Sol 6.1 assistance and independent Astra review. Full web parity remains the release requirement.

- Working branch: `codex/ios-foundation` in `.worktrees/foundation`. Main is integrated through `1891aca`; all21 existing signing/project changes were preserved by a checked three-way merge. Further test-only corrections are in progress.
- Source-bound bootstrap/discovery/catalog/session work and native onboarding corrections are reviewed. Current controls support exact nondevelopment10.0.0/10.1.17/10.1.20 with explicit session opt-in. Current fallback-page changes use the original revision and concrete board; Demo/legacy paths are explicit.
- Test server discover now reports10.1.20. CLI curl and Simulator services are available again. A standalone macOS URLSession probe gets network-unavailable; this is not evidence of successful native live login. Credentials remain out of repository/logs.
- Fresh source evidence:72 current control cases plus57 bootstrap cases replayed against10.1.20; Astra accepted bounded compatibility. Kit124 and AppState76 tests pass after review corrections. No physical send or supported release pairing is claimed.
- Actual iPhone Simulator first-run administrator setup passed. Wrong-password recovery, rotation, Keychain-backed remembered sign-in across process restart and logout passed with a locally signed Simulator build. Unsigned Simulator builds cannot access Keychain; UI CI now signs locally. AccessibilityXXXL setup now passes on phone and iPad. The iPhone create-LED → editor → delete journey passes. Full integrated suites are in progress; iPad automation geometry corrections do not establish device acceptance.

| Priority | Scope | Remaining acceptance |
| --- | --- | --- |
| 1 — Setup | Find/manual/saved server, setup choice/admin, sign-in, remember/reopen/logout | Full phone/tablet UI run, LAN discovery permissions, actual iPhone walkthrough and live server connection |
| 2 — Board control | Select/read board, current-version send/page choice, pause/schedule/restore, revision-safe fallback | Integrated UI checks, live target selection/send with physical observation, full output rendering |
| 3 — Page management | Create split-flap/LED templates, open editor, revision-safe delete and retained recovery are implemented/reviewed | Phone journey passed; complete tablet acceptance, actual-server walkthrough, import/export/compatibility browsing remain. [Gap audit](docs/research/2026-10-28-page-management-gap-audit.md) |
| 4 — Settings | Server/preferences, accounts/sessions, integrations, display configuration and administration | Implement source-backed settings flows and their complete acceptance matrix |
| 5 — Rich content editing | Native rich editing for **both split-flap and LED** | Rich/plain round trips, selection/IME/paste/undo, server preview, revision-safe save/conflicts/recovery and adaptive accessible UI |
| Remaining full parity | Schedules, collections completion, canvas/rendering, OAuth/plugins/AI/HA and release | All84 workflows/199 operations and364 human checks remain tracked in the master checklist |

The [complete checklist](docs/native-parity-checklist.md), [design](docs/superpowers/specs/2026-10-28-native-parity-completion-design.md) and [execution plan](docs/superpowers/plans/2026-10-28-native-parity-completion.md) retain the full scope. [The prior pause handoff](docs/NATIVE_CLIENT_HANDOFF.md) is historical; its paused instruction was lifted by the user's resume request.

The latest page slice (`4c14eb8`, `7569cec`, `1891aca`) passed138 Kit and84 AppState tests. Astra accepted the Kit and state/UI fixes. Exact10.1.20 create/delete support is independent of other feature capabilities. Unknown writes retain their input and require explicit readback plus a new user intent; no automatic replay. [Page milestone](docs/research/2026-10-28-native-page-lifecycle-verification.md).

The user ran the app on their iPhone and confirmed connecting/sign-in is much faster when launched directly from the Home Screen instead of through the attached Xcode debugger. Added **FiestaBoard Device Test**, which runs without debugger attachment; regular debugging remains available in the original scheme. Mac API profiling measured login245ms, pages55ms and board reads29–110ms. CLI signing remains unavailable to the agent; this is separate from the user's successful Xcode deployment. Full physical-device workflow/output acceptance is still open.

- [ ] Reduce measured connection overhead without weakening session safety: current unauthenticated selection repeats bootstrap before checking the saved-session vault; remembered restoration repeats it again; initial board listing is fetched twice. Preserve installation identity checks, stale-response exclusion and original-revision guarantees. User-observed debugger slowdown is addressed separately; these redundancies are not claimed as its cause.

## Initial baseline — historical

- [x] Audited 81 web workflows and 198 web API calls; pinned public/internal schemas and integrity/readiness gates.
- [x] Native draft: manual connection/login, isolated memory sessions, Home/Library/Displays/Settings, flap preview, simulated demo, text/page controls.
- [x] Astra reviewed core and integrated draft; 38 Swift and 25 contract-tool tests passed. Unsigned Simulator/device builds and UI-test compilation passed.
- [x] Phone signing blocker diagnosed; signed Xcode artifact verified and build helper fixed to preserve local signing choices. User reported trying the draft; comprehensive device/pose/accessibility acceptance is still pending.

## Active queue

| ID | Deliverable | Status / owner | Dependencies / acceptance |
| --- | --- | --- | --- |
| C-01 | Per-board pause/resume, schedule enablement/defaults, restore controls and faithful demo outcomes | Complete for bounded scope — Astra approved `be72a11` | Exact pinned API; immutable targets; no automatic write retry; host tests, build, Astra review |
| E-01 | Lossless page document model, local draft persistence, native editor feasibility | Complete for bounded scope — Astra approved `be72a11` | Preserve unknown fields/numbers/null/markup; no remote save before revision protocol |
| W1-03 | Integrate C-01/E-01 into the app and review the wave | Complete — built and Astra approved; interactive device checks remain | Preserve user signing edits; device/Simulator compilation; manual UI matrix |
| P-01 | Server revisions and participating-writer conditional saves | Merged in PR [#2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373); native collection candidate pinned to 10.1.7 | Pages, collections, schedules/defaults, web/AI/MCP original revisions, restore/recovery invalidation; compatible unconditional maintenance remains explicit |
| P-02 | Native conditional page saves and explicit conflict handling | Complete for bounded template-edit scope — Astra approved `aa03da7` | Consume reviewed backend protocol; audited release and lossless field contract; never retry stale writes automatically |
| E-02 | Server template validation and render previews | Complete for explicit text/warning scope — Astra approved `aa03da7` | Adapt existing internal endpoints with geometry/charset/canvas fixtures |
| P-03 | Adopt richer backend contracts in native clients | In progress — collection adapters/forms implemented; schedule, rich page and auth adapters remain | Gate rich editing on page-document-v1 plus page-revision-v1; collection/schedule/default protocols; native OAuth/session flows; device acceptance |
| S-01 | Shared schema vocabulary, secret-preserving drafts and native forms | Queued | Required by display configuration and integrations |
| R-01 | Complete LED/pixel/layer/white-board renderer and geometry fidelity | Queued | Shared golden fixtures; actual visual/device checks |

Backend completion evidence and native followups: [2026-10-26-native-backend-readiness.md](docs/research/2026-10-26-native-backend-readiness.md). Backend verification does not check off native workflow acceptance.

Collection milestone evidence and walkthrough: [2026-10-27-native-collections-verification.md](docs/research/2026-10-27-native-collections-verification.md).

## Release milestones still open

- [ ] Finish API behavior fixtures, supported server matrix, native session persistence/discovery/setup, authenticated proxy/HA topology and all four OAuth proofs.
- [ ] Complete adaptive scene restoration, TextKit rich/plain editor feasibility and supported window/device poses.
- [ ] Complete home controls, temporary overrides/silence/held/external frames, output/display setup and schema-driven configuration.
- [ ] Complete page CRUD/Picks/import/export/share, rich/plain editing, tokens/cells/formulas, undo, persistent drafts, preview and revision-safe saves.
- [ ] Complete Draw/Shapes/Source canvas authoring, up to eight canvases, Pencil/accessibility and server-rendered parity.
- [ ] Complete collections, rule editing, scheduling/calendar/recurrence/timezone/DST validation and concurrent-save handling.
- [ ] Complete plugins/instances/options/marketplace/actions and relay/device/key_exchange/plex_pin OAuth, including manual rescue and AI providers.
- [ ] Complete AI streaming/history/tools/questions/approvals and staged editor changes.
- [ ] Complete settings/account/device approval/session management, network/Wi-Fi, backups/restore, update/power/diagnostics and native help equivalents.
- [ ] Complete all fourteen locales, accessibility, deep links, file sharing, offline recovery and external document handling.
- [ ] Complete physical-device testing, performance/energy, release assets/privacy/support, signing/archive, TestFlight and App Store preparation. Publishing remains a separate user action.

## Workflow checklist

Partial means a subset exists in the draft; the checkbox stays open until the entire workflow and its verification are complete.

- [ ] **connection_boot** — Partial draft. Boot health/retry and server identity/configuration; distinguish unavailable server from authentication state.
- [ ] **auth_onboarding** — Partial draft. Authentication undecided/enabled/disabled, first administrator setup, remember-me login, wrong password/lockout, redirect and sign out.
- [ ] **account_credentials** — Remaining. Change username/password and disable authentication with current-password confirmation; surface account generation/session changes.
- [ ] **device_activation** — Remaining. Inspect, approve or deny the entered/QR device code; expiry/denial/error; enable or disable device enrollment.
- [ ] **session_management** — Remaining. List signed-in browsers/TVs; fetch CSRF context; revoke one, all other or all sessions including current.
- [ ] **mcp_credentials** — Remaining. Inspect, rotate and delete MCP token; one-time plaintext display/copy; current-token gate on auth-disabled installs.
- [ ] **home_state** — Partial draft. Read actual remembered output/external frame, selected page and collection resolution, currently scheduled page, silence/held state and service state independently.
- [ ] **home_commands** — Partial draft. Explicit target board message send and restore, discard held send/external frame, service start/stop, force refresh; honor paused/silenced/held/refused/outcome-unknown distinctions.
- [ ] **temporary_override** — Remaining. Temporary or indefinite page/collection/inline compose override, duration, revert to schedule/blank/page, read expiry and cancel/refresh.
- [ ] **board_control** — Partial draft. Per-board pause/resume, default page and schedule enablement through PATCH BoardDetail.
- [ ] **board_configuration** — Remaining. List/add/remove output boards, credentials/API modes, geometry, primary selection, resize/retarget compatibility warnings and settings round trip.
- [ ] **board_setup** — Remaining. Validate first-run setup, scan boards, test connection, enable local API, send welcome message; report scan/probe/device verdicts.
- [ ] **output_catalog** — Remaining. Installed/available/catalog output discovery and marketplace install; unavailable registry/offline seed and network cases.
- [ ] **output_actions** — Remaining. Schema-driven draft/saved-board test/discover/identify/detect-geometry and arbitrary plugin actions, secret result fields and geometry application.
- [ ] **output_board_creation** — Remaining. Choose output model, submit schema settings and geometry, create named output board.
- [ ] **panel_configuration** — Remaining. Create/edit/remove virtual panels, resolve geometry, display/TV/backdrop/auto-dim/matrix/font/sizing/presentation settings and HDMI kiosk capability.
- [ ] **panel_viewer** — Remaining. Read standalone panel configuration/frame with full split-flap/LED rendering and read-only display playback.
- [ ] **wizard_state** — Remaining. Welcome/output/model/connection/panel/easy-plugin setup; skip or complete with durable wizard outcome and reopen.
- [ ] **pages_crud** — Partial draft. Read/list and supported conditional updates implemented; create/delete/duplicate remain. List/get/create/update/delete all single/composite/template page types; duplicate via create; preserve metadata/charset/geometry/transitions/canvases and explicit nulls.
- [ ] **page_preview** — Remaining. Saved page and batch previews, target geometry/LED spans/icons/cells/layers, availability and rendering errors.
- [ ] **page_sharing** — Remaining. Export/copy page share string and import pasted/file/shared content; preserve format and validation errors.
- [ ] **staff_picks** — Remaining. Browse/filter Picks by device, inspect plugin requirements, retrieve share data and import a pick.
- [ ] **collections** — Implemented in the draft: native list/search/create/update/delete, ordered members, time/variable/random modes, rule ordering/fallback/polling, intervals, original-revision saves and durable recovery. Device/pose/VoiceOver acceptance and full release pairing remain unverified.
- [ ] **schedule_entries** — Remaining. Board-scoped schedule CRUD/toggle; weekly/annual/one-off recurrence, day patterns, start/end/sun offsets, page/collection targets and compatibility warnings.
- [ ] **schedule_validation** — Remaining. Calendar/list active resolution, overlaps and gaps, schedule behavior settings and validation.
- [ ] **silence_configuration** — Remaining. Global/per-board silence schedule with overnight windows, indicator/freeze/page, indicator placement, queued-on-exit and explicit nullable page fields.
- [ ] **plugins_configuration** — Remaining. Installed plugin list/detail/manifest, enable/disable, schema configuration, secret masks/preservation, variables, data and circuit-breaker errors.
- [ ] **plugin_instances** — Remaining. List/add/delete named plugin instances; configure and identify instance-specific secrets, variables and OAuth connections.
- [ ] **plugin_demo** — Remaining. Inspect/create plugin demo pages with provenance and idempotent existing-demo behavior.
- [ ] **plugin_marketplace** — Remaining. Registry list/install, Git repository install, update/uninstall, available update checks and bulk application; display progress/errors/provenance.
- [ ] **plugin_options** — Remaining. Dynamic schema remote options, query/search/dependent settings, pagination/current labels, secret-preserving settings context and loading/error/empty cases.
- [ ] **oauth_connections** — Remaining. List status/configuration/scopes/expiry/reconnect reason, start relay/device/key_exchange/plex_pin, complete pasted URL/code, disconnect, browser return and plugin/AI routing.
- [ ] **template_authoring** — Partial draft. Explicit validation/render previews implemented; discovery/rich authoring remain. Variable/function discovery, validation and side-effect-free server rendering with text, tokens, line metadata, geometry, charset warnings and canvas layers.
- [ ] **template_live_output** — Remaining. Explicit live-to-board render with named target, pause/silence/override/held handling; separate saved state from live hardware effect.
- [ ] **integration_helpers** — Remaining. Bay Wheels/Muni station/stop lists and nearby/address search, traffic geocode/validation, stock search/validation, generic data test fetch and Home Assistant entity picker.
- [ ] **ai_configuration** — Remaining. Provider CRUD/order/protocol/model/base URL/key/sign-in preset configuration, default provider, approval mode/turn cap and provider model/test results.
- [ ] **ai_generate** — Remaining. Generate page draft with warnings and explicit staged application/save semantics.
- [ ] **ai_chat** — Remaining. Global/editor POST SSE chat: text/status/tool streaming/call/result/warning/error/done, approvals, elicitation, cancel and non-replayed interrupted turns.
- [ ] **ai_history** — Remaining. List/search/open/save/rename/delete/clear/export conversations and restore editor/global context with interrupted-turn semantics.
- [ ] **general_settings** — Remaining. General config/instance identity/timezone/date/output mode, aggregate settings and restore notices/dismissal.
- [ ] **display_preferences** — Remaining. Board/site animations, reduce motion, preview/display preferences and capability-appropriate native presentation.
- [ ] **polling_preferences** — Remaining. Polling/UI and plugin refresh/update intervals with restart requirements and scheduling cadence.
- [ ] **location_settings** — Remaining. Location latitude/longitude/timezone and single-day/week sunrise/sunset values, no-location and polar/DST cases.
- [ ] **mqtt_settings** — Remaining. MQTT broker settings/credentials and runtime enabled/connected/running state.
- [ ] **backup_restore** — Remaining. Download complete backup and import/restore with reinstall_plugins choice, pre-restore copies, skipped files, external-plugin/manual install and reload errors.
- [ ] **system_updates** — Remaining. Current/running/build version, sidecar status and rollback/regression information, check/apply updates, auto interval and release channel switch; manual instructions when unavailable.
- [ ] **system_power** — Remaining. Explicit restart/shutdown with progress and later reconnect health; capability/error handling.
- [ ] **wifi_management** — Remaining. Capability-gated Wi-Fi status/scan/saved profiles/connect/disconnect/forget including password and lost-connectivity recovery.
- [ ] **diagnostics** — Remaining. Blank/fill/info/test board, clear/cache status, system/network diagnostics and hardware verdicts.
- [ ] **native_connection_management** — Partial draft. Manual URL/server selection, deployment identity, discovery permission and offline reconnect
- [ ] **route_navigation** — Partial draft. All browser route destinations and nested layouts, back navigation and durable selection
- [ ] **deep_links** — Remaining. Query/hash deep links, legacy settings sections, safe post-login redirect and activation code
- [ ] **panel_link_sharing** — Remaining. Copy/open a panel viewer URL, long and short viewer route
- [ ] **panel_presentation** — Remaining. Fullscreen panel/TV display, animation/matrix/font/backdrop/auto-dim and sleep behavior
- [ ] **page_library_navigation** — Partial draft. Library search/filter/sort/grid-list, geometry/device compatibility and duplicate actions
- [ ] **editor_document** — Partial draft. Rich/plain template editor, tokens/formulas, line alignment/wrap, colors/icons and cell editing
- [ ] **editor_charset** — Remaining. Character-set-aware visual cells, painting, geometry and LED formatting
- [ ] **editor_drafts** — Partial draft. Draft recovery, unsaved navigation protection and page/new editor state
- [ ] **editor_undo** — Partial draft. Undo/redo, local selection and keyboard editing across rich/plain/canvas controls
- [ ] **canvas_management** — Remaining. Up to eight canvases; add/remove/select and area, bleed, scale and flow
- [ ] **canvas_draw** — Remaining. Draw brush/eraser/bucket/eyedropper, RGB palette, zoom/grid and accessible pixel cursor
- [ ] **canvas_shapes** — Remaining. Shapes parameters, order and dynamic expressions
- [ ] **canvas_source** — Remaining. Canvas plugin source variable or arbitrary expression
- [ ] **calendar_interaction** — Remaining. Calendar/list views, recurrence/timezone-aware drag and resize, accessible entry form
- [ ] **collection_rules_editor** — Implemented draft for member order, modes/expressions, intervals, fallback and polling. Reconcile any per-page-duration wording with the current source contract; complete device/pose/VoiceOver and supported-pairing acceptance.
- [ ] **oauth_relay_flow** — Remaining. Relay browser start, signed local/prefixed callback, refusal/expiry and manual URL/code rescue
- [ ] **oauth_device_flow** — Remaining. Device verification URL/code, server polling and pending/expired/denied/failed statuses
- [ ] **oauth_key_exchange_flow** — Remaining. Key exchange callback or explicit headless pasted provider code
- [ ] **oauth_plex_flow** — Remaining. Plex PIN authorization opens browser and server polls, optional forward URL
- [ ] **oauth_app_registration** — Remaining. Shared/user OAuth app registration fields, reconnect, saved paste offer and AI provider sign-in
- [ ] **ai_staging** — Remaining. Editor AI staging/diffs, approvals/questions, global drawer and saved conversation context
- [ ] **appearance_theme** — Partial draft. Light/dark/system appearance
- [ ] **localization** — Remaining. Fourteen locales and language persistence, locale-aware formatting/output labels
- [ ] **accessibility** — Partial draft. Skip/focus/labels, motion preferences, keyboard and form error announcements
- [ ] **pwa_installation** — Remaining native equivalent: installation, onboarding/update and foreground/background/relaunch lifecycle; no browser service worker is required in SwiftUI.
- [ ] **offline_recovery** — Partial draft. Offline page and health retry; cache/offline/read/write distinction
- [ ] **geolocation_permission** — Remaining native equivalent: user-initiated Core Location permission, denied/restricted/no-fix/manual fallback and server latitude/longitude save.
- [ ] **external_plugin_documents** — Remaining. Fetch repository README and manifest-derived preview images/relative links
- [ ] **mcp_connector_instructions** — Remaining. Generate/copy MCP client instructions and endpoint/token config
- [ ] **removed_debug_monitor** — Remaining. Legacy /debug monitor route explains removed monitoring and docker logs command
- [ ] **adaptive_device_poses** — Partial draft. Preserve every workflow across compact/expanded/resized/folded/seated/standing layouts

## Working rules

- Keep this file current in every integrated milestone; record tested commits and reviewer verdicts below.
- Run bounded independent tracks with explicit file ownership. User authorized parallel subagents and Claude Opus CLI: Sol 6.1 implements/tests; Astra independently reviews integrated work. Opus may contribute when authenticated; its expired login does not block Sol progress. Do not report Opus work unless an actual call succeeds.
- Keep user signing changes and dirty backend work untouched. Build scripts must not silently regenerate the Xcode project.
- Use fixtures/disposable backends for automated tests. Do not exercise production boards.
- Distinguish implemented, built, host-tested, simulator-tested and physically verified. Keep unsupported writes disabled.

## Evidence and decisions

- Baseline: `d6b8a26` (Astra-approved draft), `3c77d42` (signing-preserving helper). See [draft verification](docs/research/2026-10-25-draft-verification.md).
- Next-wave choice: Jev recommended controls + editor foundation over schema/renderer or immediate broad backend revisions (0.95 reported confidence). Source dependencies and acceptance tests determine readiness; the advisory is not proof.

- Claude Opus CLI attempts for C-01 and E-01 both returned HTTP 401: saved OAuth access token expired. No Opus code contribution is claimed. Sol continues; retry only after authentication is refreshed.

- Backend API work is isolated at `../fiestaboard-ios-api` on `codex/ios-api-access`, based on clean upstream `3a1d6e8b6` (10.1.2). The user authorized one ongoing draft PR for native API gaps. The original dirty backend checkout is untouched. The iOS draft remains pinned to its audited 10.0.0 candidate writes; a newer server version is not implicitly trusted.

- [Native API access audit](docs/research/2026-10-25-native-api-gaps.md): current web source is a static SPA using existing API routes; no additional hidden SSR data gap was demonstrated. Page preconditions are the first backend patch; native adapters cover most remaining access work.

- Wave 1 approved by Astra at `be72a11`, after scalar-exact Unicode and visible control outcome/readback fixes. 29 Kit + 23 AppState + 22 Documents tests passed; unsigned Simulator/device builds and UI-test compilation passed. UI tests were not executed. See [wave verification](docs/research/2026-10-25-parity-wave-1-verification.md).

- Backend page foundation: `1514c274a` pushed to `Fiestaboard/FiestaBoard:codex/ios-api-access`; product changes Astra-approved at `4967cb7e2`. 523 focused Python tests and the corrected full web suite (3,060 passed, seven skipped) passed. Full Python run OOMed at 54%; no complete Python-suite claim. [Prepared single draft PR and branch](docs/research/2026-10-25-backend-pr-draft.md). GitHub connector requires approval but this session has approval policy never, so PR creation remains pending.

- Local main received the reviewed iOS wave, preserving all 21 local Xcode project-property changes. Fresh main unsigned iPhone build, contract integrity and all 25 contract-tool tests passed. User signing selections remain uncommitted; no automatic project regeneration was performed on main.

- 2026-10-26 continuation: GitHub confirms no PR exists for `codex/ios-api-access`. Creation remains blocked by the connector approval policy. [Page editing plan](docs/superpowers/plans/2026-10-26-page-editing.md) adds a narrow advertised page protocol, native changed-field saves/conflict recovery, and explicit template validation/previews. Jev recommended the per-page protocol field (0.94 confidence); source/tests and Astra determine acceptance.

- Wave 2 backend protocol `dadbc191e` passed Astra review and is pushed to the same backend branch (522 focused/contract tests; 75 independently checked). Native wave initially passed 108 tests but Astra found a late-preview recovery overwrite; fixes are now under focused review. Native compilation and contract checks are green; no interactive UI execution is claimed.

- Wave 2 accepted at `aa03da7`: Astra P1 recovery overwrite fixed and original reproduction passes unchanged. 117 Swift host tests (42 Kit, 35 AppState, 25 Documents, 15 EditorState), 25 contract-tool tests, final unsigned Simulator/device builds and UI-test compilation pass. Seven UI tests are compiled, none executed. [Wave verification and testing limits](docs/research/2026-10-26-page-editing-verification.md).

- PR creation resolved: at the user's explicit direction, used `gh` instead of the connector. Draft PR [#2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373) is OPEN and draft, targeting `main` from `codex/ios-api-access` at `dadbc191e`. Use this single PR for subsequent backend API work; do not open duplicates. Prefer `gh` for this GitHub workflow. No merge or deployment occurred.

- Native collections: implemented against merged source79edd37d2/version10.1.7. Kit65 +AppState46 +Documents25 +EditorState50 host tests pass;29contract tests/integrity and55fenced backend cases pass. Astra core/editor reviews pass after six findings were fixed. Simulator/device builds and existing UI-test compilation pass; interactive tests remain unexecuted. See the linked collection verification record for commits, source boundaries and remaining acceptance.

- October28 user approved continuous parity implementation and explicitly required rich editing for split-flap and LED. [Separate acceptance matrix](docs/research/2026-10-28-rich-editor-requirements.md); [early HA access decision/proof limits](docs/research/2026-10-28-ingress-access-decision.md). Fresh baseline186Swift/29contract tests passed before implementation. User confirmed test endpoint opens in iPhone Safari; native device/auth/output proof remains open.
