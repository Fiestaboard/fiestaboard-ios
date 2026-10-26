# Native API access: current source findings

Source: FiestaBoard `3a1d6e8b6` (10.1.2), compared with the iOS inventory's `2ced809c8` (10.0.0). This is a source audit, not runtime acceptance.

## Existing access

The current web app is a static React Router SPA (`web/react-router.config.ts`, `ssr: false`). nginx proxies `/api` to FastAPI. No privileged SSR route loader was found. Native feature parity primarily requires adapters for the same authenticated APIs, including version-bounded internal routes; a separate mobile API namespace is not justified by this audit.

Existing surfaces already provide:

- Page/template preview, validation, line metadata, canvases and charset warnings (`src/templates/routes.py`, `src/pages/routes.py`). The internal render operation has inputs absent from the public v1 wrapper.
- Output catalog, capabilities, JSON schemas, device models and character sets (`src/outputs/routes.py`, `src/outputs/models.py`).
- Per-board scheduling/polling settings (`src/settings/routes.py`, `src/schedules/routes.py`).
- Cookie-session administration, CSRF context and OAuth start/status/manual completion (`src/auth`, `src/oauth/routes.py`). These require topology and lifecycle tests; TV/MCP bearer tokens do not replace administrator sessions.

Plugin documentation is fetched from public repository content by the browser. Renderer constants are bundled in the web client. Neither is hidden server-side data. Home Assistant's upstream authentication is a separate connectivity requirement; a guessed FiestaBoard endpoint cannot bypass it.

## Backend work

The user authorized one ongoing draft PR for API gaps. The first patch is page revision/precondition support shared by public and legacy routes and the storage lock, with web editor revision carriage. This prevents a participating editor from silently overwriting intervening changes. Tests must include both save orders, unconditional legacy writers, delete/recreate, restart and restore.

Collection/schedule revisions remain follow-up work before their native editors are ready. Unknown-field preservation and all participating AI/MCP writers also remain explicit release gates. A page revision field alone does not prove a complete lossless document or concurrency contract.

## Version delta

The committed 10.0.0 → 10.1.2 diff does not change auth routes, page GET/models/storage, or the v1 board route signatures. It changes per-board polling and schedule re-enable behavior in their dependencies. Source similarity does not establish runtime compatibility.

The app keeps its existing exact 10.0.0 candidate write gate. Before adding a version, run isolated fixtures for auth/root-and-prefix URLs, primary/secondary board targeting, sparse PATCH/null clearing, per-board cadence/defer behavior, and send/restore held/refused/partial/unknown outcomes. The new page protocol needs its own audited server fixture before native publishing is enabled.

## Next native integration

1. Consume the reviewed page precondition contract with explicit conflict/reload/duplicate handling and changed-field writes.
2. Add existing template validation/render operations for editor previews.
3. Continue typed settings/output/OAuth adapters alongside their feature milestones in `TASKS.md`.

No live server or physical board was mutated by this audit. It does not certify full parity, API stability, or release readiness.
