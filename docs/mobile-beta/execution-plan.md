# Native iOS beta execution plan

Status: Astra approved architecture and corrected sequence, 2026-10-31. This is a sustained beta project; reader/physical-preview slice is verified; broader parity is pending. Requirements: requirements-design.md. Traceability: parity-inventory.json (84 existing rows plus flexible deltas). Implementation: /Users/jeffre/workspace/fiestaboard-ios-beta-recovered-20261031, branch codex/mobile-beta, isolated clone of b2e49f9; latest verified navigation checkpoint df6a6af. Original checkout and installed app remain preserved.

## Delivery rule

Every feature row links web/API evidence → native destination → behavioral acceptance → automated test → actual UX evidence → implemented/excluded/blocked. A placeholder is pending, never parity. Capability-driven protocol support replaces exact-version whitelists; a compatible newer server stays enabled. Unknown document families/protocols remain readable but cannot mutate. Where no advertised capability exists, use a documented bounded compatibility guard specific to that operation.

Use existing native SwiftUI navigation, Foundation networking, bounded lossless JSON envelope with typed editing projections, and explicit draft state. No generic sync framework or backend renderer port. Retain iOS minimum deployment target unless a necessary API changes it. Installed Xcode/SDK27.1 is build evidence; runtime and physical-device coverage are separately recorded.

## P0 — Baseline and preservation (completed)

- Inventory existing source, dirty overlay, web main/next and PR2395, prior plans, hardware, installed tools, organization repositories.
- Record exact provenance and existing limitations. No duplicate iOS repository publication.
- Existing four Swift package suites: 314 tests passed. Tooling/contract suites: 71 passed. Project, contract, fixture checks and unsigned generic device build passed.
- Native managed-worktree request timed out after3600seconds without an operation ID/path; isolated local clone used. No repeated creation request.

## P1a — Minimum safe content contract (completed baseline; flexible adapter expands in P3/P4)

1. Intake prepared reader patch once after base/hash and apply checks. Regression first for mixed template/flexible/future families. Strict legacy template geometry remains unchanged. Preserve raw document separately.
2. Review supported document family and protocol at every edit/delete boundary, including store contexts and UI. Missing legacy protocol is explicit backward compatibility; present null/malformed/unknown protocol is unsupported. Future flexible editing enables only its verified protocol.
3. Validate original revisions and sparse request bodies. All page, collection and schedule writes retain original revision; HTTP412 never retries automatically. Unknown outcomes require explicit readback/reconciliation. Keep token, URL, target, session generation and document generation distinct.
4. Exercise lossless nested array replacement with explicit null versus omission, unknown future fields, stable IDs, large integer900719925474099312345678, and original revision. Decode success alone is insufficient.
5. Verify request acceptance across target changes, logout/login to same deployment, reconnect and late responses. Durable drafts must be scoped by verified non-secret account/connection identity; URL/basePath alone and display names/token values are insufficient. If server lacks identity evidence, use connection scope and do not silently recover another session's draft.

Completed reader/preview slice d77cc59: reader patch integrated once; unsupported edit/delete guards, Decodable-only projection, unknown-template read compatibility and explicit physical frames implemented with regression-first tests and Astra review. 328 package tests passed (Kit 153, AppState 84, Editor 55, Documents 36). Project/contract integrity and final unsigned iOS build passed. Mixed-library and physical-preview interactions passed on iPhone 17 Pro Max and iPad Air 11 M4 simulators, iOS 27.0. Synthetic fixtures prove native behavior, not deployed backend or hardware output. Earlier unsigned-Keychain and offscreen test failures were diagnosed and corrected without changing credentials/security.

Evidence lives at /Users/jeffre/Documents/Codex/2026-10-29/task-4/mobile-beta-discovery/evidence/reader-intake; two representative screenshots have confirmed Library uploads (IDs in the local share/library-uploads.json manifest). iPhone screenshot shows complete pixel frame; iPad screenshot records caption-scroll reachability. Legacy template evaluation now uses reviewed stable running versions 10.0.0 through 10.3.2 only, since that endpoint has no advertised capability. This is a bounded contract inference, not testing every intervening release. Durable connection-scoped drafts and explicit recovery/export are reviewed and verified in 000324a + d3021da. The flexible preview adapter remains part of P3/P4.

## Minimal P2 — Native adaptive shell (verified checkpoint)

Keep NavigationSplitView with existing content on regular widths; compact uses an accessible destination list and native navigation stacks. Destinations follow web: Home, Displays, Pages, Collections, Schedule, Integrations, Settings; Staff Picks/help and conditional AI are traceability rows. Separate server Settings from app connection settings. Avoid web chrome, nested decorative cards, and excessive borders.

Validate two real journeys before polishing: Pages→Collections→Schedule and Displays→Playback→back. Preserve destination selection, draft and focus during resize. Use actual window size, not device-name or orientation assumptions. iPhone/iPad required. Duo profile/runtime availability must be verified before claiming coverage; lack of iOS26 runtime is not a Duo conclusion.

Navigation checkpoint 20b2ecd + a381dc4 + df6a6af: current package suites Kit169/AppState94/Documents38/Editor55 = 356 tests pass. Both required cross-section journeys, recovery access connected/disconnected, and editor draft preservation through rotation pass on iPhone 17 Pro Max and iPad Air 11 M4 with iOS 27.0. Schedule is a real read-only list/detail; mutations remain P5. Tablet window resizing and Duo folding are not claimed. The installed Duo device profile requires runtime27.1, while installed iOS runtimes are27.0; no software installation attempted.

## P3/P4 first vertical slice — Physical preview plus flexible text/Canvas

