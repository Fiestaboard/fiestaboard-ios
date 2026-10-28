# Native collections milestone verification

The native draft now has Library → Collections with list/search, create/edit/delete, ordered member pages, time/variable/random modes, ordered expressions, fallback and polling, duration bounds, explicit storage confirmation, conflict comparison, and durable local recovery. This continues the approved full-parity project; it does not complete the release inventory.

Backend PR [#2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373) is merged. The scoped collection/create and preview candidate is source `79edd37d2329eaa34f42081a4d48e87bc04bb455`, version 10.1.7. [Contract evidence](2026-10-27-collections-contract.md) verifies source ancestry, eleven source hashes, actual isolated request/response behavior, and boundaries. The original 10.0.0 baseline is retained independently.

## Behavior and access

Existing collection edits/deletes require session opt-in, a supported known-field projection, `collection-revision-v1`, and the original loaded revision. New collection creation also requires the exact audited non-development 10.1.7 candidate. The in-memory demo implements the same draft/uncertainty behaviors without a network session. Page saves, previews and hardware controls retain separate gates; the existing preview adapter additionally accepts the verified 10.1.7 subset.

Store contexts bind connection generation, deployment, document identity and original revision. Same-URL reconnects and late reads cannot authorize an old editor. A list refresh never substitutes a newer revision into a dirty draft. An uncertain POST remains blocked: inspect a fresh list and explicitly start a new draft; the old draft cannot resend. Deletion respects references and never forces dependent changes.

Local recovery keeps each window's own checkpoint and exact Unicode text. Discard/acknowledgement retires only the exact recovered source versions using independent markers; newer writes remain available and another window's source files are not deleted. Explicit comparison/adoption retains the prior local copy independently, including after later new work. Known server acknowledgement remains distinct from local cleanup errors, preventing duplicate writes after a disk error.

## Verification

| Check | Result |
| --- | --- |
| Kit host tests | 65 passed |
| AppState host tests | 46 passed |
| Documents host tests | 25 passed |
| EditorState host tests | 50 passed |
| Total Swift host tests | 186 passed |
| Contract-tool tests and baseline integrity | 29 passed; integrity passed |
| Isolated 10.1.7 backend fixture replay | 55 cases passed in Docker with network disabled |
| Simulator app build | Unsigned build succeeded for arm64/x86_64 |
| iPhone/iPad device SDK build | Unsigned build succeeded |
| Existing UI test target | Build-for-testing succeeded; seven tests compiled, zero executed |
| Independent Astra core review | Passed; two findings fixed and reverified; two adversarial probes passed |
| Independent Astra editor/UI code review | Passed at cc44824; four findings fixed; eighteen external probes passed |

The implementation commits are `47ace60`/`2aa8725` (Kit), `48e114f` (editor/forms), `058ab96` (Store/navigation/project), and `918120b` (source/fixtures). Review corrections are `058ecdd`/`b9f6ce2` (SDK recovery/partial-gateway outcomes) and `11f7f9b`/`cc44824` (draft ownership, reverts, Unicode and source-version lifecycle). Final checks ran after these corrections.

New regression cases were observed failing before their corrections. Root's missing-protocol test exposed an existing-edit-to-create fallback and now forbids it. Astra independently reproduced the reconnect dead-end and a malformed board-shaped partial-502 acknowledgement that incorrectly unlocked collection retries. Editor probes exposed shared recovered-checkpoint ownership, stale intermediate edits after revert, scalar-distinct changes treated as unchanged, and recovered sources that could not be cleared. Original reproductions and additional lifecycle probes pass after the fixes. Jev advised exact-version retirement over deleting another editor's source; the actual source/tests and independent review establish the result.

## To try

Run the shared FiestaBoard scheme in Xcode with its existing `--demo` argument. Open Library → Collections, create a collection from Welcome/Sunny day, choose a selection mode, and confirm the simulated save. Reopen it, reorder members/rules, and try the local recovery/compare flow. [The testing guide](../draft-testing.md) has the walkthrough and iPhone signing steps.

Simulator services refused connections from the managed environment; the desktop Simulator app was also unavailable through the enabled UI surface. No runtime geometry, resize, VoiceOver, device installation, or live-board/provider acceptance is claimed. AppIntents/CoreSimulator diagnostics and SwiftPM manifest-cache warnings did not prevent compilation/tests. Live hardware was not contacted. Main Xcode signing settings are preserved during the documentation/product integration.

Remaining work includes scheduling, richer page/canvas authoring, renderer fidelity, integration forms/OAuth, account/system flows, localization/accessibility, and complete device acceptance. `TASKS.md` keeps these open. Sol 6.1 implemented the tracks; Astra independently reviewed them. Earlier Claude CLI authentication was expired, so no Opus contribution is claimed.
