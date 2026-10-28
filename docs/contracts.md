# Mobile API compatibility

FiestaBoard iOS uses the public `/v1` API where it provides the required behavior, with separate first-party adapters for required internal UI operations. Each adapter is accepted only for server releases covered by contract and behavior tests. This is the mobile project's compatibility policy; it does not change the upstream internal API into a stable public API.

## Baseline

The initial candidate is FiestaBoard 10.0.0, commit `2ced809c8fe20d4ac6e5dc6603d691c8cb4e475a`, source tree `4a07aab0018ce14d3d65d00436a0647d2feda614`. Schema generation and source references use a clean Git archive of that commit. The active web checkout contains uncommitted changes and the existing local service reports 9.14.9; neither is used as the candidate fixture server.

The candidate is **not yet a supported app/server pairing**. `Contracts/supported-servers.json` records its status and unresolved acceptance gates. Do not turn this into a broad `>=10.0.0` promise. API additions and fixes may establish a newer minimum before the app ships.

## Why separate adapters

The backend intentionally separates its consumer API from web-only contracts. Adding a second mobile namespace for every web operation would duplicate a large maintenance surface before delivering native features. Version-bounded adapters keep the domain/UI stable while allowing narrowly scoped request/response translation when the server changes.

The alternative of expanding `/v1` to contain all web internals would change its deliberately smaller consumer contract. New public operations remain appropriate when they offer a coherent reusable capability, but are not required merely to rename every existing UI path.

Jev compared these three strategies using the inspected source and the approved full-parity requirement. It recommended bounded adapters (reported confidence 0.98). The decision rests on the separation of contracts and the acceptance tests below, not on that score.

## Acceptance rules

1. Inventory operations by exact method and schema path. `/api` is the reverse-proxy prefix and is joined separately from an optional deployment prefix. Avoid deprecated aliases when their supported successor covers the behavior.
2. Record public/internal surface, authorization, target scope, side effects, replay policy and web workflow references. HTTP method alone does not establish that a request is safe to retry.
3. Snapshot public and internal schemas with source/version/environment hashes. Preserve the internal schema's compatibility warning. Schema validity proves shape, not behavior or safety.
4. Keep unsupported internal operations behind adapters and capabilities. An unrecognized release cannot silently inherit write support based only on a matching major version.
5. Require operation-specific fixtures and isolated behavior tests before claiming runtime verification. Authentication, outcome semantics, errors and partial failures count as part of the contract.
6. Keep fixture integrity and release readiness separate. The default checker can accept an honest candidate inventory; release readiness fails until feature verification, internal adapter acceptance, topology/auth/OAuth proof and physical validation are complete.
7. Before accepting a server release, run the app's contract suite against its exact candidate, review schema/behavior changes, and update the supported pairing. Publishing an app or backend release is separate from generating a new schema snapshot.

## Remaining protocol work

The pinned 10.0.0 baseline lacks atomic revision preconditions. Merged PR [#2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373) now supplies page, collection, schedule/default and participating AI/MCP protection, restore/recovery invalidation, and the separate page-document-v1 preservation contract. Native collection evidence is scoped to source `79edd37d2329eaa34f42081a4d48e87bc04bb455` (10.1.7), archived independently of the original baseline. It does not make every native workflow or a complete app/server release pairing verified.

Native collection updates/deletes require explicit session opt-in, the exact loaded collection-revision-v1 protocol, supported known fields/mode and the original revision. Creation additionally requires the exact non-development 10.1.7 audited candidate, including empty installations. An uncertain creation stays blocked until the user reviews a fresh list and deliberately starts a new draft; the old draft cannot replay. Connection/document contexts prevent same-URL reconnects or comparison reads from supplying a fresh token to stale content. Unknown fields/modes remain inspectable through the known projection with saving disabled. These typed collection models do not promise arbitrary raw JSON preservation.

The Home Assistant test proxy demonstrates path rewriting, not Home Assistant authentication. Native access through an actual ingress-only deployment needs its own authenticated proof. Likewise, the four OAuth flow families require native completion/lifecycle validation; browser callback success alone is insufficient.

These gates remain visible rather than being hidden by a green schema check.

## Experimental page protocol and template evaluation

The development draft now has a separate, narrow page-save adapter. It requires explicit session opt-in and a loaded template page advertising both `edit_protocol: "page-revision-v1"` and a nonempty original `revision`. It sends only supported changed name/fixed-slot template fields plus `expected_revision`; a version string alone cannot enable this operation. The page protocol originated at `dadbc191e7b329a2803f229dcca22914e6a83b6e` and is now included in merged PR #2373. This feature contract does not certify an app/server release pairing or enable board commands.

Board commands retain the exact, non-development 10.0.0 candidate gate. Template validation/rendering uses separate adapters for non-development 10.0.0, 10.1.2 and the scoped 10.1.7 candidate. These explicit evaluation requests can fetch plugin data but never call the live-send route. Unknown internal-API versions remain blocked. HTTP POST alone does not imply mutation: only the two exact evaluation paths have nonmutating error semantics, without automatic retries.

The local document retains unknown JSON/numeric/Unicode content. The merged backend separately advertises page-document-v1 for validated extension-value preservation. The current native page adapter still sends only narrow supported changed fields and does not enable rich editing merely from that new advertisement. A save acknowledges page storage, not physical board output. Running displays may use the changed page during normal operation.

Conflicts and uncertain results preserve local work and require explicit comparison/reload. Readback does not silently rebase an old draft or resend it. Emergency checkpoints on actual authentication/session loss preserve new local work without overwriting a pre-reload draft with unchanged server content. Interactive device, topology and release verification remain separate gates.
