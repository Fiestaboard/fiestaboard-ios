# Native first-release parity inventory

**Historical source audit:** the inventory below is pinned to10.0.0. It is not a claim that later backend work remains unimplemented. PR #2373 is merged; scoped10.1.7 native collection evidence exists. The [October28 master checklist](native-parity-checklist.md) expands all81 IDs, tracks current native subsets and proposes full refresh to10.1.17/source `b5eac069dce10945eac61e1fdadf6ee4a903ba08`. Preserve this original source evidence while executing that migration. All rows still lack complete release acceptance; see TASKS.md for current milestone results rather than inferring code progress from the old planned statuses.

Reference: clean FiestaBoard v10.0.0 source commit `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a`, archived at `.reference/FiestaBoard-v10`. Every source path and line below is relative to that archive. The sibling development checkout is not evidence. Full parity remains a first-release requirement, including all useful compact/open/folded/seated/standing device poses.

`Contracts/parity.json` records **81 workflows**. `Contracts/operations.json` records **198 unique method/path pairs**, of which **22 are public and 176 internal**. The operations preserve every API client function (including compatibility aliases) in notes and cite each original call site. Thirteen workflows explicitly need no server operation; other local/editor/browser workflows link to their shared existing transport. All rows are **planned**, all contracts **candidate/schema_only**. Source/schema matching is not runtime proof, mobile support, compatibility approval or a shipping sign-off.

The bounded audit covers the 19 modules in `web/src/lib/api`, their API barrel, all configured routes, and non-barrel fetch/stream/download/external-image paths. The authored method/path pairs were compared against the exported clean-source `public-openapi.json` (36 operations) and `mobile-internal-openapi.json` (278 operations): every one exists in the latter and the 22 public labels match the former. The inventory deliberately does not copy every backend route. Backend-only functions such as manual rollback or page-cache HTTP controls are not invented as web actions.

## Route and interaction coverage

The route authority is `web/app/routes.ts:7–36`. Layout modules are retained as navigation context, even when they do not fetch independently.

| Web destination | Required native capability | Principal parity IDs |
|---|---|---|
| `/` | Setup/boot recovery; actual versus selected, scheduled, paused, held, silence and temporary output; explicit target controls | `connection_boot`, `home_state`, `home_commands`, `temporary_override` |
| `/login` | Auth disabled/undecided/setup-required/signed-in states, first-run preference, administrator setup, remember-me login and safe redirect | `auth_onboarding`, `account_credentials` |
| `/activate` | Read/enter activation code, inspect device, approve/deny, expiry/denial and enrollment enablement | `device_activation`, `session_management` |
| `/profile` | Profile route/settings equivalence and account controls | `account_credentials`, `appearance_theme`, `localization` |
| `/settings` | General/account/network/scheduling/AI/system/advanced sections, capability gates, legacy section aliases and hashes | all settings/admin rows; `deep_links` |
| `/collections` | CRUD, order, time/variable/random rules, durations/defaults, resolution and invalid references | `collections`, `collection_rules_editor` |
| `/debug` | Existing removed-monitor explanation and operator `docker logs fiestaboard` instruction | `removed_debug_monitor` |
| `/displays`, `/displays/:boardId` | Display catalog/add/edit/remove, model/schema/actions, credentials, pause/schedule/default page, geometry/retargeting, panel and kiosk | display/setup rows |
| `/picks` | Device filtering, plugin prerequisites, preview/share retrieval and pick import | `staff_picks`, `page_sharing` |
| `/integrations`, `/integrations/:pluginId` | Installed/registry/Git views, schema settings/remote options, instances, OAuth, variables/data/errors/demos and updates/provenance | integration rows |
| `/pages`, `/pages/new`, `/pages/edit`, `/pages/edit/:id` | Library search/filter/sort/grid/list; all page types; duplicate/import/export; rich/plain/cell/canvas editing, undo/drafts/previews/live mode | page/editor/canvas rows |
| `/schedule` | Calendar/list, form/drag/resize, CRUD/toggle, board defaults/enablement, recurrence, sun/timezones, overlaps/gaps and silence | schedule rows |
| `/panel/:panelId`, `/p/:panelId` | Standalone viewer, frames and presentation, sharing/opening the browser-compatible viewer URL | `panel_viewer`, `panel_presentation`, `panel_link_sharing` |
| `/offline` | Honest offline/retry/reconnect state and lifecycle recovery | `offline_recovery`, `pwa_installation` |

