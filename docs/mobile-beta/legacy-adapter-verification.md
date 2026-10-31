# Legacy adapter and physical-frame follow-up

The missing-document-protocol fallback is now confined to stable 10.1.2, matching the captured `page-revision-v1.json` contract and reviewed backend `dadbc191e` described in the October 26 verification. A present supported `page-document-v1` remains version-independent. Explicit null, malformed, unknown protocol and unsupported document families remain read-only. Save still requires session opt-in, `page-revision-v1`, and a nonempty original revision; deletion retains its separate operation capability gate.

Regression first: the new service test failed with six assertions because development, unknown and missing server versions sent PUT with an absent document protocol. After the guard, all 154 Kit tests pass. All 85 AppState tests pass, including a permissive-service test of snapshot and current save availability and refusal before service invocation. Independent Astra review found no blocking correctness gap and requested this AppState regression, which was added.

Test identifiers:
- `PageEditingTests.testLegacyDocumentAbsenceRequiresAuditedAdapterWhileAdvertisedProtocolSurvivesNewVersion`
- `BoardStoreTests.testSavePermissionMatchesLegacyAdapterAndAdvertisedDocumentCapability`
- `PageManagementTests.testReaderOnlyFamiliesAndUnknownProtocolsCannotMutate` now includes absent protocol on 10.1.20.
- `PhysicalFramePreviewTests.testMalformedPhysicalFramesAreRejectedWithoutGuessingGeometry` covers malformed base64, byte-count mismatch, transparent black, over-limit dimensions, Int.max and UInt64.max dimensions; all bounds run before allocation/multiplication.
- `PhysicalFramePreviewTests.testPhysicalGoldensKeepExactDimensionsLastPixelAndBlack` verifies opaque black, endpoint pixels and exact 32×8, 52×16 and 64×64 geometry.

Logs are copied to `mobile-beta-discovery/evidence/legacy-adapter/` alongside this isolated checkout. `git diff --check` passes. This follow-up changes no UI layout; prior actual iPhone/iPad reader and pixel-preview screenshots remain representative. The generic iOS build and interactive screenshots were produced for the preceding reader slice, not rerun for this guard-only follow-up.

Next: verified connection-scoped durable draft identity and explicit recovery of unassigned legacy drafts, then native flexible text/Canvas authoring. These remain pending; no production actions, physical installation or publication occurred.