1. Consume backend preview/layout. Explicit physical_frame_version:1, width/height and opaque RGBA determine the surface; character grid dimensions never do. Golden32×8,52×16,64×64 frames verify full bytes and pixel geometry; legacy projection remains unchanged. Unknown physical versions display unsupported without false fallback.
2. Capture targetID + draft generation + session epoch on each preview. Preserve the draft and require target reselection if the selected board is deleted; include deletion while a preview is in flight. Core target semantics are verified at864cfa6b: explicit unknown/empty board_id returns404, omitted/null retains primary default. Pin fixtures to that source; no deployment inferred. Reject stale/out-of-order replies after edits, target changes or reconnect. Preview and validation have independent visible states.
3. Implement one actual flexible text block and Canvas authoring path end to end: read → edit → preview → revision-conditional save → reopen → exact preservation assertion on isolated fixture/server. No raw JSON-only completion claim.
4. First Canvas slice: select source; add text, rectangle and line shapes supported by actual schema; select shape; native inspector; accessible numeric position/size; move/resize buttons equivalent to drag; add/remove/reorder; one undo action per user operation. Native text selection/IME supports variable insertion at current selection. Preserve unsupported shapes/blocks read-only with labels.
5. Numeric fields retain intermediate empty/minus/decimal text while editing. Invalid hidden/collapsed fields keep Save disabled and expose a visible route to the error. Short windows/keyboard allow scroll access to focused controls.
6. Draft state distinguishes local checkpoint from acknowledged server snapshot. Saved only follows acknowledgment and becomes Unsaved on a new edit. Pending/failed/unknown writes never show Saved. Invalid Canvas remains recoverable; undo, dirty state, save/reopen, conflict, resize, keyboard and restart preserve the correct document.
7. Preview, Saved, SendAccepted, Paused, Silenced, Held and Observed are distinct. Adapter-specific acceptance/intended/held evidence must not be described as observed hardware output.

## P1b / P5 — Refresh contracts and finish parity by feature

Refresh each remaining contract immediately before its feature; do not block the first editor on all84 operations, SSE, OAuth or downloads. Work can parallel after interfaces stabilize.

- Home/Displays/Playback: target identity, schedule/manual source, pause/silence/hold, physical/legacy preview, adapter-specific output evidence and board defaults/settings.
- Pages: native CRUD, variables, block styles/conditions/priority/targets, full Canvas tools and accessible nondrag equivalents; legacy exact grid unchanged.
- Collections: CRUD, member ordering, timing/rules, revision conflict, unknown fields and full-list replacement preservation.
- Schedule: CRUD, timezone/DST semantics from server contract, page/collection references, defaults, revision conflicts and ambiguous write recovery.
- Integrations: installed/available catalogs, actual schema-driven native configuration, advertised OAuth, failure/revocation/reconnect. Secrets never leak into fixtures/screenshots.
- Settings: intentional native sections for board/system configuration, session/device administration, server versus local connection settings. Retain exact applicable Origin/CSRF/session contract; block unsupported requests rather than forging headers or weakening checks.
- Staff Picks/help and conditional AI: implement actual supported workflows, document explicit unavailability. No placeholder completion.

Each package uses synthetic fixtures or isolated local test servers for mutations. Lack of production authority does not remove implementation scope. Live production output, OAuth authorization, privileged settings changes and real-session revocation remain separate actions requiring applicable authorization.

## P6 — Device, accessibility and recovery evidence

Run actual compact and tablet app journeys with screenshots and interaction assertions. Cover light/dark, large Dynamic Type, VoiceOver labels/order/actions, hardware/software keyboards, safe areas, modal sizing, resize/fold draft continuity, and reachable controls. Screenshots prove layout, not interaction. Simulator evidence is not physical evidence. Capture sanitized milestones for async user feedback without blocking work.

Device matrix: installed iPhone simulator, installed iPad simulator, available iPhone Duo profile/runtime if verified; physical iPhone/iPad only when separately authorized and available. Record exact model, runtime, SDK, viewport and untested cases. No invented hardware support. Android phone/foldable/tablet coverage is owned by parallel Android lead; share golden contracts and behavior, not UI implementation.

Recovery matrix: offline launch/drafts, session expiry, same-origin account switch, logout/relogin, reconnect, old response, slow/out-of-order preview, server restart, revoked session, invalid Canvas, HTTP404/412, uncertain write. No background mutation replay.

## P7 — Beta gate and publication readiness

- Every parity row has implementation or named exclusion/blocker and evidence; no P0/P1 critical defects.
- Reproducible package, contract, build and UI checks with pinned dependencies; CI matches actual validated commands.
- Independent Astra code/design review of meaningful slices and final beta, with fixes retested.
- Read-only inspect existing organization repositories before any conditional creation; prepare CI/protection configuration locally. Publication only once beta ready under user authorization; actual security approval boundaries still apply. No App Store/TestFlight distribution authorization.
- Deliver beta provenance, installable build only through approved workflow, supported device matrix, known limits, test logs and screenshots. Never claim install/health from build success.

## Current restrictions and independent progress

No new software/runtimes/security settings, physical install, live deployment, merge or production mutations in this phase. Build/test local implementation and isolated fixtures continuously. Native worktree tool timed out without a success receipt; the isolated clone works normally and no creation retry was made. All broad parity and actual UI validation remain pending until demonstrated.

Recovery checkpoint: exact committed and dirty state moved by verified copy out of Documents after cloud-file stalls. Original checkout remains frozen; all1511 files, Git history and dirty diff verified. Evidence /tmp/fb-ios-recovered-git-verification.json. First flexible editor implementation resumed with known compile/test corrections pending; no beta/build completion claim.
