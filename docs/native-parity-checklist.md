# Native FiestaBoard end-to-end parity checklist

Planning baseline: October 28, 2026. This is the authoritative human acceptance checklist linked from TASKS.md. It expands all **81 original workflow IDs plus three explicit current-source workflows**, with repository, compatibility, journey and release requirements. It is a working plan for review, not a claim that the app is complete.

The native draft is at `116b075`. Proposed current-web target: FiestaBoard **10.1.17**, `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. Original Contracts inventory remains independently pinned to 10.0.0 until its audited migration. Scoped 10.1.7 collection evidence remains separate.

User's first test target: `http://fiestapi.local:4420`. Credentials are deliberately absent. Read-only requests to health/discover/auth-status on October 28 returned **No route to host** from this environment. This is a reachability blocker, not evidence of a bad password or stopped server; installed version and actual native login remain unverified. The user subsequently confirmed the same URL opens in iPhone Safari on the same Wi-Fi; Mac-side resolved IPv4/IPv6 health probes still fail. Continue isolated implementation while resolving development-side access.

Read alongside [design](superpowers/specs/2026-10-28-native-parity-completion-design.md), [execution plan](superpowers/plans/2026-10-28-native-parity-completion.md), [original source inventory](parity.md), [contracts policy](contracts.md), and [latest completed milestone](research/2026-10-27-native-collections-verification.md).

## How items become complete

A checkbox means the entire described result has accepted evidence. Existing partial implementations stay open. For every workflow below, apply the same acceptance contract:

1. Reachable native UI and real typed service behavior for the frozen upstream capability, or its documented native equivalent.
2. Success/loading/empty/validation/refusal/auth-expiry/offline/partial/unknown states as applicable; accessible actionable recovery.
3. Correct server/board/resource/scene identity, secret handling, original revisions and explicit null/omitted values.
4. Relevant host and isolated contract tests; actual UI execution; available geometry/input/accessibility/localization matrix.
5. Evidence file with app/server commits, commands/results, runtime/device conditions, screenshots when useful, reviewer verdict and remaining limitations. Compiled UI tests cannot satisfy runtime acceptance.
6. Sol implementation plus independent Astra acceptance. No unchecked omission disappears because a newer milestone starts.

Use the evidence levels **D** draft implemented, **B** built, **H** host tested, **I** isolated server behavior, **U** UI runtime, **P** physical device/board observed, **R** full release accepted. Track them separately; never replace the entire list with a percent based on screen or checkbox count.

Future upstream deltas go into a dated intake list and must be reconciled before changing the parity target. Do not silently promise all future server versions. A capability unsupported by an actual server gets an explanation; a feature supported by the chosen reference must have a working native path.

## F0 — Source, clone and compatibility foundation (W0)

- [ ] F0-01 Record exact native commit, upstream source/build, schema generator environment and clean source hashes.
- [ ] F0-02 Regenerate public/internal schemas, route/UI sources and operation mappings for 10.1.17; reconcile every original workflow and non-barrel fetch/stream/download/external path.
- [ ] F0-03 Expand newly visible capabilities within existing rows or add reviewed new IDs; never force the refreshed inventory to stay at 81/198.
- [ ] F0-04 Preserve the 10.0.0 baseline and 10.1.7 fixtures as dated evidence rather than attributing old tests to new source.
- [ ] F0-05 Migrate the single-source snapshot/checker design to a current authoritative snapshot plus archived baselines, or a reviewed multi-source format; keep reciprocal coverage/hash and negative tests.
- [ ] F0-06 Audit 10.1.17 page/collection/schedule/default/document protocols, authentication/errors, preview/control receipts and side effects with isolated runtime fixtures.
- [ ] F0-07 Build a per-operation current-version capability policy; replace obsolete board-control gate only after its own fixtures/review. No blanket >=version enablement.
- [ ] F0-08 Confirm the installed version of the test instance separately from upstream main; retain unsupported-version diagnostics.
- [ ] F0-09 Inventory all target models/geometries/charsets and setup/admin/OAuth host capabilities without assuming they exist on every install.
- [ ] F0-10 Confirm repository owner/visibility for `fiestaboard-ios`, establish its remote using gh and preserve existing history. No personal credentials or signing Team are committed.
- [ ] F0-11 Document clone/open/build/test prerequisites, pinned tool versions and network/offline requirements.
- [ ] F0-12 Implement reproducible source/fixture bootstrap without preexisting ignored .reference/.build directories or local-only Docker images.
- [ ] F0-13 Prove a fresh clone can run package/contract tests, generate needed resources and build device/Simulator targets from committed inputs.
- [ ] F0-14 Keep project.yml and committed Xcode project/resources synchronized with a controlled generation/check path that preserves local signing.
- [ ] F0-15 Provide normal live-onboarding and explicit demo schemes; confirm shipping/profile configuration never auto-forces --demo.
- [ ] F0-16 Add macOS CI for packages, contracts/integrity, source bindings, device/Simulator builds and actually executed Simulator UI tests.
- [ ] F0-17 Add isolated Docker API replay jobs with bounded memory/time and artifacts; mark provider/hardware/manual jobs honestly.
- [ ] F0-18 Protect user signing edits and existing dirty backend work during each integration; compare project semantics if generated metadata changes.
- [ ] F0-19 Reconcile stale README/TASKS/app capability copy and historical PR claims; distinguish historical evidence from current active instructions.
- [ ] F0-20 Keep integrity green and release-readiness red until actual gates pass; add negative cases preventing fake supported/verified claims.

## J0 — First real controller journey (W1, highest priority)

- [ ] J0-01 Resolve reachability to fiestapi.local:4420 from the development/test device; confirm Wi-Fi/VPN/LAN and manual IP fallback without interpreting route failure as authentication failure.
- [ ] J0-02 Cold-launch to live connection onboarding without editing an Xcode argument.
- [ ] J0-03 Tap Find FiestaBoard, allow local-network access, find/verify the intended server or use a working manual/pasted URL.
- [ ] J0-04 Show server identity, transport and compatibility before entering credentials; distinguish server discovery from hardware-board scanning.
- [ ] J0-05 Sign in successfully with the test account and prove rejected-password/rate-limit/retry states without losing the selected server.
- [ ] J0-06 Select the intended board, including zero/multiple-board and no-library-yet cases.
- [ ] J0-07 See current/selected/scheduled output distinctions and a clear supported-control status on the installed test-server version.
- [ ] J0-08 Explicitly enable supported changes, review captured board and send a user-authorized test message.
- [ ] J0-09 Compare server acknowledgement/readback and, with the user, actual board output; verify a timeout never silently resends.
- [ ] J0-10 Quit/reopen and reconnect through saved server plus explicitly remembered secure session; expired session offers reauthentication.
- [ ] J0-11 Log out, clear local material and verify remote revocation or visible pending revocation; a different server cannot inherit the session.
- [ ] J0-12 Repeat on iPad/narrow window and with VoiceOver/keyboard for the connect-to-control path; record concrete runtime evidence.

## J1 — Cross-feature journeys that define end-to-end parity

