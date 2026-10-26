# FiestaBoard UI and API audit

## Evidence baseline

Inspected on October 25, 2026. Main source: `../FiestaBoard`, commit `2ced809c8` (10.0.0), with substantial uncommitted work targeting 10.1.0. No source changes were made. The running local server reports **9.14.9**; it is not evidence of v10 runtime compatibility. Read-only `/api/health` and `/api/auth/status` probes succeeded. Authentication is disabled on that server. Browser inspection reached a blank application surface, so this audit makes no claim to have visually validated the running app's screens.

The earlier `../fiestaboard-swift` repository contains a July design only. Its v8 assumptions, API inventory, platform scope and deferred App Store requirement are superseded by this project. `../fiestaboard-appletv` points to `Fiestaboard/fiestaboard-tvos`, commit `a3df9c9`; it contains reusable Swift source. The standalone FiestaUI checkout is older than the web app's declared package `@fiestaboard/ui` 8.14.0 and has dirty files; use the pinned package and fixtures when establishing renderer parity.

## Source map

Paths in this table are relative to `../FiestaBoard`; line references describe the inspected working tree unless marked HEAD.

| Concern | Evidence | Consequence |
|---|---|---|
| Navigation | `web/src/components/navigation-sidebar.tsx:29`, `web/app/routes.ts:8` | Home, Displays, Pages, Collections, Schedule, Integrations, Picks, Settings, account, debug, activation and panel viewer all need coverage. |
| Ongoing refresh | `docs/internal/plans/2026-10-25-ux-refresh-design.md`; HEAD Collections is one route, current tree splits list/new/detail | Adopt useful native equivalents, but pin merged behavior before final parity signoff. |
| HTTP client | `web/src/lib/api/core.ts:101`, `web/src/lib/base-path.ts` | Cookie sessions, ingress base path, 30-second default timeout, structured errors, auth/setup transitions. |
| Public API boundary | `src/v1/visibility.py:70`, `src/api_server.py:475` | `/api/openapi.json` is public; `/api/internal/openapi.json` contains unsupported internal contracts. Full parity cannot be promised from the public schema alone. |
| TV auth restriction | `src/auth/device_models.py:16`, `src/auth/middleware.py:215` | TV client IDs/tokens only grant panel access. Do not masquerade as a TV. |
| Controller cookie path | `src/auth/routes.py:348`, `src/auth/service.py:641`, `src/auth/middleware.py:310` | Current browser/legacy sessions can call broader UI endpoints. Validate independent native session storage. |
| Session administration | `src/auth/browser_routes.py:25` | Some management mutations require an allowed Origin and per-session CSRF token from `/auth/sessions/context`. |
| Board state | `web/src/hooks/use-board.ts:63`, `web/src/lib/api/boards.ts:585` | Selected, actual, paused, held, silenced and scheduled states differ; board IDs must accompany scoped operations. |
| Active page | `web/src/lib/api/pages.ts:34`, `:223` | HTTP success can mean saved selection without a physical send. |
| Page previews | `web/src/lib/api/pages.ts:174`, `:265` | Batch previews return rich cells, bitmap layers and errors. |
| Rich rendering | `web/src/lib/api/templates.ts:174`, `src/v1/routes_meta.py:94` | Public render is not equivalent to internal rich canvas/charset/live rendering. |
| Editor document | `web/src/components/tiptap-template-editor/TipTapTemplateEditor.tsx:68`, `web/src/components/charset-template-editor.tsx:3` | Tokenized template, formatting metadata, two rich editor families, round-trip preservation. |
| Canvas | `web/src/lib/api/canvas.ts:1`, `:69` | Up to eight canvases, pixel/shapes/expression sources, area/bleed/scale/flow; server returns RGBA layers. |
| Editor lifecycle | `web/src/components/page-builder.tsx:925`, `:1182`, `:1372`, `:1503`, `:1882` | Stale-preview cancellation, draft autosave, dirty navigation guard, explicit null clears, live write mode. |
| Collections and schedules | `web/src/lib/api/collections.ts:13`, `web/app/routes/schedule.tsx:234` | Rules, order, cadence, calendars, sun times, timezone and silence interactions are product behavior. |
| Plugin forms | `web/src/components/plugin-settings/schema-form.tsx:1111`, `web/src/lib/api/outputs.ts:169` | Generic schemas, remote options, OAuth, instances, output discovery/actions and marketplace flows. |
| AI | `web/src/lib/api-stream.ts:27`, `:120`, `web/src/lib/api/ai.ts:209` | POST SSE, tool results/questions, conversations, cancellation; no blind replay of mutation-capable streams. |
| Accessibility/locales | `web/src/hooks/use-reduced-motion.ts:5`, `web/src/i18n/config.ts:1` | Live reduced-motion changes and fourteen locales belong in parity inventory. |

## Native reuse

Audit and extract selected code from `../fiestaboard-appletv/Sources/Core/`: `FiestaClient.swift`, `Credentials.swift`, `Discovery.swift`, `BonjourDiscovery.swift`, `BoardSpec.swift`, `BoardTables.swift`, `BoardGeometry.swift`, `MatrixRaster.swift`, `FiestaChat.swift`, and `FiestaClient+Chat.swift`. Rendering references live under `Sources/Render/`. Reuse tests/assets with license notices and a recorded source commit. TV endpoint coverage, fixed client identity, focus navigation, pollers and full-screen rendering assumptions are not controller requirements.

## Apple guidance

- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): native controls adopt the system appearance; support continuously resizable windows.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): glass belongs in navigation/controls, with restraint; content needs a separate readable layer.
- [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/): build with the 27.1 SDK for full layout behavior; window geometry and asymmetric safe areas replace device/orientation assumptions. Test vertical bars and resizing.
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/): standard split navigation, tabs and presentations adapt to poses. Custom edge placement may use reserved-region APIs after SDK validation.
- [Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): declare the usage description and browsed Bonjour services; handle denied access and retry after permission changes.
- [Local networking and ATS](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking): validate local hostname and IP transport behavior on every supported OS; do not use an unrestricted global exception.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/): provide review access and hardware demonstration resources.

Local tools report Xcode 27.1 and iOS/iOS Simulator SDK 27.1. Deployment target and build SDK are separate choices.

## Advisory decision

One real Jev call compared cookie-first, new controller tokens, and dual authentication. It recommended cookie-first with low confidence (0.45), with no contradicted requirements. Source inspection supports feasibility, but proxy/Origin/CSRF and credential-isolation tests remain acceptance gates. Dedicated controller tokens are a future auth improvement, not an assumed prerequisite for the whole app.
