# Collection ownership Task2 — native original-file recovery

Execute only after Task1 independent review passes, using the approved docs/mobile-beta/collection-ownership-plan.md. Reuse the current implementer. Controller owns simulator execution, fixture seeding inside task-owned simulators, generated project, screenshot export and aggregate evidence. No production/device/credential/security actions.

## Ownership and interface

CollectionDraft.swift (or one justified adjacent file), existing LocalDraftRecoveryView in App/Features/Library/LocalPageEditorLoader.swift, focused archive tests, native UI tests. Share the existing CollectionDraftResources archive rather than introducing a competing recovery store; adjust its visibility/location minimally. Preserve page recovery and Task1 scope gates.

Add CollectionDraftRecoveryEntry: stable original file URL identity, optional safely decoded checkpoint, human-readable classification/reason. recoveryInventory() includes scoped, unassigned legacy, future, malformed and retired original checkpoint bytes. Retirement marker metadata is not a draft entry; distinguish it explicitly. Inventory must never create/adopt/rewrite/retire a checkpoint. File ID/content mismatch must be classified untrusted, not scoped. Future formats must not be presented as validated scoped checkpoints merely because JSONDecoder accepts their known fields. An unsupported baseline must retain read-only evidence.

Native List sections Pages and Collections; preserve connected and disconnected recovery routes. A collection row shows safe name or new-collection/ID fallback, ownership classification and original filename. Details show useful baseline/status/revision information without implying active-account ownership; original ShareLink exports the exact file URL. No automatic adoption or server mutation from this inventory. Per-store read failures must not hide the other store's valid inventory. Empty state only when both inventories completed and are empty. Labels/accessibility and standard navigation; no enclosing AX identifiers or nested decorative cards.

## Regression and actual UX evidence

1. Unit tests first: all five archive classes including retired; inventory leaves every byte identical, original export URL is the discovered file, malformed scope/future version never claims active ownership, ID mismatch/unreadable file handling explicit. Existing exact-scope load and model recovery gates remain unchanged.
2. Native same-scope flow: demo or isolated fixture collection, edit name/numeric intermediate, keep local draft, terminate/relaunch/reopen, recover exact value, then preserve or explicitly discard only that test draft. Real input/navigation, no state injection as replacement for recovery interaction.
3. Unassigned inventory/export flow: controller may seed exact synthetic legacy/future/malformed bytes into the task simulator app's CollectionDrafts directory. Provide checked-in fixture bytes and deterministic test expectations plus controller setup instructions. No product launch-argument seeding hook is needed. Unit tests prove byte identity; UI verifies row/classification/detail and opens normal system ShareLink sheet without sending to a recipient. Verify no recovery/adoption action appears in this inventory. Exercise connected then disconnected route on both phone/tablet.
4. Keep all existing flexible assertions unchanged. Controller can build an immutable committed archive to avoid any concurrent source edits. No simulator commands from implementer.
5. Run affected package suites, parser/native test typecheck/tooling as relevant; report exact red/green commands/counts, fixture hashes and source commits. Independent Astra review before actual acceptance. Do not claim screenshot or UI success from static tests.

Do not expand collection contract, schedule authoring or generic sync in this package. Scope is safe access to retained collection drafts; broader collection parity remains tracked separately.