- [ ] J1-01 Fresh server → auth choice/admin setup → first output setup/test → first page → show output.
- [ ] J1-02 Add second server → switch scenes/servers/boards → reconnect → prove cookies, caches, draft revisions and pending confirmations remain isolated.
- [ ] J1-03 Create/import/duplicate every page kind → rich/plain/cell/canvas edit → preview → conditional save → select/display → export/reimport.
- [ ] J1-04 Create collection → configure each rule mode → select/override → schedule it → inspect resolution → handle missing/deleted member.
- [ ] J1-05 Create schedule with sun/timezone/DST/overnight behavior → validate overlap/gap/default/silence → observe transitions and explicit restore.
- [ ] J1-06 Install plugin → create instance → secret/remote-option/color-rule/JSON-mapping settings → authorize provider → use variable/canvas → update/remove and recover errors.
- [ ] J1-07 Complete each of relay/device/key_exchange/plex_pin on supported providers with denial, expiry, manual rescue and background/resume.
- [ ] J1-08 Configure AI → global/editor conversation → tool approval/question → stage diff → save original-revision document → retrieve/export history.
- [ ] J1-09 Concurrent web/native/AI/MCP edits in both orders → stale save/delete/default rejection → explicit compare/duplicate/adopt → no automatic rebasing/replay.
- [ ] J1-10 Backup → intentional test edit → restore in isolated/test environment → invalidated old revisions/drafts/cache → inspect partial/manual-plugin outcomes.
- [ ] J1-11 Open/present/share a panel with correct rendering/preferences → background/resume → receiver/browser route under proxy prefix.
- [ ] J1-12 Admin session/account/device operations → revoke current/other sessions → native credential recovery across scenes.
- [ ] J1-13 Supported update/restart/Wi-Fi change on a disposable host → expected disconnect → discover/reconnect → inspect actual outcome without duplicate action.
- [ ] J1-14 Rotate/resize/multiwindow/background during editor, confirmation, OAuth, AI and calendar flows → preserve context and user work.

## Complete original workflow acceptance

The first81 headings retain their original Contracts/parity.json IDs; the following current-source section adds three separately inventoried IDs. Wave and current status describe sequencing and partial code, not acceptance. The acceptance contract above applies to **every** item.

### connection_boot

Wave: **W1**. Current: **Partial**.

- [ ] connection_boot.1 Separate server health/startup 503, identity/discover, auth state, compatibility, service-running state and board availability; one failing optional domain must not destroy the connected shell.
- [ ] connection_boot.2 Show retry/cancel and actionable DNS/TLS/timeout/gateway-HTML/auth-store errors; distinguish healthy-but-setup-required and healthy-with-zero-boards.
- [ ] connection_boot.3 Read the installed version/build after authorized connection and select independently tested adapters; unknown/development releases explain unavailable capabilities.

### auth_onboarding

Wave: **W1**. Current: **Partial**.

- [ ] auth_onboarding.1 Implement enabled/disabled/undecided/first-run/setup-required/authenticated states and a safe return destination.
- [ ] auth_onboarding.2 Implement first-run auth preference and administrator setup, including env-pinned 409, setup race, validation and stored-MCP-token possession requirements where the server requires them.
- [ ] auth_onboarding.3 Implement username/password login, explicit Remember sign-in, wrong-password 401 and rate-limit 429/Retry-After feedback without saving the password.
- [ ] auth_onboarding.4 Handle expired/revoked/replaced sessions, logout success/offline-pending/failure and replacement cookies; reopen with deployment-scoped secure session material.

### account_credentials

Wave: **W9**. Current: **Missing**.

- [ ] account_credentials.1 Change username and password with server validation/current-password context and clear replacement-cookie/session-generation effects.
- [ ] account_credentials.2 Disable authentication using the current-password/confirmation path and refresh all scene/session capabilities.
- [ ] account_credentials.3 Exercise another active scene, an expired current session, rejected input and account changes made in the web app.

### device_activation

Wave: **W9**. Current: **Missing**.

- [ ] device_activation.1 Open activation deep link, scan QR or enter code; inspect device identity before explicit approve/deny.
- [ ] device_activation.2 Handle invalid/expired/consumed/denied/rate-limited codes and enrollment enabled/disabled changes.
- [ ] device_activation.3 Use cookie plus fresh CSRF/Origin for administrative actions; never substitute a TV panel-scoped bearer credential.

### session_management

Wave: **W9**. Current: **Missing**.

- [ ] session_management.1 List current/other sessions and device metadata, including auth-disabled/no-browser-session behavior.
- [ ] session_management.2 Fetch fresh CSRF context and send the exact accepted external Origin before individual/self/other/all revocation.
- [ ] session_management.3 Handle expired context, account generation changes, current-session removal, offline revocation and propagation to every relevant app scene.

### mcp_credentials

Wave: **W9**. Current: **Missing**.

- [ ] mcp_credentials.1 Show token status, rotate/delete with applicable current-token gate on auth-disabled installs.
- [ ] mcp_credentials.2 Display/copy newly issued plaintext only as the server permits; redact logs, cached UI and exported diagnostics.
- [ ] mcp_credentials.3 Verify cancellation, lost response after rotation and stale administrative session without silently issuing another token.

### home_state

Wave: **W1–W2**. Current: **Partial**.

- [ ] home_state.1 Independently show server-reported current/remembered external output, selected page/collection, resolved member, scheduled page, fallback and service state.
- [ ] home_state.2 Represent pause, silence modes, held queue and temporary override with reasons/timestamps; do not label a selected page as physically displayed.
- [ ] home_state.3 Refresh only relevant visible data, label stale/offline values and handle optional-domain failure without losing working control navigation.

### home_commands

Wave: **W1–W2**. Current: **Partial**.

- [ ] home_commands.1 Complete explicit-target text send, restore, clear remembered external frame, discard held queue, force refresh and service start/stop.
- [ ] home_commands.2 Represent sent/unchanged/UI-only/queued/held/refused/partial/unknown outcomes and detailed region failures.
- [ ] home_commands.3 Capture deployment/board/content at review, serialize per target and reconcile after acknowledgement; switching primary/scene/connection never retargets or replays a command.
- [ ] home_commands.4 Test realistic long-running sends, malformed receipts, request cancellation and timeout-after-apply; use command-appropriate timeout without an automatic resend.

### temporary_override

Wave: **W2**. Current: **Missing**.

- [ ] temporary_override.1 Create page/collection/inline overrides with preset/custom or indefinite duration, limits and explicit target.
- [ ] temporary_override.2 Support revert-to-schedule/blank/page, current countdown, cancel and replacement of an existing override.
- [ ] temporary_override.3 Verify expiry while backgrounded, clock/timezone change, silence/held interactions and the side effects of override-status reads.

### board_control

Wave: **W1–W2**. Current: **Partial**.

- [ ] board_control.1 Audit message/restore/configuration semantics on the chosen current server before enabling an exact-version adapter.
- [ ] board_control.2 Implement pause/resume, schedule enablement and fallback selection/clearing with captured target and conditional default semantics where supported.
- [ ] board_control.3 Keep conditional PUT schedule-default distinct from unconditioned board PATCH; conflicting web/default changes require comparison rather than a token refresh.

### board_configuration

Wave: **W3**. Current: **Missing**.

- [ ] board_configuration.1 List/add/rename/remove/select primary output boards and edit connection/API-mode/credential settings through shared typed forms.
- [ ] board_configuration.2 Configure geometry/model/charset/transitions and preserve omitted, masked and explicitly cleared fields.
- [ ] board_configuration.3 Preview retarget/resize implications; report copied/modified pages, stale references and partial results; invalidate all affected caches and drafts safely.

