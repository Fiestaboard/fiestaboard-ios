# W0-C: authorized native access for Home Assistant installations

Status: source-backed early route decision; native integration and actual authorized HA proof remain open. No Home Assistant host, user credentials or provider/hardware endpoint was contacted.

## Source inspected

FiestaBoard core source10.1.17 `b5eac069dce10945eac61e1fdadf6ee4a903ba08`: docs/setup/home-assistant-addon.md, nginx.conf, entrypoint.sh and src/auth/browser_routes.py. Current add-on main was inspected read-only through gh at `d80f98e0ba44a82a0d03e9edc6aa5d090e027712`, version10.1.17-ha.1. Its config.yaml blob is `892a94581bff6c5ac89448c4f50ccb3ae7fcbd31`; DOCS.md blob `0827e9b09b980069cda7190130f9d4b6449a2da7`. The older local add-on checkout was not used as current-release proof and was not modified.

Current add-on configuration enables ingress at internal port3000 and separately publishes container3000/tcp as host4420. FiestaBoard authentication defaults off in this wrapper. These defaults are source facts, not evidence that an operator's install exposes the port or has that authentication preference. Core documentation identifies direct host access as a distinct supported access route.

Home Assistant's [ingress guide](https://contributors.home-assistant.io/apps/guides/ingress/) describes browser requests through `/api/hassio_ingress/<token>/`, where Home Assistant checks the user's session before forwarding to Supervisor. A path prefix alone supplies neither that authorization nor a native session bridge. Do not treat the token-shaped path as an independent stable credential, transfer browser cookies by assumption, or relax Origin/TLS/redirect handling to obtain access.

## Decision and implementation boundary

The first native route for an HA-hosted FiestaBoard installation is the separately operator-published FiestaBoard endpoint (for example a local host:4420, or an operator-managed HTTPS/VPN endpoint) with its actual FiestaBoard auth status and normal deployment-scoped session handling. This uses an existing source-supported access route; it does not require an invented Supervisor token or a TV/MCP credential. App connection UI must explain the difference between the FiestaBoard server address and an HA sidebar/ingress browser URL.

This decision does not accept arbitrary ingress-only access. For an installation whose direct endpoint is disabled or unavailable, require an authorized upstream access method/actual HA environment before selecting and implementing the browser/native bridge. Record it as an explicit topology limitation until proven; no fallback sends credentials to a different origin. A user can continue normal direct-LAN onboarding while this proof is blocked.

W1-A owns clear gateway-HTML/redirect/auth diagnostics and deployment identity; W1-C owns isolated session restore/logout; W1-D owns endpoint guidance. Any real bridge joins that same owner, with a separately reviewed interface for upstream authentication and cookie lifetime. W9 Origin/CSRF is FiestaBoard browser-session administration, not HA upstream authentication. A proxy-path rewriting test cannot close actual HA acceptance.

## Required proof before W0-C/Q0-16 acceptance

- An authorized HA operator confirms actual add-on version/configuration and supplies either the direct native endpoint or the intended upstream access route, without committing secrets.
- Native app connects to that actual endpoint, observes identity/auth, survives reconnect/expiry/logout and performs a specifically authorized fixture/test action.
- Local topology fixtures cover allowed/denied/expired/cross-origin and prefix handling without credential leakage. Native transport tests cover refusing unexpected redirects and preventing endpoint reassociation from adopting another session.
- If actual ingress-only access is required, implement and test the chosen upstream bridge against the real flow, including native/browser separation, suspension/resume and expiry/revocation.
- Astra reviews the resulting implementation/evidence. Until then, W0-C physical/authenticated-topology proof remains blocked, not complete or waived.

One actual Jev advisory compared direct-endpoint-first with implementing an upstream ingress bridge before real HA access and selected direct-endpoint-first. Advice is not proof: inspected source establishes the route, and actual authorization/device tests still establish acceptance. Required HA proof remains open.
