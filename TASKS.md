# FiestaBoard iOS remaining work

This is the durable task tracker. Full web-app feature parity is required before the first App Store release. Checkboxes mean the whole listed deliverable is accepted, not that a draft screen exists. `Contracts/parity.json` remains the release inventory; source/fixture tests alone do not make a workflow release-verified.

## Current baseline

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
| P-01 | All-writer server revisions and conditional saves | Page foundation reviewed and pushed; draft PR creation blocked by connector approval policy; broader writer work remains | Web/AI/import/restore/background writers; both save orders; isolated backend branch |
| P-02 | Native conditional page saves and explicit conflict handling | Queued | Consume reviewed backend protocol; audited release and lossless field contract; never retry stale writes automatically |
| E-02 | Server template validation and render previews | Queued | Adapt existing internal endpoints with geometry/charset/canvas fixtures |
| S-01 | Shared schema vocabulary, secret-preserving drafts and native forms | Queued | Required by display configuration and integrations |
| R-01 | Complete LED/pixel/layer/white-board renderer and geometry fidelity | Queued | Shared golden fixtures; actual visual/device checks |

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
- [ ] **pages_crud** — Remaining. List/get/create/update/delete all single/composite/template page types; duplicate via create; preserve metadata/charset/geometry/transitions/canvases and explicit nulls.
- [ ] **page_preview** — Remaining. Saved page and batch previews, target geometry/LED spans/icons/cells/layers, availability and rendering errors.
- [ ] **page_sharing** — Remaining. Export/copy page share string and import pasted/file/shared content; preserve format and validation errors.
- [ ] **staff_picks** — Remaining. Browse/filter Picks by device, inspect plugin requirements, retrieve share data and import a pick.
- [ ] **collections** — Remaining. Create/update/delete/list ordered collections with time/variable/random modes, rules, default behavior and per-page durations.
- [ ] **schedule_entries** — Remaining. Board-scoped schedule CRUD/toggle; weekly/annual/one-off recurrence, day patterns, start/end/sun offsets, page/collection targets and compatibility warnings.
- [ ] **schedule_validation** — Remaining. Calendar/list active resolution, overlaps and gaps, schedule behavior settings and validation.
- [ ] **silence_configuration** — Remaining. Global/per-board silence schedule with overnight windows, indicator/freeze/page, indicator placement, queued-on-exit and explicit nullable page fields.
- [ ] **plugins_configuration** — Remaining. Installed plugin list/detail/manifest, enable/disable, schema configuration, secret masks/preservation, variables, data and circuit-breaker errors.
- [ ] **plugin_instances** — Remaining. List/add/delete named plugin instances; configure and identify instance-specific secrets, variables and OAuth connections.
- [ ] **plugin_demo** — Remaining. Inspect/create plugin demo pages with provenance and idempotent existing-demo behavior.
- [ ] **plugin_marketplace** — Remaining. Registry list/install, Git repository install, update/uninstall, available update checks and bulk application; display progress/errors/provenance.
- [ ] **plugin_options** — Remaining. Dynamic schema remote options, query/search/dependent settings, pagination/current labels, secret-preserving settings context and loading/error/empty cases.
- [ ] **oauth_connections** — Remaining. List status/configuration/scopes/expiry/reconnect reason, start relay/device/key_exchange/plex_pin, complete pasted URL/code, disconnect, browser return and plugin/AI routing.
- [ ] **template_authoring** — Remaining. Variable/function discovery, validation and side-effect-free server rendering with text, tokens, line metadata, geometry, charset warnings and canvas layers.
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
- [ ] **collection_rules_editor** — Remaining. Collection page ordering, rule modes/expressions, durations and default controls
- [ ] **oauth_relay_flow** — Remaining. Relay browser start, signed local/prefixed callback, refusal/expiry and manual URL/code rescue
- [ ] **oauth_device_flow** — Remaining. Device verification URL/code, server polling and pending/expired/denied/failed statuses
- [ ] **oauth_key_exchange_flow** — Remaining. Key exchange callback or explicit headless pasted provider code
- [ ] **oauth_plex_flow** — Remaining. Plex PIN authorization opens browser and server polls, optional forward URL
- [ ] **oauth_app_registration** — Remaining. Shared/user OAuth app registration fields, reconnect, saved paste offer and AI provider sign-in
- [ ] **ai_staging** — Remaining. Editor AI staging/diffs, approvals/questions, global drawer and saved conversation context
- [ ] **appearance_theme** — Partial draft. Light/dark/system appearance
- [ ] **localization** — Remaining. Fourteen locales and language persistence, locale-aware formatting/output labels
- [ ] **accessibility** — Partial draft. Skip/focus/labels, motion preferences, keyboard and form error announcements
- [ ] **pwa_installation** — Remaining. Browser install prompt, manifest/service worker and installed-app lifecycle
- [ ] **offline_recovery** — Partial draft. Offline page and health retry; cache/offline/read/write distinction
- [ ] **geolocation_permission** — Remaining. Use browser location to fill server latitude/longitude
- [ ] **external_plugin_documents** — Remaining. Fetch repository README and manifest-derived preview images/relative links
- [ ] **mcp_connector_instructions** — Remaining. Generate/copy MCP client instructions and endpoint/token config
- [ ] **removed_debug_monitor** — Remaining. Legacy /debug monitor route explains removed monitoring and docker logs command
- [ ] **adaptive_device_poses** — Partial draft. Preserve every workflow across compact/expanded/resized/folded/seated/standing layouts

## Working rules

- Keep this file current in every integrated milestone; record tested commits and reviewer verdicts below.
- Run bounded independent tracks with explicit file ownership. User authorized Claude Opus CLI and parallel subagents; Sol coordinates/tests, Opus contributes implementation, Astra independently reviews integrated work. Do not report Opus work unless an actual call succeeds.
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