### board_setup

Wave: **W3**. Current: **Missing**.

- [ ] board_setup.1 Run first-board setup validation, server-side hardware scan/probe and connection test with distinct device/network/API verdicts.
- [ ] board_setup.2 Guide enabling the hardware's local API and offer an explicit welcome/test send.
- [ ] board_setup.3 Recover from no hardware, unsupported local API, wrong credentials, cancelled scan and network change; server discovery and physical-board scan remain distinct.

### output_catalog

Wave: **W3**. Current: **Missing**.

- [ ] output_catalog.1 Present installed/available/catalog outputs and model compatibility; distinguish registry offline, empty catalog and unsupported plugin.
- [ ] output_catalog.2 Install a chosen output plugin with progress and refreshed catalog after completion.
- [ ] output_catalog.3 Reconcile interrupted/uncertain install from actual state and preserve provenance/version without duplicate install requests.

### output_actions

Wave: **W3**. Current: **Missing**.

- [ ] output_actions.1 Render manifest-defined draft and saved-board test/discover/identify/detect-geometry actions, mode-cards/device-picker/tile-grid widgets and supported arbitrary action schemas as part of W3 output setup.
- [ ] output_actions.2 Bind draft/saved-board actions and tile coordinates/unique fields/nested settings correctly; apply returned geometry and redacted secret fields only to the right draft, with clear user intent for device effects.
- [ ] output_actions.3 Handle delayed action results, partial failures and schema changes without overwriting newer edits.

### output_board_creation

Wave: **W3**. Current: **Missing**.

- [ ] output_board_creation.1 Choose output/model and complete typed schema settings plus geometry/name to create a board.
- [ ] output_board_creation.2 Validate required/default/nullable values and secret context before creation; route an empty install into this flow.
- [ ] output_board_creation.3 Handle duplicate/unknown creation, post-create selection and refreshed output catalog without automatically creating another board.

### panel_configuration

Wave: **W3–W4**. Current: **Missing**.

- [ ] panel_configuration.1 Create/edit/remove virtual panels with supported geometry, TV/backdrop/font/matrix/sizing/auto-dim/presentation options.
- [ ] panel_configuration.2 Expose HDMI/kiosk controls only when supported and preserve server values not represented by native controls.
- [ ] panel_configuration.3 Report geometry conversion/retarget consequences and stale references; refresh panel, pages, collections, active output and silence state.

### panel_viewer

Wave: **W4**. Current: **Missing**.

- [ ] panel_viewer.1 Load standalone panel configuration/frame independently of the editing shell and render supported split-flap/LED content.
- [ ] panel_viewer.2 Handle authentication, invalid/deleted panel, malformed frame, stale/offline playback and foreground refresh.
- [ ] panel_viewer.3 Keep read-only viewing separate from administration and verify both normal and short viewer-route equivalence.

### wizard_state

Wave: **W3**. Current: **Missing**.

- [ ] wizard_state.1 Implement welcome/output/model/connection/panel/easy-plugin steps with durable server wizard outcome.
- [ ] wizard_state.2 Support skip, complete, resume and reopen without repeating already applied server changes.
- [ ] wizard_state.3 Handle partially configured installs and unavailable output/plugin dependencies without trapping the user in onboarding.

### pages_crud

Wave: **W5**. Current: **Partial**.

- [ ] pages_crud.1 List/get/create/edit/delete/duplicate single, composite and template pages with original revisions and correct resource identity.
- [ ] pages_crud.2 Preserve metadata, geometry, charset, transitions, canvases, extension JSON, list replacement, omitted fields and explicit null under page-document-v1.
- [ ] pages_crud.3 Handle delete references, conflicts, ID deletion/recreation, restore/conversion generations and uncertain creation/save; retain usable local work.
- [ ] pages_crud.4 Reconcile protocol/version capabilities before rich saves; narrow template-save support is not full page CRUD.

### page_preview

Wave: **W4–W5**. Current: **Partial**.

- [ ] page_preview.1 Implement saved-page and batch previews with explicit target geometry, charset, visual spans/icons/cells/layers and availability warnings.
- [ ] page_preview.2 Distinguish server-rendered output, local draft simulation, text diagnostics and physically reported output.
- [ ] page_preview.3 Tag/cancel superseded requests by draft/target revision; plugin errors, unsupported content or late results must not replace newer previews.

### page_sharing

Wave: **W5**. Current: **Missing**.

- [ ] page_sharing.1 Export/copy/share page strings and files; import pasted, Files, share-sheet and dropped content with validation.
- [ ] page_sharing.2 Preserve supported page/document fields and make create-new versus replace-existing explicit.
- [ ] page_sharing.3 Handle incompatible format/version/size, cancelled file access, missing dependencies and unknown import outcomes without data loss.

### staff_picks

Wave: **W5**. Current: **Missing**.

- [ ] staff_picks.1 Browse/filter Picks by device/geometry, inspect previews and plugin prerequisites.
- [ ] staff_picks.2 Retrieve share data and import the selected pick through the same validated page-import path.
- [ ] staff_picks.3 Handle registry/offline/unavailable pick and missing plugin; avoid duplicating imported pages after ambiguous completion.

### collections

Wave: **W6**. Current: **Implemented draft**.

- [ ] collections.1 Runtime-test list/search/create/edit/delete, member order, time/variable/random modes and current member resolution.
- [ ] collections.2 Verify original-revision conflict/delete/restore/reconnect barriers and unknown-field/mode read-only behavior on the refreshed candidate.
- [ ] collections.3 Execute multiwindow recovery/adoption/revert/Unicode/exact-source-retirement cases on actual app storage; preserve independent prior drafts.
- [ ] collections.4 Verify geometry/VoiceOver/input acceptance and board selection of a collection separately from collection storage.

### schedule_entries

Wave: **W6**. Current: **Missing**.

- [ ] schedule_entries.1 Implement board-scoped entry CRUD/enable-disable with original schedule revision and accessible entry form.
- [ ] schedule_entries.2 Support weekly/annual/one-off recurrence, day patterns, time/sun start-end offsets and page/collection targets.
- [ ] schedule_entries.3 Handle overnight/date-boundary/DST/invalid target/geometry cases; stale update/delete and uncertain create require explicit reconciliation.

### schedule_validation

Wave: **W6**. Current: **Missing**.

- [ ] schedule_validation.1 Show calendar/list active resolution, overlap/gap validation, defaults and schedule behavior settings.
- [ ] schedule_validation.2 Use original schedule-default revision for board-scoped default changes and explicit nullable clearing.
- [ ] schedule_validation.3 Explain server-timezone versus phone-timezone, disabled schedule, missing location, polar sun and concurrent web/native changes.

### silence_configuration

Wave: **W6**. Current: **Missing**.

- [ ] silence_configuration.1 Edit global/per-board silence windows including overnight days, indicator/freeze/page modes and placement.
- [ ] silence_configuration.2 Preserve explicit null page/indicator settings and show current held/queued behavior plus queued-on-exit options.
- [ ] silence_configuration.3 Verify entry/exit transitions, overlap with override/pause/schedule, invalid references and cancellation while editing.

### plugins_configuration

Wave: **W7**. Current: **Missing**.

