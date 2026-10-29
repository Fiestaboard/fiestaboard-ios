# Native parity planning audit

This milestone produces a complete, reviewable plan; no product code or supported-server gates were changed. Native source baseline is `116b075`. Two Sol 6.1 read-only audits inspected actual native code, tests, the original 81-workflow inventory, the 10.1.7 source candidate and the focused current-source delta. Astra independently reviews the resulting design/checklist/plan. No Claude CLI contribution or new native runtime acceptance is claimed.

## What exists

The app has manual URL/login, isolated memory sessions, four root tabs, bounded board controls and flap preview, narrow template editing/validation/conditional saves, and substantial native Collections forms/recovery. The October 27 milestone's 186 Swift host tests,29 contract-tool tests,55 isolated backend fixture cases and unsigned app builds remain dated evidence. Seven UI tests compiled; zero executed. Earlier user-reported physical installation does not establish this milestone's full device/feature acceptance.

The native project is integrated on main at 116b075 with the user's21 semantic project/signing changes preserved. It has no configured remote in the inspected checkout. Fresh-clone/CI/release setup is explicitly included in the plan.

## Source-backed planning findings

| Finding | Source / consequence |
| --- | --- |
| Current board commands require exact non-development 10.0.0; collection creation and previews have separate candidates | Kit Service.swift and CollectionEditing.swift; current-server end-to-end control needs its own fixture-backed compatibility change, not a blanket gate removal |
| Login is memory-only and remember_me is false; discovery/setup/admin/OAuth are not native workflows yet | Kit Service.swift, Transport.swift, Models.swift; App WelcomeView/BoardStore; W1 prioritized |
| Auth connection is coupled to other domain loads | BoardStore.connect; optional pages/domain failure must not prevent a healthy authenticated shell |
| Actual Bonjour is HTTP service, not a FiestaBoard-specific service name | Current server src/system/mdns.py: `_http._tcp.local.`, TXT product=FiestaBoard/path=/, default 4420; verify candidates via public discover |
| Native transport lacks bounded Origin/CSRF admin request support | Transport.swift; current server src/auth/browser_routes.py and web/src/lib/api/sessions.ts; cookie login is sufficient in principle but session/device mutations need additional context |
| Legacy-labeled cookie session is accepted for browser-session resolution | Current src/auth/service.py; do not invent an admin bearer need or treat a metadata label as a privilege block |
| Full first-run auth has preference/setup/token-possession/error branches | Current src/auth/routes.py; build the native state machine rather than telling every user to finish in the web app |
| Conditional default uses its own PUT/precondition semantics | Current web/src/lib/api/schedules.ts; board PATCH is not an equivalent revision-aware substitute |
| Forms contain more than primitive schema fields | schema-form.tsx, board-widgets.tsx, integrations._index.tsx: visible_when/sections, device/model widgets, color rules, remote options and JSON mapper are explicit checklist work |
| Source/contract checker is currently single-snapshot | scripts/check-contracts.py; archive/migrate source-bound evidence deliberately rather than mixing source SHAs into a supported declaration |
| Editor/renderer/adaptive implementation is bounded | EditorState/Documents, RawTemplateTextView, BoardOutputView/BoardTables; rich IME/undo/canvas, configured charsets/LED/layers and actual geometry/accessibility proof remain open |
| Some baseline descriptions lag delivered Collections/backend work | README/TASKS/parity/handoff now link authoritative current status; product capability copy is queued with its owning implementation task |

## Current upstream and deployment facts

On October 28, `gh api repos/Fiestaboard/FiestaBoard/commits/main` returned 10.1.17 bump/source `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. A clean git archive was prepared for read-only inspection. The 10.1.7→10.1.17 diff across web and src touched 15 files in total, including dependency/test updates. Focused inspected behavior includes filled-color 71/editor handling, force-set/other form controls and plugin cache-before-breaker recovery. This is a planning target, not proof of complete current contract coverage or deployment compatibility. W0 regenerates the whole source/route/schema/operation inventory.

The user supplied `http://fiestapi.local:4420` as a test instance. Unauthenticated requests to `/api/health`, `/api/discover`, `/api/auth/status` each returned urllib `Errno 65: No route to host`. No account credentials were sent in these probes, no login was attempted and no board/provider operation was invoked. Do not infer DNS failure, wrong password, a stopped server or an installed version from this route error. The plan records an interaction to resolve LAN/VPN/IP/device reachability while isolated implementation continues.

## Planning artifacts and evidence limits

- [Completion design](../superpowers/specs/2026-10-28-native-parity-completion-design.md).
- [Wave/task execution plan](../superpowers/plans/2026-10-28-native-parity-completion.md).
- [Master acceptance checklist](../native-parity-checklist.md):355 open checks, all 81 original workflow IDs, first-controller/cross-feature journeys, clone/CI, physical/adaptive/release and interaction queues.
- TASKS.md is the short active queue, with historical milestone records retained.

Planning validation checks exact 81-ID inclusion, unique checklist task IDs, local links, source inventory integrity and whitespace. Product tests/builds are not rerun for documentation-only changes; the latest actual product test evidence remains the October 27 report. UI/device/network/provider checks stay open. Independent Astra verdict and corrected planning findings are recorded below after review.

## Independent review and final planning validation

Astra's [recorded review](2026-10-28-parity-plan-review.md) initially required three corrections: owned early authenticated-HA route/bridge work, core output widgets before complete output setup, and explicit clear-message-cache mutation acceptance. W0-C, W3-A/output_actions and W11-C/diagnostics now cover them. The focused recheck passed for planning handoff; no immediate user-only design question blocks W0/W1 after the user's plan review. This verdict is not product/runtime/release approval.

Validation executed for these documentation changes: all 81 original parity IDs occur exactly once as master headings;355 unique open acceptance IDs; relative links resolve; contract integrity passed and explicitly remains NOT release ready; git diff --check passed. Existing product suites were not rerun because no product code changed.
