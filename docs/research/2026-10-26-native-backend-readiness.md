# Native backend preparation handoff

**Historical status, updated October28:** PR #2373 subsequently merged. This document records the pre-merge backend wave and its tests, not the current deployment status. Native Collections was subsequently implemented and reviewed; [its evidence](2026-10-27-native-collections-verification.md) remains scoped. The [complete native checklist](../native-parity-checklist.md) tracks current remaining work and source refresh; the user's deployed server is not yet reachable/verified from this environment.

All identified backend preparation is in the single draft [FiestaBoard PR #2373](https://github.com/Fiestaboard/FiestaBoard/pull/2373), implemented by Sol 6.1 and independently reviewed by Astra. The branch includes upstream 10.1.4. It remains unmerged and has not been deployed to the user's server or hardware.

Completed server scope:

- Runtime revisions and optional conditional REST update/delete for pages, collections, and schedules, including conditional schedule defaults and participating web controls.
- Original revisions carried through AI/MCP reads, drafts, approvals, dispatch, and both editor/global web AI request snapshots. Participating tools require the original token; compatible maintenance/legacy writers still invalidate it.
- `page-document-v1` capability for validated JSON extension values across rich page saves, copies, share/import, and restores. List fields replace whole values; arbitrary numeric spelling and future rendering behavior are not promised.
- Restore/recovery invalidation, stable live store owners, default/primary-board generation handling, and consistent lock order.
- Existing cookie/CSRF/OAuth API access verified with isolated fixtures. No new native authentication bypass or provider callback scheme was needed.

Verification: 14,448 offline Python tests passed across bounded groups (three skipped, 14 external integration tests excluded); full web suite 3,066 passed/seven skipped, plus 148 focused tests after the final AI context correction; type checking and lint passed. Astra's preservation and combined content/tool findings were fixed and independently re-reviewed. See the backend's `docs/development/native-client-readiness-verification.md` for exact source snapshots, corrected failures, and limits.

## Native work still required

The app's existing bounded template-save adapter does not become a rich editor merely because the server adds capabilities. Implement the new collection/schedule/default adapters, rich field editors, safe original-generation drafts, explicit conflict reconciliation, and provider browser/session flows. Preserve the app's existing separate board-control and preview gates; server feature metadata is not universal write authorization.

After the backend is reviewed, merged, and installed, refresh the native fixtures and supported-server matrix against that deployed version, then test real device behavior. Direct/proxy reachability, Home Assistant gateway authentication, all four native OAuth presentations, adaptive layouts, accessibility, performance, and complete feature parity remain tracked in `TASKS.md` and `Contracts/parity.json`.

No native source or Xcode project/signing settings changed during this backend wave. Claude Opus CLI was unavailable earlier because its login had expired; no Opus contribution is claimed. GitHub operations used `gh`, as requested.