- [ ] plugins_configuration.1 Show installed list/detail/manifest, enable/disable, configuration, variables, data and circuit-breaker errors.
- [ ] plugins_configuration.2 Implement secret-preserving schema configuration including sections, visible_when, nested objects/arrays, validation and explicit clear/reveal.
- [ ] plugins_configuration.3 Implement plugin color rules: field creation/removal, numeric/string comparisons, ordered first-match rules, six operators, official colors and generated variable copying.
- [ ] plugins_configuration.4 Allow cache/breaker recovery and plugin changes during preview; never leak provider settings through logs or unsupported-field round trips.

### plugin_instances

Wave: **W7**. Current: **Missing**.

- [ ] plugin_instances.1 List/create/rename where supported/delete named plugin instances and route to the right instance settings.
- [ ] plugin_instances.2 Scope secret preservation, variables, options, errors/data and OAuth connection IDs to that instance.
- [ ] plugin_instances.3 Handle duplicate/unknown creation, instance deletion during editing and stale result delivery without cross-instance contamination.

### plugin_demo

Wave: **W7**. Current: **Missing**.

- [ ] plugin_demo.1 Inspect available plugin demo pages, prerequisite configuration and provenance.
- [ ] plugin_demo.2 Create demos through the actual server contract and identify existing/idempotent demo results.
- [ ] plugin_demo.3 Handle disabled/unconfigured plugin, changed demo template and interrupted creation without producing duplicate pages.

### plugin_marketplace

Wave: **W7**. Current: **Missing**.

- [ ] plugin_marketplace.1 Browse registry and Git sources, inspect manifests/README/screenshots/provenance and installed/update status.
- [ ] plugin_marketplace.2 Install/update/uninstall/check/bulk-apply with progress, dependencies and clear partial/error outcomes.
- [ ] plugin_marketplace.3 Handle offline registry, invalid repository, removed plugin references and unknown install results through state inspection, never automatic mutation replay.

### plugin_options

Wave: **W7**. Current: **Missing**.

- [ ] plugin_options.1 Implement scalar/multiple remote options with search, pagination, current labels and dependency settings context.
- [ ] plugin_options.2 Cancel/discard stale option requests when inputs/instance/server change; preserve unresolved current selections.
- [ ] plugin_options.3 Keep secrets in authorized request context without exposing them in UI/cache/export; show loading/error/empty/unsupported-source states.

### oauth_connections

Wave: **W8**. Current: **Missing**.

- [ ] oauth_connections.1 Show connection/provider/instance status, scopes, expiry and reconnect reason; start, complete and disconnect the correct identity.
- [ ] oauth_connections.2 Track pending server-owned authorization across sheets, backgrounding and browser return; a browser success is not native connection proof.
- [ ] oauth_connections.3 Implement manual full-address/bare-code rescue where supported and refresh authenticated server status after completion.
- [ ] oauth_connections.4 Test denied/expired/duplicate/stale completion and network loss; never create a second enrollment merely to recover presentation.

### template_authoring

Wave: **W5**. Current: **Partial**.

- [ ] template_authoring.1 Discover variables/functions and author raw expressions, tokens, colors/icons, alignment/wrap and supported line structure.
- [ ] template_authoring.2 Validate and preview explicitly against server evaluation with target geometry/charset/line diagnostics/canvas warnings.
- [ ] template_authoring.3 Preserve unknown syntax and Unicode; IME/token-adjacent edits, multiline paste and rich/plain switching must pass canonical round-trip tests.

### template_live_output

Wave: **W5**. Current: **Missing**.

- [ ] template_live_output.1 Provide an explicit live-to-board mode with captured named target, visible active indicator and safe stop/expiry.
- [ ] template_live_output.2 Tag draft revisions and distinguish side-effect-free preview from hardware-affecting render.
- [ ] template_live_output.3 Handle pause/silence/override/held/refused/partial/unknown outcomes; leaving/resizing/backgrounding cannot retarget or replay live output.

### integration_helpers

Wave: **W7**. Current: **Missing**.

- [ ] integration_helpers.1 Implement Bay Wheels/Muni station-stop search, nearby/address lookups, traffic geocode/validation and stock search/validation.
- [ ] integration_helpers.2 Implement generic-data test fetch plus JSON-path tree selection/mapping rows/transforms/labels and Home Assistant entity picker.
- [ ] integration_helpers.3 Keep sample/error/empty/pagination/type handling and credential context faithful to each server helper, including JSON/text fetch results.

### ai_configuration

Wave: **W10**. Current: **Missing**.

- [ ] ai_configuration.1 Configure provider CRUD/order/protocol/model/base URL/key/presets/default, approval mode and turn cap with secret preservation.
- [ ] ai_configuration.2 Load supported models/test results and route OAuth sign-in to the same provider connection lifecycle.
- [ ] ai_configuration.3 Handle unavailable provider, invalid credentials, partial config failure and switched provider while an editor/chat holds context.

### ai_generate

Wave: **W10**. Current: **Missing**.

- [ ] ai_generate.1 Generate a page draft with warnings, target geometry and required plugin context.
- [ ] ai_generate.2 Stage results for explicit review/application; generation never silently saves the page or sends hardware output.
- [ ] ai_generate.3 Preserve existing local work through cancellation, malformed output and concurrent server edits.

### ai_chat

Wave: **W10**. Current: **Missing**.

- [ ] ai_chat.1 Implement global/editor POST SSE for text/status/tool-stream/call/result/elicitation/warning/error/done across arbitrary byte boundaries.
- [ ] ai_chat.2 Handle approval modes, questions/resume, cancellation races and already-running server tools with visible outcomes.
- [ ] ai_chat.3 Persist interrupted transcripts and distinguish stream interruption from tool failure; never reconnect/replay a tool-bearing turn automatically.
- [ ] ai_chat.4 Retain original document revisions and immutable deployment/resource context through tools, staging and confirmation.

### ai_history

Wave: **W10**. Current: **Missing**.

- [ ] ai_history.1 List/search/open/save/rename/delete/clear/export conversations with correct global/editor context.
- [ ] ai_history.2 Restore partial/interrupted turns and tool states without resuming side effects implicitly.
- [ ] ai_history.3 Handle long/paginated history, missing conversation, concurrent edits and native file export/authentication.

### general_settings

Wave: **W11**. Current: **Missing**.

- [ ] general_settings.1 Edit instance identity/timezone/date/output/general config and aggregate settings without erasing unrepresented values.
- [ ] general_settings.2 Show restore notices and dismiss them through the supported action.
- [ ] general_settings.3 Validate server-required ranges and partial/failure outcomes, refreshing dependent labels/caches after accepted changes.

### display_preferences

Wave: **W11**. Current: **Missing**.

- [ ] display_preferences.1 Implement shared display/site animation, reduce-motion and preview/presentation preferences.
- [ ] display_preferences.2 Separate server/shared output preferences from app-local appearance and native accessibility settings.
- [ ] display_preferences.3 Verify changes on supported outputs and accessible native rendering without assuming browser CSS behavior.

### polling_preferences

Wave: **W11**. Current: **Missing**.

- [ ] polling_preferences.1 Configure UI/plugin refresh/update intervals and scheduling cadence from supported schemas/ranges.
- [ ] polling_preferences.2 Show restart requirements and actual runtime state separately from saved settings.
- [ ] polling_preferences.3 Test foreground/background cadence, bounded concurrency/backoff and preference changes with requests already pending.