Page kinds are exactly `single`, `composite`, `template` (`web/src/lib/api/shared.ts:11`; `src/pages/models.py:38`). Geometry includes flagship, Note, Note arrays, arbitrary panels and plugin/LED charset semantics. Canvas transport is the page's existing `canvases` field; `web/src/lib/api/canvas.ts` declares types, not a standalone canvas HTTP API. The canvas inspector adds/removes/selects up to eight (`web/src/components/canvas-editor/canvases-panel.tsx:100–134`), while Draw/Shapes/Source are local authoring surfaces backed by existing page save and server render calls.

Native equivalents are recorded rather than omitted: browser-origin connection becomes per-deployment server management; routes/URL queries/hashes become native routes/deep links; local theme becomes native theme; service worker/install prompt becomes native lifecycle/install; browser location becomes native permission/manual location; browser clipboard/download/upload becomes native copy/share/import/export; browser fullscreen/panel rendering becomes native presentation. Fourteen locales are explicit: en, es, fr, de, it, pt, nl, pl, ru, sv, tr, ja, ko, zh (`web/src/i18n/config.ts:1`). Web accessibility includes focus restoration and error focus in login (`web/app/routes/login.tsx:13–23`), skip-to-content, labeled controls and persisted server `reduce_motion` (`web/src/components/settings/accessibility-settings.tsx:31–40`); native VoiceOver/Dynamic Type/system motion/transparency/contrast and accessible alternatives must be verified.

## Calls beyond the API barrel

| Source | Actual transport/equivalence |
|---|---|
| `web/app/routes/login.tsx:59,165,212,236` | Direct GET auth status and POST login/setup/preference; credentials included; no barrel-only inventory can capture setup/login. |
| `web/src/components/boot-gate.tsx:54` | Direct GET `/health` before the authenticated app loads. |
| `web/src/lib/api/sessions.ts:50–58` | GET `/auth/sessions/context` then portal-origin/CSRF-protected mutations; context is a helper, not an object property. |
| `web/src/lib/api-stream.ts:69–84,117–154` | POST `/pages/ai/chat` as SSE; text/status/tool_streaming/tool_call/tool_result/elicitation/warning/error/done; no automatic reconnect/replay. |
| `web/src/lib/api/ai.ts:182,231` | Direct generate fetch and conversation export URL. |
| `web/src/lib/api/system.ts:356,376` | Backup download URL and import body with `reinstall_plugins` query option. |
| `web/src/components/plugin-settings/oauth-connection.tsx:255–293` | Provider browser navigation/new tab, server connection-list polling and manual completion; relay callback is an HTTP leg despite no fetch call to it. |
| `web/src/lib/github.ts:47,94,105–121` | External raw GitHub README/manifest and derived screenshot image URLs, including main/master fallback. Native external resources need safe loading and credential isolation; they are not FiestaBoard schema operations. |
| `web/src/components/settings/mcp-settings.tsx:46–72` | Produces MCP endpoint/client instructions. The web does not invoke MCP transport; do not fabricate a REST operation. Preserve host/port/trailing slash and validate prefixed deployments. |
| `web/src/components/settings/fiestapanel-settings.tsx:91,374` | Browser viewer URL construction/copy, represented by native sharing plus existing panel reads. |

Images used to render board previews are local board/cell/layer components or plugin/repository assets, not an omitted generic preview-image HTTP API. The ledger includes JSON panel frames, template/page render responses, share/export URLs and the AI POST stream. Arbitrary user/provider/plugin links remain external browser content, not server API paths.

## Public/legacy/internal distinction

`src/v1/visibility.py:55–60,139–146` publishes `/v1` plus only `POST /send-message` and `POST /refresh`; all other web operations are internal. The full schema explicitly has no consumer compatibility promise (`src/v1/visibility.py:78–93`). Public does not mean anonymous. The mobile API release gate therefore remains stabilization/versioning or an explicitly version-bounded first-party adapter for the 176 required internal operations, with behavior/compatibility proof.

