# Independent Astra builder/completeness review

Verdict: **CORRECTIONS REQUIRED before plan handoff**. One P1 ownership/feasibility gap and two P2 concrete coverage/dependency corrections. The overall program is buildable; these are bounded plan edits, not a request for a complete future DTO design or another architecture discussion.

Reviewed 2026-10-28: the completion design, execution plan and all 355 master-checklist checkboxes in `/Users/jeffre/workspace/fiestaboard-ios/.worktrees/foundation`; `Contracts/parity.json`; the approved October 25 design; both `/private/tmp/fiestaboard-parity-{web,native}-audit.md` audits; selected original source under `.reference/FiestaBoard-v10.1.17` at `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. Read-only review; no app/server/provider/hardware operations or product implementation performed. No test pass or runtime approval is claimed.

## Required corrections

### P1 — Give authenticated Home Assistant ingress an early owner and executable task

**Evidence:** The approved design's “Server and authentication contracts” explicitly requires milestone 0 to validate an authorized native access route or supported upstream browser-auth bridge. The new design retains this as required (line 49), and the checklist requires actual proof at Q0-16 (line 759). However, W0-A/B have no ingress feasibility output; W1 only defines FiestaBoard bootstrap/session restoration; W8 is provider OAuth; W12-A is route/lifecycle handling. No work package produces the upstream authentication transport/bridge. The interaction queue's I0-05 (line 801) additionally makes access conditional on whether the user's own topology uses it, while Q0-16 and the design make release proof required.

**Why it matters:** A late physical-proof checkbox cannot implement an upstream login route. Whether an ingress-only install can be accessed natively can affect credential stores, browser continuation, redirects, Origin, URL identity and session restoration. Discovering an unsupported bridge at W12 risks revisiting the W1 transport foundation. This was explicitly an early requirement in the approved spec.

**Correction:** Add an owned W0/W1 ingress feasibility task with source-backed supported-route/bridge decision and declared transport/session contract, followed by the bounded implementation/proof task. Name its dependencies on connection restoration, redirects/Origin and browser handling. Keep a missing authorized HA environment recorded as blocked *proof*, allow direct-LAN development to continue, and do not let I0-05 silently waive the required release category. If actual evidence proves a server/HA-side change is necessary, record that concrete dependency before claiming the native architecture covers it. No need to invent the bridge now or solicit credentials in chat.

**Paths:** `docs/superpowers/specs/2026-10-25-fiestaboard-ios-design.md` (Server and authentication contracts); `docs/superpowers/specs/2026-10-28-native-parity-completion-design.md:49`; `docs/superpowers/plans/2026-10-28-native-parity-completion.md:78`, `:90`, `:208`, `:217`; `docs/native-parity-checklist.md:759`, `:801`.

### P2 — Put the core board widgets before the output-setup milestone

**Evidence:** W3 promises empty install through a configured/tested output. W3-A enumerates generic schema handling, but the only explicit “output widgets” deliverable appears later in W7-B. Neither the checklist nor plan names the current core `mode-cards`, `device-picker` or `tile-grid` vocabulary. The pinned web source dispatches these at `web/src/components/plugin-settings/schema-form.tsx:883–958`. `tile-grid` carries board/field-derived rows and columns, per-tile actions, unique fields and nested settings; it is more than an ordinary JSON array. `web/src/components/settings/plugin-board-settings.tsx:84–110` binds device discovery/fallbacks and per-tile actions to these widgets.

**Why it matters:** A builder following the stated order could finish generic schema forms and claim W3 while required model selection, device discovery and tile configuration remain a W7 deliverable. The declared W3 exit and W7 ownership currently disagree.

**Correction:** Explicitly assign those three core widget equivalents and their action/geometry bindings to W3-A/B, with source-bound acceptance for draft and saved-board contexts, returned/secret fields, tile coordinates/uniqueness and stale results. W7-B should consume this foundation and own integration-specific options/helpers/mappers. Add stable checklist acceptance under output creation/actions/configuration. Native controls need equivalent capability, not copied web widgets. Include existing timezone/page-picker vocabulary in the schema capability inventory so the closed set is reviewable.

**Paths:** execution plan `:64`, `:192–193`, `:206`; checklist `output_actions`, `output_board_creation`, `plugins_configuration`; pinned web `web/src/components/plugin-settings/schema-form.tsx:268–269`, `:883–958`; `web/src/components/settings/plugin-board-settings.tsx:84–110`; `src/plugins/settings_ui.py:47–81`.

### P2 — Restore explicit clear-message-cache diagnostics acceptance

**Evidence:** The original `diagnostics` contract includes “clear/cache status.” The new diagnostics checklist only names blank/fill/info/test operations and exposing cache/system/network diagnostics (lines 480–482). The pinned current web has a distinct “clear message cache” button at `web/src/components/settings/debug-settings.tsx:438–459`, calling POST `/debug/clear-cache` via `web/src/lib/api/system.ts:337`.

**Why it matters:** Reading/exposing cache diagnostics does not cover the visible mutation. The plan advertises the human checklist as the complete expanded acceptance scope; this original action should not depend on rediscovery in W0.

**Correction:** Add an explicit diagnostics acceptance item for clear message cache, supported-host gating, applicable confirmation, success/refusal/unknown outcome and authoritative follow-up without replay. Map it to W11-C. Do not infer target semantics before refreshing its fixture.

**Paths:** `Contracts/parity.json` diagnostics row; `docs/native-parity-checklist.md:480–482`; execution plan `:216`; pinned web sources above.

## Builder check: user-only questions

**None prevents a competent builder from beginning W0 and the independent W1 implementation after plan approval.** Source baseline, native architecture, iOS floor, Apple design, universal geometry, full first-release scope and Sol/Astra method are already settled. Exact later DTOs and routine component boundaries can be frozen in wave briefs as the plan says.

Inputs ranked by when they become indispensable:

1. **Before the first real J0 walkthrough:** reachable network route to `fiestapi.local:4420` or replacement address, observed installed version, available signed iPhone build and intended physical target. Prepare the build/runbook first; isolate implementation while access is unavailable. The route error is not evidence of incorrect credentials.
2. **For the early ingress proof and later provider acceptance:** an authorized actual HA environment/access method and provider-account owner interaction. A separate test environment can satisfy HA proof even if the user's board uses direct LAN. Do not silently drop this release category because their deployment does not use it.
3. **When repository/distribution setup becomes concrete:** repository owner/visibility and Apple ownership/bundle identity; later final metadata/assets/business choices and publication authorization. These are already identified and do not block code.

Available iPad/Pencil/posture hardware and physical send/restore/destructive tests are operator/evidence interactions at the appropriate milestone, not reasons to reopen layout policy or pause unrelated tasks. No immediate questionnaire is warranted.

## Checks that passed at the planning level

- All 81 original workflow IDs have exact master-checklist headings. The three connection IDs are represented semantically by W1-A–F even though the execution-plan prose does not repeat their literal IDs; this is not missing implementation scope.
- Source roles are correctly separated: historical 10.0.0 ledger, scoped 10.1.7 fixtures, proposed full 10.1.17 target and unverified deployed version. W0 explicitly refreshes routes, non-barrel calls and runtime fixtures; no false claim that the present ledger already proves 10.1.17 parity.
- Board commands' old exact-version gate is a named first-slice problem, with per-operation evidence required before broadening.
- Session persistence, consent, cookie boundaries, fresh CSRF/Origin, first-run token proof, account/session invalidation and scene isolation have concrete tasks and acceptance.
- Four server-owned OAuth families, app/browser cookie separation, manual rescue, lifecycle observation and non-replayed enrollments are covered. POST SSE, cancellation races, staging and original revisions are covered separately.
- Unknown write outcomes, post-ack local failures, stale-result generations, original revision retention, restore/recreate invalidation and the selection/physical-output distinction are explicitly preserved.
- Rich editor feasibility precedes the full editor; rendering includes current token 71, model charsets, LED/canvas/white-board; native accessibility/locale/geometry acceptance is continuous rather than only a final retrofit.
- Fresh-clone bootstrap, committed project generation checks, preserved signing edits, explicit live/demo schemes, CI execution and truthful runtime evidence are included. No need to require complete future DTOs or reopen routine implementation choices in this program plan.
- Completion remains full frozen-reference parity plus runtime/topology/provider/physical and release evidence; the planning milestone does not pretend to complete the product.

After the three edits above, a focused recheck is sufficient. No broad redesign is requested.

## Focused recheck — final planning verdict

**PASS — ready for user review of the plan.** Rechecked the amended design, execution plan and master checklist on 2026-10-28. All three findings are resolved at the planning level:

- P1: New W0-C names a connection/transport owner, consumes actual upstream configuration and source-bound auth contracts, produces the authorized native route/bridge or explicit upstream dependency, and includes isolation/lifecycle/negative tests plus real HA proof. Missing access leaves proof blocked while direct-LAN work continues. I0-05 and Q0-16 now consistently retain the required topology acceptance.
- P2: W3-A owns the three core board widgets, timezone/page pickers, shared remote options and action/tile/geometry semantics before W3-B. `output_actions.1–.3` carry concrete acceptance. W7-B explicitly consumes those primitives and no longer supplies prerequisites after the output-setup exit.
- P2: `diagnostics.2` explicitly requires POST `/debug/clear-cache`, support gating, applicable confirmation, success/refusal/unknown outcomes and authoritative follow-up without replay. W11-C owns it.

A mechanical inventory recheck returned **355 master checkboxes, 81 original workflow IDs, zero missing workflow headings**. No remaining blocking planning finding or immediate user-only design question was identified. This verdict accepts the planning milestone only; it does not accept an app/server pairing, runtime behavior, real HA access, physical output or release readiness. Product implementation still follows the user's plan-review authorization boundary.