### location_settings

Wave: **W11**. Current: **Missing**.

- [ ] location_settings.1 Edit latitude/longitude/timezone with manual validation and optional native location fill.
- [ ] location_settings.2 Show single-day/week sun times and distinguish server timezone from device display formatting.
- [ ] location_settings.3 Handle no location/fix, polar day/night, DST/date changes and dependent schedule validation.

### mqtt_settings

Wave: **W11**. Current: **Missing**.

- [ ] mqtt_settings.1 Edit broker/address/credentials and enabled/discovery-related settings exposed by the web contract.
- [ ] mqtt_settings.2 Show enabled/configured/runtime-connected/running/error as distinct states.
- [ ] mqtt_settings.3 Preserve masked secrets and handle reconnect/restart requirements and unknown setting-apply outcomes.

### backup_restore

Wave: **W11**. Current: **Missing**.

- [ ] backup_restore.1 Download/share a complete authenticated backup and select/import it with reinstall_plugins choice and explicit destructive review.
- [ ] backup_restore.2 Show pre-restore copies, skipped files, manual/external plugin installation and per-file/reload/partial failures.
- [ ] backup_restore.3 Invalidate old document/default/session/cache generations and recover connectivity; inspect actual result after interruption instead of restoring twice.

### system_updates

Wave: **W11**. Current: **Missing**.

- [ ] system_updates.1 Show current/running/build version, updater sidecar availability and available update/rollback-regression information.
- [ ] system_updates.2 Implement check/apply, auto interval and release-channel settings with progress and manual instructions when unsupported.
- [ ] system_updates.3 Recover after server restart/network loss and identify completed/failed/unknown update state without issuing a duplicate update.

### system_power

Wave: **W11**. Current: **Missing**.

- [ ] system_power.1 Implement supported restart/shutdown with explicit server identity and meaningful confirmation.
- [ ] system_power.2 Show acknowledged/unknown request and later health/reconnect progress; shutdown intentionally prevents immediate reconnect.
- [ ] system_power.3 Retain local drafts and secure state through disappearance/restart; do not automatically resend a power action.

### wifi_management

Wave: **W11**. Current: **Missing**.

- [ ] wifi_management.1 Capability-gate Wi-Fi status/scan/saved profiles/connect/disconnect/forget and password entry.
- [ ] wifi_management.2 Explain expected lost connection and offer address/discovery/manual recovery after network changes.
- [ ] wifi_management.3 Handle unsupported host, permission/helper error, wrong credentials, interrupted apply and duplicate action risk.

### diagnostics

Wave: **W11**. Current: **Missing**.

- [ ] diagnostics.1 Implement available blank/fill/info/test-board operations with captured hardware destination and confirmation.
- [ ] diagnostics.2 Expose cache statistics/system/network verdicts and explicit POST /debug/clear-cache; gate supported hosts and applicable confirmation, handle success/refusal/unknown outcomes and authoritative follow-up without replay.
- [ ] diagnostics.3 Redact exported diagnostics and accurately explain unsupported live-log features instead of fabricating a log API.

### native_connection_management

Wave: **W1**. Current: **Partial**.

- [ ] native_connection_management.1 Add/name/edit/remove saved servers; paste/normalize hostname/IP/port/scheme/prefix with validated localHTTP choice.
- [ ] native_connection_management.2 Browse actual HTTP Bonjour service/TXT, resolve IPv4/IPv6 candidates, verify discover identity and handle multiples/stale addresses/no multicast/cancel.
- [ ] native_connection_management.3 Persist last server/preferred board separately from per-deployment Keychain sessions; wrong identity/address reuse requires explicit reassociation.
- [ ] native_connection_management.4 Provide honest no-results/permission-troubleshooting/manual fallback, QR/share server-link handling and explicit remembered-session choice.

### route_navigation

Wave: **W0–W12**. Current: **Partial**.

- [ ] route_navigation.1 Implement native routes for Home/Library Pages-Collections-Picks/Schedule/Displays/Integrations/AI/Settings/Account/Diagnostics/Help and nested editors.
- [ ] route_navigation.2 Restore scene-specific destination/selection/back stack, including empty/missing/deleted resource and new-versus-existing document.
- [ ] route_navigation.3 Keep scene state outside adaptive geometry branches; resizing or login recovery preserves user intent and captured destination.

### deep_links

Wave: **W1–W12**. Current: **Missing**.

- [ ] deep_links.1 Map web routes, legacy settings aliases/section query/hash, board IDs, new/edit collections/pages and activation routes to safe native destinations.
- [ ] deep_links.2 Preserve allowed post-login destination with server identity; reject foreign-origin/unsafe redirects and invalid/deleted IDs.
- [ ] deep_links.3 Test cold/warm/background launch, another connected scene, OAuth/browser-return links and shared-file activation without losing drafts.

### panel_link_sharing

Wave: **W4**. Current: **Missing**.

- [ ] panel_link_sharing.1 Construct/copy/open long and short viewer URLs with deployment prefix and panel identity.
- [ ] panel_link_sharing.2 Use native sharing and browser handoff without embedding credentials or extra /api in app-document URLs.
- [ ] panel_link_sharing.3 Verify authenticated/unauthenticated recipients, proxy prefixes and removed panels.

### panel_presentation

Wave: **W4**. Current: **Missing**.

- [ ] panel_presentation.1 Provide fullscreen/read-only display presentation with supported font/matrix/backdrop/auto-dim/animation behavior.
- [ ] panel_presentation.2 Handle idle-sleep intent, foreground/background and output refresh without indefinite hidden tasks.
- [ ] panel_presentation.3 Verify short-wide/standing/expanded display use and explicit exit controls, including keyboard/VoiceOver.

### page_library_navigation

Implementation checkpoint: native template creation for split-flap/LED and conditional deletion are reviewed; phone/tablet create→editor→delete journeys passed. Import/export, compatibility browsing and the full acceptance checks below remain open. [Evidence](research/2026-10-28-native-page-lifecycle-verification.md).

Wave: **W5**. Current: **Partial**.

- [ ] page_library_navigation.1 Implement search/filter/sort/grid-list and device/geometry compatibility indicators across pages and Picks.
- [ ] page_library_navigation.2 Keep selection/query/scroll state through edits/import/delete/server switch and window changes.
- [ ] page_library_navigation.3 Expose duplicate/create/share/import actions and lazy thumbnails with loading/error/empty/filtered-empty distinctions.

### editor_document

Wave: **W5**. Current: **Partial**.

- [ ] editor_document.1 Prove rich/plain templates for both split-flap and LED, including their supported tokens/formulas/colors/icons/formatting, line insertion/removal/order/alignment/wrap and cell edits; raw-only LED does not satisfy acceptance.
- [ ] editor_document.2 Support every single/composite/template document shape and unsupported extension preservation under current document/revision protocols.
- [ ] editor_document.3 Preserve IME marked text/caret/selection/dictation/paste/Unicode across validation, rich/plain changes, resizing and server comparison.

### editor_charset

Wave: **W4–W5**. Current: **Missing**.