| Web migration in the pinned source | Existing legacy predecessor / semantics |
|---|---|
| `/v1/pages*`, `/v1/collections*`, `/v1/schedules*` | Legacy noun CRUD paths; delegates to existing handlers (`src/v1/routes_content.py:63,109,144,189,222,267`). Exact parameter names remain `{page_id}`, `{collection_id}`, `{schedule_id}`. |
| `PATCH /v1/boards/{board}` | Combines pause, default page and schedule-enabled settings; `primary` alias supported. The web functions remain individually named in operation notes (`web/src/lib/api/boards.ts:644`; `schedules.ts:303,309`). |
| `POST /v1/boards/{board}/message` | Replaces legacy `/send-message`; legacy endpoint remains public/deprecated, but the web uses v1 (`web/src/lib/api/boards.ts:582`; `src/board_api/routes.py:283–300`). |
| `POST /v1/boards/{board}/restore` | Explicit restoration of what this board should display; held/silence/pause/refusal remain distinct (`web/src/lib/api/boards.ts:580`). |
| `GET/PATCH /v1/plugins/{plugin_id}` | Detail plus legacy config/enable/disable consolidation (`web/src/lib/api/plugins.ts:272–300`). |
| `GET /v1/plugins/{plugin_id}/data` | Supersedes deprecated `GET /displays/{display_type}/raw` (`web/src/lib/api/plugins.ts:267–270`). Raw batch is still used separately. |
| `/v1/variables`, `/v1/functions` | Variables merges legacy template/plugin sources; function discovery remains public (`web/src/lib/api/templates.ts:146–152`). |
| `GET /v1/status` | Same status handler as legacy `/status` (`web/src/lib/api/system.ts:288–289`). |
| `/config/board` GET/PUT | Still used by compatibility aliases and setup; deprecated legacy config is retained in the ledger (`web/src/lib/api/boards.ts:603–615`; `src/config_api/routes.py:157–180`). |

Methods/paths exclude nginx's `/api` and query strings. Query/body semantics still matter: optional `board_id`, default-primary resolution, force reads, target geometry, `override_silence`, preview batches, schedule validation, backup reinstall, remote-option search/context and conversation search are preserved in client references/notes and must be exercised by behavior fixtures. Do not mechanically swap an internal action for a similarly named v1 operation without preserving request and outcome semantics.

## State and replay gaps

A selected page save may persist even when immediate output is silenced, paused, UI-only, unchanged or failed (`src/settings/routes.py:617–637`). Primary board current-message can use live polling; secondary boards use last-sent/polled runtime cache, and paused boards remain hands-off (`src/board_api/routes.py:129–164`). Native UI must distinguish current output, remembered external frame, selected/resolved page, schedule, temporary override, held queue, pause and silence. A send acknowledgment alone is not physical readback.

Five concrete state-mutating GETs are **not** safe reads in the ledger:

- `GET /settings/temporary-override` auto-clears an expired persisted override (`src/settings/service.py:2695–2716`).
- `GET /schedules/active/page` calls the same getter to include countdown/override status, so it also clears and persists expired overrides, even when scheduling is disabled (`src/schedules/routes.py:209`; `src/settings/service.py:2695–2716`).
- `GET /auth/sessions/context` issues CSRF context (`src/auth/session_routes.py:17–19`).
- `GET /oauth/callback` pops a valid matched pending state before denial/provider-error/missing-code handling; successful completion exchanges the provider code, persists tokens and invalidates provider data (`src/oauth/service.py:730–775,829–850`). Denied/error/exchange-failed outcomes consume that attempt too; it is `mixed/explicit_only`, never automatically replayed.
- `GET /auth/sessions` invokes persisted cleanup of expired session/CSRF/challenge/rate-limit records before listing (`src/auth/session_store.py:82–88,141–148`).

GETs that probe network/provider/device state are conservatively `external/explicit_only`, including current-message, current-display, provider models/data, update checks/status and network diagnostics. Current-display returns raw text/metadata for a template page with stored template, but single/composite/fallback pages force a fresh preview, fan out to plugins and replace the preview cache (`src/pages/routes.py:167–174`; `src/pages/service.py:849–854`); that page-type-dependent GET is `external/explicit_only`. This classification is intentionally conservative until behavior proof. Plain read operations use `safe_read`; every mutation/stream is `explicit_only`. Authentication may also update last-active telemetry on otherwise read-only requests (`src/auth/session_store.py:109–122`); this incidental shared middleware bookkeeping is distinguished from the operation-specific mutations above. Ambiguous timeout never authorizes automatic replay of hardware send, installation, restore, update/restart/shutdown, OAuth enrollment or AI tools. POST server preview/validation can be semantically read-only while still remaining explicit-only in this initial ledger.