- [ ] editor_charset.1 Load configured/returned charset and model-specific glyph/color/blank semantics, including code 62 and filled 71.
- [ ] editor_charset.2 Implement geometry-aware visual cell painting/selection and LED spans/icons/formatting without coercing unsupported content.
- [ ] editor_charset.3 Offer readable warnings and accessible editing for unsupported glyphs, overfull layouts and changed target geometry.

### editor_drafts

Wave: **W5–W6**. Current: **Partial**.

- [ ] editor_drafts.1 Support new/existing page and collection durable draft recovery, unsaved navigation protection and explicit local-versus-server save.
- [ ] editor_drafts.2 Checkpoint promised interruption states, isolate scenes/deployments/documents and retire only owned/exact recovered versions.
- [ ] editor_drafts.3 Preserve pre-comparison work, unknown outcomes and acknowledged-save/local-cleanup errors; no silent baseline replacement or replay.

### editor_undo

Wave: **W5**. Current: **Partial**.

- [ ] editor_undo.1 Implement coherent undo/redo for rich/plain/cell/canvas operations with meaningful grouping and keyboard actions.
- [ ] editor_undo.2 Preserve selection/caret and undo across adaptive changes and supported editor mode switches.
- [ ] editor_undo.3 Define reset/adoption/save boundaries and verify token-adjacent/IME/multiline/draw undo without corrupting serialized documents.

### canvas_management

Wave: **W5**. Current: **Missing**.

- [ ] canvas_management.1 Add/remove/select up to eight canvases and edit area/bleed/scale/flow with page-document preservation.
- [ ] canvas_management.2 Maintain layer order/selection and correctly clear/remove fields, including extension/unsupported content behavior.
- [ ] canvas_management.3 Use server rasterization/golden fixtures for target geometry and warnings; never silently flatten or discard another canvas.

### canvas_draw

Wave: **W5**. Current: **Missing**.

- [ ] canvas_draw.1 Implement brush/eraser/bucket/eyedropper/RGB palette, grid and zoom/pan with touch/Pencil where supported.
- [ ] canvas_draw.2 Provide accessible pixel cursor, coordinate/color controls and keyboard alternatives.
- [ ] canvas_draw.3 Verify strokes/palm handling, edge fill, undo, resize and large/eight-canvas memory/latency on actual available hardware.

### canvas_shapes

Wave: **W5**. Current: **Missing**.

- [ ] canvas_shapes.1 Create/edit/remove/reorder supported shapes and parameters with dynamic expressions.
- [ ] canvas_shapes.2 Preserve literal-versus-expression values and expose server validation/render errors per shape.
- [ ] canvas_shapes.3 Verify shape selection, geometry bounds, undo and accessible form equivalents without locally diverging from server rasterization.

### canvas_source

Wave: **W5**. Current: **Missing**.

- [ ] canvas_source.1 Select plugin source variable or arbitrary expression for a canvas with discoverable current labels.
- [ ] canvas_source.2 Preview source rendering/warnings using correct instance/geometry/draft context.
- [ ] canvas_source.3 Handle removed/disabled/unconfigured plugin, invalid expression and slow/missing data without replacing newer source edits.

### calendar_interaction

Wave: **W6**. Current: **Missing**.

- [ ] calendar_interaction.1 Offer calendar and list views with timezone-aware entry selection, drag/move/time resize and accessible forms.
- [ ] calendar_interaction.2 Preserve recurrence semantics and original revisions through calendar edits and conflict reconciliation.
- [ ] calendar_interaction.3 Verify DST repeated/missing hours, overnight/annual/one-off/sun entries, compact keyboard layout and continuous resize.

### collection_rules_editor

Wave: **W6**. Current: **Implemented draft**.

- [ ] collection_rules_editor.1 Verify current-source member ordering, all three modes, expression-rule priority, intervals, fallback and polling fields.
- [ ] collection_rules_editor.2 Reconcile inventory wording about per-page durations with actual current schema before inventing a field; implement any real current-source omission.
- [ ] collection_rules_editor.3 Exercise invalid/missing pages, unsatisfied expressions, random/time boundaries and read-only future fields with runtime UI/VoiceOver.

### oauth_relay_flow

Wave: **W8**. Current: **Missing**.

- [ ] oauth_relay_flow.1 Start server-owned relay authorization, open browser and observe authenticated server status on return/resume.
- [ ] oauth_relay_flow.2 Handle signed single-use callback, direct/LAN/HTTPS/prefixed return, refusal/expiry/error/duplicate completion.
- [ ] oauth_relay_flow.3 Provide manual code/fullURL rescue and keep browser cookies distinct from app cookies; no assumed universal app callback.

### oauth_device_flow

Wave: **W8**. Current: **Missing**.

- [ ] oauth_device_flow.1 Show verification URL/user code and server-owned pending polling status; open browser and support copy.
- [ ] oauth_device_flow.2 Represent approved/expired/denied/failed and provider interval/backoff accurately.
- [ ] oauth_device_flow.3 Resume observation after background/termination where supported without starting another device enrollment.

### oauth_key_exchange_flow

Wave: **W8**. Current: **Missing**.

- [ ] oauth_key_exchange_flow.1 Implement callback and explicit headless pasted-code/fullURL paths bound to the correct pending PKCE flow.
- [ ] oauth_key_exchange_flow.2 Preserve provider/client/connection identity through browser handoff and app resume.
- [ ] oauth_key_exchange_flow.3 Reject stale/duplicate/wrong-flow completion and handle timeout/refusal without silently creating a replacement authorization.

### oauth_plex_flow

Wave: **W8**. Current: **Missing**.

- [ ] oauth_plex_flow.1 Implement Plex PIN browser authorization with server polling and optional prefixed forward URL.
- [ ] oauth_plex_flow.2 Distinguish browser return, observed connection success, PIN expiry/denial/failure.
- [ ] oauth_plex_flow.3 Resume pending observation without issuing another PIN and handle offline/native-session expiry during provider completion.

### oauth_app_registration

Wave: **W8**. Current: **Missing**.

- [ ] oauth_app_registration.1 Edit shared/user client-ID/secret overrides and masked preservation with provider developer instructions.
- [ ] oauth_app_registration.2 Support reconnect, saved paste offer and correct instance/AI-provider connection routing.
- [ ] oauth_app_registration.3 Verify saved/unsaved setting requirements, local/prefixed callback guidance and provider error recovery without exposing secrets.

### ai_staging

Wave: **W10**. Current: **Missing**.

- [ ] ai_staging.1 Show editor AI proposed diffs with explicit apply/reject, questions and approval actions.
- [ ] ai_staging.2 Keep global drawer/editor conversation context and loaded original revisions through staged edits and server tools.
- [ ] ai_staging.3 Test concurrent web/native/AI edits, approved tool completion after cancel and local draft preservation through interrupted streams.

### appearance_theme

Wave: **W12**. Current: **Partial**.

- [ ] appearance_theme.1 Provide persistent app-local light/dark/system selection and consistent semantic branding.
- [ ] appearance_theme.2 Review glass/navigation/toolbar readability over real content and scroll edges with accessibility settings.
- [ ] appearance_theme.3 Preserve separate server/output appearance preferences and test theme changes during active editing/sheets.

### localization

Wave: **W12**. Current: **Missing**.

- [ ] localization.1 Extract native strings and translate/review en/es/fr/de/it/pt/nl/pl/ru/sv/tr/ja/ko/zh, including errors and accessibility labels.
- [ ] localization.2 Implement language persistence and locale-aware dates/numbers/durations while preserving server timezone/output-language settings.
- [ ] localization.3 Test long/CJK text, pluralization, formatting and language changes during drafts/schedules; retain unsupported glyph diagnostics.

### accessibility

Wave: **W12**. Current: **Partial**.

- [ ] accessibility.1 Complete every workflow with VoiceOver, Dynamic Type including largest sizes, hardware keyboard and clear focus restoration/error announcements.
- [ ] accessibility.2 Honor Reduce Motion/Transparency and Increased Contrast; never convey state using only color or animation.
- [ ] accessibility.3 Provide accessible equivalents for cell/canvas/calendar/reorder controls and meaningful unique labels for repeated fields/actions.

### pwa_installation

Wave: **W12–W13**. Current: **Native equivalent missing**.

- [ ] pwa_installation.1 Replace browser install/service-worker behavior with native install/onboarding/update/foreground lifecycle; do not build a fake PWA.
- [ ] pwa_installation.2 Verify cold launch, termination/relaunch, lock/unlock, memory pressure and scene restoration.
- [ ] pwa_installation.3 Guarantee no duplicated command/tool/OAuth action after resume or app update.

### offline_recovery

Wave: **W1–W12**. Current: **Partial**.

- [ ] offline_recovery.1 Show cached-versus-live/stale/offline data, unavailable-server retry and explicit reconnect per deployment.
- [ ] offline_recovery.2 Recover after Wi-Fi/VPN/proxy/server changes, auth revocation and pending remote logout without mixing caches/sessions.
- [ ] offline_recovery.3 Preserve drafts and unresolved mutations; never create an offline mutation replay queue as an implicit recovery mechanism.

### geolocation_permission

Wave: **W11**. Current: **Missing**.

- [ ] geolocation_permission.1 Request native location only from a user-initiated location-setting action and explain the purpose.
- [ ] geolocation_permission.2 Handle granted/denied/restricted/no-fix with manual coordinate fallback.
- [ ] geolocation_permission.3 Save location through existing server settings and confirm timezone/sun/scheduling consequences separately.

### external_plugin_documents

Wave: **W7**. Current: **Missing**.

- [ ] external_plugin_documents.1 Load repository README/manifest screenshots with supported main/master fallbacks and relative URL resolution.
- [ ] external_plugin_documents.2 Use separate external-resource requests without deployment cookies/Authorization and open external links safely.
- [ ] external_plugin_documents.3 Handle invalid/oversized/missing/offline content and accessible loading/text presentation.

### mcp_connector_instructions

Wave: **W9**. Current: **Missing**.

- [ ] mcp_connector_instructions.1 Generate/copy/share native MCP client instructions with correct endpoint host/port/trailing slash and prefix rules.
- [ ] mcp_connector_instructions.2 Integrate one-time token UI without treating MCP transport as a fabricated web REST operation.
- [ ] mcp_connector_instructions.3 Verify redaction and clipboard/share presentation, including no-token/auth-disabled/current-token gate behavior.

### removed_debug_monitor

Wave: **W11**. Current: **Missing**.

- [ ] removed_debug_monitor.1 Provide native diagnostics/help explaining the removed monitor and truthful operator log instructions.
- [ ] removed_debug_monitor.2 Offer copyable commands/support context with correct deployment identification and redacted details.
- [ ] removed_debug_monitor.3 Do not claim an existing live-log/download API where the web only shows instructions.

### adaptive_device_poses

Wave: **W12**. Current: **Partial**.

- [ ] adaptive_device_poses.1 Exercise all workflows at compact portrait, short-wide landscape, intermediate and expanded widths and continuous resizing around actual content breakpoints.
- [ ] adaptive_device_poses.2 Verify iPad split/resizable/multiple scenes and available open/part-folded/seated/tent geometry without hard-coded device/hinge assumptions.
- [ ] adaptive_device_poses.3 Preserve route/server/board/draft/selection/undo/focus/scroll/pending target/AI-OAuth context through geometry changes.
- [ ] adaptive_device_poses.4 Test touch/keyboard/pointer/Pencil as supported, safe-area asymmetry, keyboard-reduced height and large text; record real device/OS/window evidence.

## Explicit current-source workflows added during W0-A

The current-source inventory separates three capabilities that were previously buried in broad rows. These acceptance IDs supplement the original81 headings; parent-row evidence may be reused where it proves the same behavior. No duplicate suite is required merely because two ledger rows reference one capability.

### plugin_color_rules

Wave: **W7**. Current: **Missing**.

- [ ] plugin_color_rules.1 Add/remove per-instance color fields and ordered first-match conditions with current-source numeric/string operators and empty/fallback behavior.
- [ ] plugin_color_rules.2 Edit the supported palette and reorder/remove conditions; display/copy generated field_color variables and verify their rendered use.
- [ ] plugin_color_rules.3 Save/read back through plugin configuration with masked-secret preservation, actionable errors and unknown-outcome reconciliation without automatic retry.

### plugin_json_mapper

Wave: **W7**. Current: **Missing**.

- [ ] plugin_json_mapper.1 Probe the schema-declared JSON endpoint/request fields through server helper contracts with preserved authorized secret context and typed JSON/text/error results.
- [ ] plugin_json_mapper.2 Inspect nested objects/arrays and select paths using the actual server-supported grammar; handle missing/null/empty/unsupported values without inventing a local query evaluator.
- [ ] plugin_json_mapper.3 Add/reorder/delete variable/path/default mapping rows and support both json-path-mapper and generic-data-mapping-helper aliases with stale-result cancellation.

### schema_widgets

Wave: **W3 shared primitives; W7 integration-specific extensions**. Current: **Missing**.

- [ ] schema_widgets.1 Cover sections/visible_when, secret/password preservation, textarea/timezone/page pickers, typed enum/remote-option/nested-object/array fields, explicit null and unknown fields.
- [ ] schema_widgets.2 Provide mode-cards/device-picker/tile-grid native equivalents in draft/saved-board contexts with action results, coordinates/uniqueness, nested fields and geometry binding before output setup is accepted.
- [ ] schema_widgets.3 Verify dependent search/pagination/current labels, validation/focus/accessibility, loading/error/empty states and late-result rejection for every current schema widget family.

## Q0 — Cross-cutting physical, layout and recovery acceptance (W12)