## Shared revision/precondition release gate

Atomic JSON replacement and process locks already exist (`src/storage/json_store.py:173–219`); they do not reject stale editors. The v10 page/collection/schedule update signatures accept only an ID and update dictionary, merge unconditionally and assign `updated_at`. Timestamp assignment is not an atomic compare-and-swap precondition.

| Writer / entry point | Clean source evidence | Required shared revision boundary |
|---|---|---|
| Page create/update/delete | `src/pages/storage.py:403,429,442,486`; service `src/pages/service.py:181,217,297` | Validate expected revision under `self._store.lock` before mutating the current record; advance revision on create/update/delete and persist atomically. Read/DTO must expose revision. |
| Collection create/update/delete | `src/collections/storage.py:254,266,270,292`; service `src/collections/service.py:71–93` | Same lock-scoped precondition and revision advance; preserve rules/config unknown fields. |
| Schedule create/update/delete/default-page | `src/schedules/storage.py:259,274,287,327,368`; service `src/schedules/service.py:88,123,159,350` | Same atomic boundary; also account for default-page state stored in schedules document. |
| Public and legacy REST | `src/v1/routes_content.py:109,189,267`; legacy `src/pages/routes.py:254`, `collections/routes.py:148`, `schedules/routes.py:358` | Both surfaces must route to the same revision-aware persistence; participating clients send a precondition. Unconditional legacy writes remain an explicit limitation unless prohibited/versioned. |
| Web native-form saves | `web/src/lib/api/pages.ts:258`, `collections.ts:92`, `schedules.ts:275` | No precondition is sent in v10. All first-party saves must carry the shared revision; a pre-save GET alone is insufficient. |
| AI/MCP tools | `src/ops/executors.py:440,1213,1489`; `src/mcp_server.py:1333,1996,2165`; `src/ai/mcp_bridge.py:1` | Executors use common services. Add revision carriage to participating tool grammar/arguments and shared persistence; staged local editor edits keep their loaded base revision until explicit save. |
| Page share import | `src/pages/routes.py:350–374` and `src/pages/service.py:181` | Create new resource/revision through common storage; import/replacement distinction must be explicit. |
| Demo/default/replacement pages | `src/pages/service.py:356,371,406,442–447` | Storage create/delete paths must advance revisions even when the normal form route is bypassed. Demo replacement must not resurrect stale revisions. |
| Geometry retargeting | `src/pages/retarget.py:41,81`; `src/panels/content_resize.py:185–198` | Service/storage writes participate; geometry copies receive new resource revisions and modified references advance existing revisions. |
| Conversion rollback/startup recovery | `src/panels/content_resize.py:224–226`; `src/panels/content_resize_recovery.py:205–207` | Direct `_schedules` replacement and `_save` bypass regular update. Explicit recovery semantics must advance/invalidate revisions; never restore a stale revision token from the journal. |
| Backup restore | `src/backup/service.py:126,194–195,253–291,301–343,509–545` | Restore writes files directly under owner locks, then reloads services. It must deliberately reset/advance a store generation or reassign revisions so pre-restore tokens cannot become valid; preserve per-file failure/reload reporting. |
| Initial load/migrations/legacy collection import | `src/pages/storage.py:296–341`; `collections/storage.py:90,165–213`; `schedules/storage.py:130–182` | Migrate/init revision metadata coherently without reusing versions from previous data generations. |

The best precise introduction points are the three storage mutation locks plus their shared serialized revision representation, not a single UI route. `AtomicJSONStore.save` knows the file, not the semantic record/precondition. Restore/recovery bypasses require an explicit generation/replacement rule. Include both save orders across web/native/AI, stale delete, deletion/recreation, restore while editing, conversion recovery and legacy unconditional writers. Offer reload/duplicate/deliberate conflict resolution before claiming stale-save protection.

## OAuth completion and lifecycle release gate

The four declared flows are real (`web/src/lib/api/oauth.ts:9`; `src/oauth/service.py:501–531`). The server owns provider credentials and pending state; native code must not substitute TV device bearer authorization or treat all flows as app callbacks.