- [ ] Q0-01 Record device/OS/build/window/safe-area/input conditions for every executed case; no assumed hardware or hinge APIs.
- [ ] Q0-02 Exercise smallest supported compact width, normal portrait, keyboard-reduced height and short-wide landscape.
- [ ] Q0-03 Exercise intermediate/expanded layouts and both sides of every actual content breakpoint with continuous resize.
- [ ] Q0-04 Exercise actual iPad split/resizable/fullscreen and multiple independent scenes; open/part-folded/tent/seated cases only on available supporting hardware.
- [ ] Q0-05 Verify all routes, forms, nested sheets, popovers, menus, alerts and confirmations remain reachable without clipped primary actions.
- [ ] Q0-06 Preserve drafts, undo/selection/IME, route/scroll/focus and immutable action targets across rotation/window changes.
- [ ] Q0-07 Complete all workflows using VoiceOver with announced validation/errors, focus return and contextual labels.
- [ ] Q0-08 Complete creation/reorder/calendar/cell/canvas workflows with hardware keyboard and accessible alternatives.
- [ ] Q0-09 Verify pointer and supported Pencil/touch/palm/eraser interactions without requiring them on every device.
- [ ] Q0-10 Audit largest Dynamic Type, increased contrast, reduced transparency/motion and light/dark/system appearance.
- [ ] Q0-11 Review all 14 locales, long names/URLs/errors, CJK composition, scalar-distinct Unicode and unsupported glyph behavior.
- [ ] Q0-12 Exercise lock/unlock, memory pressure, force-quit/relaunch, app update, scene closure and backgrounding during reads/saves/streams/browser auth.
- [ ] Q0-13 Exercise offline/Wi-Fi/VPN/proxy restart and permission recovery; distinguish stale data, not-sent and unknown effect.
- [ ] Q0-14 Verify local-network permission on real devices, including Settings recovery/manual fallback and discovery unavailable on nonadvertising deployments.
- [ ] Q0-15 Verify direct HTTP LAN, HTTPS, ports, IPv4/IPv6 where supported, proxy prefix and TLS termination with correct cookie/Origin behavior.
- [ ] Q0-16 Prove an actual authorized Home Assistant ingress access route/browser-auth bridge; a rewriting-only fixture does not count.
- [ ] Q0-17 Run every renderer golden fixture at thumbnail/full size, including filled 71/configured 62/Note arrays/LED/icons/pixels/canvases/white-board.
- [ ] Q0-18 Measure launch/scroll/edit/stream/render latency, memory/network/foreground energy on the minimum chosen test device.
- [ ] Q0-19 Stress large libraries/schedules/conversations, eight canvases and supported maximum output geometry; set measured regression budgets.
- [ ] Q0-20 Verify cancelled reads/polls/streams do not accumulate tasks or keep offscreen thumbnails animating.
- [ ] Q0-21 Complete physically observed selected/scheduled/silenced/held/override output transitions on authorized hardware.
- [ ] Q0-22 Run a multiwindow web/native/AI/MCP race and restore/conversion invalidation matrix using a disposable server.
- [ ] Q0-23 Independently review credential isolation/redaction, resource revisions, supported-version gates and all unknown-outcome paths.
- [ ] Q0-24 Fix every accepted blocking Astra finding and rerun the affected proof before integrated acceptance.

## R0 — Release and fresh-clone acceptance (W13)

- [ ] R0-01 Reconcile the frozen source, all route/workflow/operation mappings and post-freeze deltas; no unsupported first-party feature is silently omitted.
- [ ] R0-02 Every workflow has named UI, supported capability, code commit, automated/runtime/device evidence and reviewer verdict.
- [ ] R0-03 Every required operation has accepted auth/target/error/side-effect/replay behavior fixtures, not schema-only coverage.
- [ ] R0-04 Supported-server declaration includes exact source-matching hashed auth, OAuth, conditional-write, operation, physical-native and topology evidence.
- [ ] R0-05 Run the genuine --release-ready gate and confirm all required acceptance categories pass with zero invented evidence/cleared-but-unresolved blockers.
- [ ] R0-06 Full relevant CI and clean-clone tests/builds/UI runtime pass at the intended release commit; attach exact toolchain and artifact results.
- [ ] R0-07 Choose production bundle IDs, Apple team/App Store ownership and version/build strategy; preserve local development signing overrides.
- [ ] R0-08 Produce signed Archive, validation and real install/upgrade/uninstall/reinstall results on supported devices.
- [ ] R0-09 Ensure release launch/schemes contain no forced demo, debug URLs, test credentials or accidental development service.
- [ ] R0-10 Provide an honest complete demo/review environment for all workflows with simulated effects clearly labeled.
- [ ] R0-11 Add app icon/assets/localized metadata, current screenshots and device-family layout examples from actual builds.
- [ ] R0-12 Audit borrowed code/fonts/glyph tables/assets and include licenses, attribution and dependency provenance.
- [ ] R0-13 Audit privacy manifest/required-reason APIs/data collection and tracking against actual app/dependency behavior.
- [ ] R0-14 Prepare privacy/support URLs, local-network/location purpose text and diagnostic retention/redaction policy.
- [ ] R0-15 Resolve applicable account/deletion, purchase/business-model, export/encryption, permissions and distribution questions from actual shipped behavior.
- [ ] R0-16 Define supportable server upgrade/downgrade compatibility, migration/recovery and unsupported-version messaging.
- [ ] R0-17 Set up maintained App Review server/account or complete demo plus required physical hardware demonstration/access.
- [ ] R0-18 Run TestFlight acceptance with iPhone/iPad users across supported server/network/input configurations.
- [ ] R0-19 Triage/fix/reverify feedback, accessibility/localization failures, crashes, data-loss and performance regressions.
- [ ] R0-20 Complete independent Astra integrated release review with code, CI and device evidence; code-only approval is insufficient.
- [ ] R0-21 Publish release notes, known host capability requirements and operational help/recovery instructions.
- [ ] R0-22 Present a concrete release artifact/metadata/evidence set for the user's final submission decision.
- [ ] R0-23 Submit/publish only through the separately authorized distribution action.

## Interaction queue — unblock one item without stopping everything

- [x] I0-01 User confirmed fiestapi.local:4420 opens in iPhone Safari on the same Wi-Fi. The Mac-side route still fails for resolved IPv4/IPv6; installed version, native permission/login and physical output proof remain open.
- [ ] I0-02 Observe real iPhone local-network prompt, discovery result, login and selected board; user keeps credential entry local where possible.
- [ ] I0-03 Authorize/run concrete physical-board send/restore/diagnostic and disposable-host destructive acceptance steps when their runbooks/builds are ready.
- [ ] I0-04 Provider/account owner completes real OAuth browser authorization for each supported flow when native UI/test fixtures are ready.
- [ ] I0-05 Supply an authorized actual HA ingress proof environment/access method, which may be a separate test deployment; native route/bridge acceptance remains required even if the user's board uses direct LAN.
- [ ] I0-06 Confirm organization/repository visibility and production Apple ownership/bundle identity when remote/distribution setup is ready.
- [ ] I0-07 Provide actual iPad/Pencil/additional posture hardware or record the unexecuted acceptance requirement; do not replace it with a claim.
- [ ] I0-08 Refresh Claude CLI authentication only if Opus participation is wanted; independent Sol work continues while unavailable.
- [x] I0-09 User approved the completed plan/order on October 28 and requested continuous Sol/Astra execution, explicitly including split-flap and LED rich editing; no repeated approval for routine reversible implementation.
- [ ] I0-10 Final release/distribution action remains explicit after the complete artifact is reviewable.

## Evidence record template

For each accepted work package, create a dated file in docs/research with: stable task/workflow IDs; native commit; server source/build/version; exact fixture hashes; command and result; reviewer/model and verdict; actual UI/device/window/network conditions; physical acknowledgement versus observation; unresolved input/blocker; next independent task. Link it from TASKS.md and the accepted checklist items. Never include account passwords, cookies, provider codes, tokens or personal signing material.

Current work-package state and later discoveries belong in TASKS.md; preserve this document's stable IDs when splitting or refining tasks. If actual refreshed source changes a requirement, record the old/new behavior and source-backed rationale rather than simply deleting the checkbox.