| Flow | Pinned mechanism and evidence | Native proof still required |
|---|---|---|
| `relay` | Server builds signed single-use state and provider redirect (`src/oauth/service.py:533–580`); callback consumes pending state (`:718–735`); public GET callback redirects relatively to browser integrations or AI settings (`src/oauth/routes.py:135–185`). | Direct/LAN/HTTPS and prefixed browser return, denied/expired/duplicate state, manual full URL/code rescue, app suspension and authenticated native status refresh. |
| `device` | Server device code start and background polling (`src/oauth/service.py:681–713,855–913`); web displays verification URI/code and polls connection list (`web/src/components/plugin-settings/oauth-connection.tsx:14,236–250`). | Pending/approved/expired/denied/failed state mapping, suspend/resume/poll cancellation and avoiding duplicate enrollment. |
| `key_exchange` | PKCE key exchange can use callback or `headless` bare-code paste (`src/oauth/service.py:592–630`; UI headless option `web/src/components/plugin-settings/oauth-connection.tsx:589`). | Callback/headless variants, bare code/full address paste, PKCE association, stale/duplicate paste and resumed flow. |
| `plex_pin` | Provider browser PIN and server polling; optional `board_url/integrations` forward (`src/oauth/service.py:635–659,926–946`). | Browser completion versus polling, PIN expiry/denial and prefixed return, resumed polling without extra PIN. |

`POST /oauth/connections/{connection_id}/complete` is the existing authenticated manual-paste contract (`src/oauth/routes.py:114–129`); no native URL-scheme callback is declared. Browser `boardAddress()` includes origin plus prefix (`web/src/lib/api/oauth.ts:87–96`). Web paste offers survive same-tab navigation through session storage (`web/src/components/plugin-settings/oauth-connection.tsx:118–138`), focus the returning paste field, and distinguish mandatory paste (ChatGPT loopback redirect) from rescue. Client ID/secret registration fields, shared/user apps, scopes, expiry/reconnect reasons, instances and `ai.<provider_id>` are all parity requirements. Native must retain analogous pending-flow identity across suspension without persisting provider secrets.

## Authentication, prefixes and Home Assistant gate

Cookie-session authentication and API bearer authorization are different capabilities. `src/auth/middleware.py:70–114` exempts bootstrap/auth/callback paths from the middleware but individual auth handlers still enforce their own gates. The middleware has a separate limited `fb_tv_` allowlist for panel reads and six presentation PATCH fields (`src/auth/middleware.py:214–253`); those tokens are not controller sessions. Enabling login/provisioning an unclaimed install also requires possession of an existing stored MCP token when configured (`src/auth/routes.py:211–242`), which the web setup request does not automatically supply. Device/session management requires a real browser-session cookie and rejects an `Authorization` header (`src/auth/browser_routes.py:15–23`), then requires a normalized allowed portal Origin and valid `x-csrf-token` for mutations (`:26–54`). A URLSession client can supply headers, but native cookies, Origin/proxy behavior and account/session generation must be validated; advertising parity from schema alone is unsafe.

`web/src/lib/base-path.ts:21–38`, nginx rewriting and the OAuth relative return correctly carry deployment prefixes. That solves routing, not upstream authentication. The HA simulator only rewrites the ingress path and adds headers (`infra/ha-ingress-proxy.conf:9–29`); it has no HA login/session/token authorization layer. The upstream boundary is explicit in the source design: `docs/internal/superpowers/specs/2026-10-18-revocable-sign-ins-design.md:141` says separate HA login is not automatically native-TV-accessible and requires an endpoint both participants can reach. Neither the simulator nor prefix tests establish a native HA browser-auth bridge. Release requires an authorized direct/VPN/server route or a separately supported/tested upstream authentication bridge; record the supported topology honestly.

## Verification and remaining sign-off

Completed: clean-source route/client enumeration; inline transport audit; exact method/path and public/internal reconciliation; non-empty source paths/line bounds; unique stable authored IDs; bidirectional operation/workflow references. No application runtime, physical board, production data or executable application code was touched for this inventory.

Pending release proof: supported internal API policy; typed payload/outcome and unknown-field/null fixtures; all four OAuth lifecycles; cookie/CSRF/proxy/HA topology; shared atomic revision preconditions across every writer; all editor/renderer/charset/canvas fixtures; complete localization/accessibility; offline/ambiguous mutation recovery; native routes/sharing; and compact/expanded/resized/folded/seated/standing device verification. These are explicit verification requirements, not omissions or a reduced first-release scope.
