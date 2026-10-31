import XCTest
import CryptoKit
import FiestaBoardKit
@testable import FiestaBoardEditorState

@MainActor final class CollectionEditorTests: XCTestCase {
    private var directory: URL!
    private var archive: CollectionDraftArchive!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        archive = CollectionDraftArchive(directory: directory)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private func collection(_ name: String = "Original", revision: String = "r1", mode: String = "time", protocolValue: String? = "collection-revision-v1") -> PageCollection {
        PageCollection(id: "c", name: name, pageIDs: ["a", "b"], selectionMode: mode,
                       time: .init(intervalSeconds: 30), variable: nil, random: nil,
                       revision: revision, editProtocol: protocolValue, createdAt: nil, updatedAt: nil)
    }
    private func identity(deploymentID: String = "https://example.test", collectionID: String? = "c") -> CollectionDraftIdentity {
        .init(deploymentID: deploymentID, installationID: "fixture-installation", connectionID: UUID(uuidString: "00000000-0000-4000-8000-000000000011")!, collectionID: collectionID)
    }
    private func model(_ baseline: PageCollection? = nil, actions: CollectionEditorActions? = nil) -> CollectionEditorModel {
        CollectionEditorModel(identity: identity(collectionID: baseline?.id), collection: baseline, canSave: true,
                              archive: archive, actions: actions ?? .init(save: { _, _ in throw FiestaBoardError.networkUnavailable }, delete: { _ in }, compare: { nil }))
    }
    func testUnassignedCheckpointCannotEnterActiveRecovery() throws {
        let legacy = CollectionDraftCheckpoint(id: UUID(), deploymentID: "https://example.test", collectionID: "c", baseline: collection(), draft: CollectionDraft(collection: collection("Foreign archive")), sourceSupportsEditing: true, status: .idle)
        try archive.save(legacy)
        let current = model(collection())
        current.checkRecovery()
        XCTAssertFalse(current.canRecover, "Deployment-only archives cannot prove ownership of an active connection")
    }
    func testScopedIdentitySeparatesConnectionsInstallationsAndNilCreationWithExactUTF8() throws {
        let a = CollectionDraftIdentity(deploymentID: "https://example.test", installationID: "cafe\u{301}", connectionID: UUID(), collectionID: nil)
        let same = a
        let otherLogin = CollectionDraftIdentity(deploymentID: a.deploymentID, installationID: a.installationID, connectionID: UUID(), collectionID: nil)
        let otherInstall = CollectionDraftIdentity(deploymentID: a.deploymentID, installationID: "café", connectionID: a.connectionID, collectionID: nil)
        XCTAssertEqual(a, same); XCTAssertNotEqual(a, otherLogin); XCTAssertNotEqual(a, otherInstall)
        XCTAssertEqual(Set([a, same, otherLogin, otherInstall]).count, 3)
        var draft = CollectionDraft(collection: nil); draft.name = "Owned new draft"; draft.pageIDs = ["a"]
        try archive.save(.init(id: UUID(), identity: a, baseline: nil, draft: draft, sourceSupportsEditing: true, status: .unknownOutcome))
        XCTAssertEqual(try archive.load(identity: same).count, 1)
        XCTAssertTrue(try archive.load(identity: otherLogin).isEmpty)
        XCTAssertTrue(try archive.load(identity: otherInstall).isEmpty)
        let assigned = CollectionDraftIdentity(deploymentID: a.deploymentID, installationID: a.installationID, connectionID: a.connectionID, collectionID: "c")
        XCTAssertTrue(try archive.load(identity: assigned).isEmpty)
    }
    func testAllModesPreserveMembershipRuleOrderAndInvalidNumericText() throws {
        let model = model()
        model.edit { $0.name = "😀 Morning"; $0.pageIDs = ["b", "a"]; $0.intervalText = "not a number" }
        XCTAssertNil(model.validatedInput)
        XCTAssertEqual(model.draft.intervalText, "not a number")
        model.edit { $0.intervalText = "5" }
        XCTAssertEqual(model.validatedInput?.pageIDs, ["b", "a"])
        model.edit { $0.selectionMode = "random"; $0.randomIntervalText = "86400" }
        XCTAssertEqual(model.validatedInput?.random?.intervalSeconds, 86400)
        model.edit { $0.selectionMode = "variable"; $0.defaultPageID = "a"; $0.pollText = "2"; $0.rules = [.init(expression: "second", pageID: "b"), .init(expression: "first", pageID: "a")] }
        XCTAssertEqual(model.validatedInput?.variable?.rules.map(\.expression), ["second", "first"])
        model.edit { $0.pollText = "1" }
        XCTAssertFalse(model.canSave)
    }
    func testSaveUsesOriginalRevisionAndAcknowledgementClearsArchive() async throws {
        let receipt = collection("Edited", revision: "r2")
        let model = model(collection(), actions: .init(save: { input, revision in
            XCTAssertEqual(revision, "r1"); XCTAssertEqual(input.name, "Edited"); return receipt
        }, delete: { _ in }, compare: { nil }))
        model.edit { $0.name = "Edited" }
        XCTAssertEqual(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).count, 1)
        await model.save()
        XCTAssertEqual(model.originalRevision, "r2")
        XCTAssertFalse(model.hasChanges)
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
    }
    func testCompareDoesNotAdoptOrRetokenDirtyDraft() async {
        let fresh = collection("Server", revision: "r2")
        let model = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.collectionConflict }, delete: { _ in }, compare: { fresh }))
        model.edit { $0.name = "Edited" }; await model.save(); await model.compare()
        XCTAssertEqual(model.draft.name, "Edited"); XCTAssertEqual(model.originalRevision, "r1")
        XCTAssertFalse(model.canSave); XCTAssertEqual(model.comparison?.revision, "r2")
        model.adoptComparison()
        XCTAssertEqual(model.draft.name, "Server"); XCTAssertEqual(model.originalRevision, "r2")
        XCTAssertFalse(model.hasChanges)
    }
    func testRecoveryRetainsOriginalBaselineAndInvalidText() async throws {
        let old = model(collection(revision: "old"))
        old.edit { $0.name = "Recovered"; $0.intervalText = "-" }
        let fresh = model(collection("Fresh", revision: "fresh"))
        fresh.checkRecovery(); XCTAssertTrue(fresh.canRecover)
        fresh.recoverDraft()
        XCTAssertEqual(fresh.originalRevision, "old"); XCTAssertEqual(fresh.draft.intervalText, "-")
        XCTAssertNil(fresh.validatedInput)
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://another.test", collectionID: "c")).isEmpty)
    }
    func testUnknownCreateCannotAutomaticallyRetryEvenAfterRecoveryOrComparison() async {
        var calls = 0
        let actions = CollectionEditorActions(save: { _, _ in calls += 1; throw FiestaBoardError.unknownMutationOutcome }, delete: { _ in }, compare: { nil })
        let first = model(actions: actions)
        first.edit { $0.name = "New"; $0.pageIDs = ["a"] }
        await first.save(); await first.save(); await first.compare(); await first.save()
        XCTAssertEqual(calls, 1); XCTAssertFalse(first.canSave)
        let recovered = model(actions: actions)
        recovered.checkRecovery(); recovered.recoverDraft(); await recovered.save()
        XCTAssertEqual(calls, 1); XCTAssertFalse(recovered.canSave)
    }
    func testMissingComparisonDisablesOldDraftWritesAndKeepsLocalCopy() async throws {
        let model = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.collectionConflict }, delete: { _ in }, compare: { nil }))
        model.edit { $0.name = "Keep" }; await model.compare()
        XCTAssertEqual(model.status, .missing); XCTAssertFalse(model.canSave); XCTAssertFalse(model.canDelete)
        XCTAssertTrue(model.localCopyText.contains("Keep"))
        XCTAssertEqual(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).count, 1)
    }
    func testDeleteInUseIsActionableAndDoesNotDiscardDraft() async {
        let model = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { revision in
            XCTAssertEqual(revision, "r1"); throw FiestaBoardError.collectionInUse
        }, compare: { nil }))
        model.edit { $0.name = "Keep" }; await model.delete()
        XCTAssertEqual(model.status, .idle); XCTAssertTrue(model.hasChanges); XCTAssertTrue(model.canDelete)
        XCTAssertNotNil(model.message)
    }
    func testSaveFreezesOverlappingEditSaveAndDelete() async {
        var continuation: CheckedContinuation<PageCollection, any Error>?
        var saves = 0; var deletes = 0
        let model = model(collection(), actions: .init(save: { _, _ in
            saves += 1; return try await withCheckedThrowingContinuation { continuation = $0 }
        }, delete: { _ in deletes += 1 }, compare: { nil }))
        model.edit { $0.name = "Edited" }
        let work = Task { await model.save() }
        while continuation == nil { await Task.yield() }
        model.edit { $0.name = "Lost" }; await model.save(); await model.delete()
        XCTAssertEqual(model.draft.name, "Edited"); XCTAssertEqual(saves, 1); XCTAssertEqual(deletes, 0)
        continuation!.resume(returning: collection("Edited", revision: "r2")); await work.value
        XCTAssertFalse(model.hasChanges)
    }
    func testCancellationAfterDispatchPreservesDraftAndRequiresComparison() async {
        let model = model(collection(), actions: .init(save: { _, _ in throw CancellationError() }, delete: { _ in }, compare: { nil }))
        model.edit { $0.name = "Keep" }; await model.save()
        XCTAssertEqual(model.status, .unknownOutcome); XCTAssertFalse(model.canSave); XCTAssertTrue(model.hasChanges)
    }
    func testUnknownModeAndUnsupportedProtocolRemainReadOnlyAndInspectable() {
        let model = model(collection(mode: "future_mode"))
        model.edit { $0.name = "Lost" }
        XCTAssertEqual(model.draft.name, "Original"); XCTAssertFalse(model.canSave); XCTAssertFalse(model.canDelete)
        XCTAssertTrue(model.localCopyText.contains("future_mode"))
        let legacy = self.model(collection(protocolValue: "future-protocol"))
        XCTAssertFalse(legacy.canSave); XCTAssertFalse(legacy.canDelete)
        legacy.edit { $0.name = "Lost" }; XCTAssertEqual(legacy.draft.name, "Original")
    }
    func testDiscardClearsCheckpointAndEndsEditing() throws {
        let model = model(collection()); model.edit { $0.name = "Discard" }; model.discard()
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
        model.edit { $0.name = "Resurrected" }; XCTAssertEqual(model.status, .ended)
    }
    func testUnknownFieldsCannotBecomeWritableThroughLocalArchive() throws {
        let unknown = try JSONDecoder().decode(PageCollection.self, from: Data(#"{"id":"c","name":"Original","page_ids":["a"],"selection_mode":"time","time":{"interval_seconds":30},"variable":null,"random":null,"revision":"r1","edit_protocol":"collection-revision-v1","future_setting":true}"#.utf8))
        let original = model(unknown)
        XCTAssertFalse(original.supportsEditing)
        original.preserve()
        let restored = model(collection())
        restored.checkRecovery(); restored.recoverDraft()
        XCTAssertFalse(restored.supportsEditing)
        restored.edit { $0.name = "Must remain read only" }
        XCTAssertEqual(restored.draft.name, "Original")
    }
    func testModeSwitchRetainsConfigurationsUntilExplicitClear() throws {
        let model = model()
        model.edit { $0.name = "Modes"; $0.pageIDs = ["a"]; $0.selectionMode = "variable"; $0.defaultPageID = "a"; $0.rules = [.init(expression: "x", pageID: "a")] }
        model.edit { $0.selectionMode = "random" }
        XCTAssertEqual(model.validatedInput?.variable?.rules.first?.expression, "x")
        model.edit { $0.selectionMode = "time" }
        XCTAssertNotNil(model.validatedInput?.random)
        model.edit { $0.hasVariableConfig = false; $0.hasRandomConfig = false }
        XCTAssertNil(model.validatedInput?.variable); XCTAssertNil(model.validatedInput?.random)
    }

    func testUncertainDeleteAfterAcknowledgedSavePersistsReadbackBarrier() async throws {
        let receipt = collection("Edited", revision: "r2")
        let model = model(collection(), actions: .init(save: { _, _ in receipt }, delete: { revision in
            XCTAssertEqual(revision, "r2"); throw FiestaBoardError.unknownMutationOutcome
        }, compare: { nil }))
        model.edit { $0.name = "Edited" }; await model.save(); await model.delete()
        let checkpoints = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertEqual(checkpoints.first?.status, .unknownOutcome)
        let restored = self.model(receipt)
        restored.checkRecovery(); restored.recoverDraft()
        XCTAssertFalse(restored.canDelete)
    }
    func testDeleteConflictAndMissingRemainDistinct() async {
        let conflict = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in throw FiestaBoardError.collectionConflict }, compare: { nil }))
        await conflict.delete(); XCTAssertEqual(conflict.status, .conflict); XCTAssertFalse(conflict.canDelete)
        let missing = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in throw FiestaBoardError.rejected(status: 404) }, compare: { nil }))
        await missing.delete(); XCTAssertEqual(missing.status, .missing); XCTAssertFalse(missing.canDelete)
    }
    func testDeleteFreezesOverlappingEditsAndSave() async {
        var continuation: CheckedContinuation<Void, any Error>?
        var saves = 0
        let model = model(collection(), actions: .init(save: { _, _ in saves += 1; throw FiestaBoardError.invalidResponse }, delete: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }, compare: { nil }))
        let work = Task { await model.delete() }
        while continuation == nil { await Task.yield() }
        model.edit { $0.name = "Lost" }; await model.save()
        XCTAssertEqual(model.draft.name, "Original"); XCTAssertEqual(saves, 0)
        continuation!.resume(); await work.value
        XCTAssertEqual(model.status, .ended)
    }
    func testAcknowledgedSaveInEachModeUsesExplicitNilConfigsAndOrder() async {
        for mode in ["time", "variable", "random"] {
            var saved: CollectionInput?
            let model = model(actions: .init(save: { input, revision in
                saved = input; XCTAssertNil(revision)
                return PageCollection(id: "new", name: input.name, pageIDs: input.pageIDs, selectionMode: input.selectionMode.rawValue,
                    time: input.time, variable: input.variable, random: input.random, revision: "created", editProtocol: "collection-revision-v1")
            }, delete: { _ in }, compare: { nil }))
            model.edit { $0.name = "Create"; $0.pageIDs = ["b", "a"]; $0.selectionMode = mode; $0.defaultPageID = "a" }
            await model.save()
            XCTAssertEqual(saved?.selectionMode.rawValue, mode); XCTAssertEqual(saved?.pageIDs, ["b", "a"])
            XCTAssertEqual(model.originalRevision, "created"); XCTAssertFalse(model.hasChanges)
            if mode == "time" { XCTAssertNil(saved?.variable); XCTAssertNil(saved?.random) }
        }
    }
    func testComparisonAdoptionPreservesPriorDraftAcrossBackgroundCheckpoint() async throws {
        let server = collection("Fresh", revision: "r2")
        let model = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in }, compare: { server }))
        model.edit { $0.name = "Prior local work" }; await model.compare(); model.adoptComparison(); model.preserve()
        let checkpoints = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertEqual(checkpoints.first?.draft.name, "Prior local work")
        XCTAssertEqual(checkpoints.first?.baseline?.revision, "r1")
    }

    func testClearedInactiveConfigurationsDoNotValidateHiddenInvalidText() {
        let model = model()
        model.edit { $0.name = "Valid"; $0.pageIDs = ["a"]; $0.pollText = "-"; $0.randomIntervalText = "invalid" }
        XCTAssertNotNil(model.validatedInput)
        XCTAssertNil(model.validatedInput?.variable); XCTAssertNil(model.validatedInput?.random)
    }

    func testClosingUnchangedEditorDoesNotCreateARecoveryDraft() throws {
        let model = model(collection())
        XCTAssertTrue(model.closeKeepingDraft())
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
    }

    func testComparisonSessionLossKeepsDraftAndBlocksStaleWrites() async throws {
        let model = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in }, compare: { throw FiestaBoardError.unauthenticated }))
        model.edit { $0.name = "Keep on logout" }; await model.compare()
        XCTAssertFalse(model.canSave); XCTAssertFalse(model.canDelete)
        XCTAssertEqual(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).first?.draft.name, "Keep on logout")
    }

    func testRecoveredWindowsOwnIndependentCheckpointsOnDiscardAndAcknowledgement() async throws {
        let original = model(collection()); original.edit { $0.name = "Source draft" }; XCTAssertTrue(original.closeKeepingDraft())
        let sourceID = try XCTUnwrap(archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).first?.id)
        let sourceURL = directory.appendingPathComponent(sourceID.uuidString).appendingPathExtension("json")
        let sourceBytes = try Data(contentsOf: sourceURL)
        let windowA = model(collection())
        let windowC = model(collection())
        let receipt = collection("Window B", revision: "r2")
        let windowB = model(collection(), actions: .init(save: { _, _ in receipt }, delete: { _ in }, compare: { nil }))
        windowA.checkRecovery(); windowB.checkRecovery(); windowC.checkRecovery()
        windowA.recoverDraft(); windowB.recoverDraft(); windowC.recoverDraft()
        windowA.edit { $0.name = "Window A" }; windowB.edit { $0.name = "Window B" }
        await windowB.save()
        var remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertTrue(remaining.contains { $0.draft.name == "Window A" })
        windowC.edit { $0.name = "Window C" }; windowC.discard()
        remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertTrue(remaining.contains { $0.draft.name == "Window A" })
        XCTAssertFalse(remaining.contains { $0.draft.name == "Source draft" })
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }
    func testRevertingOwnedDraftRemovesStaleCheckpointWithoutRemovingOtherWindows() throws {
        let other = model(collection()); other.edit { $0.name = "Other window" }
        let current = model(collection()); current.edit { $0.name = "Temporary" }; current.edit { $0.name = "Original" }
        XCTAssertFalse(current.hasChanges); XCTAssertTrue(current.closeKeepingDraft())
        let remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertEqual(remaining.count, 1); XCTAssertEqual(remaining.first?.draft.name, "Other window")
    }
    func testRevertAfterConflictRetainsWriteBarrier() async throws {
        let current = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.collectionConflict }, delete: { _ in }, compare: { nil }))
        current.edit { $0.name = "Temporary" }; await current.save(); current.edit { $0.name = "Original" }
        XCTAssertFalse(current.hasChanges); XCTAssertFalse(current.canSave); XCTAssertFalse(current.canDelete)
        let remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertEqual(remaining.first?.draft.name, "Original"); XCTAssertEqual(remaining.first?.status, .conflict)
    }
    func testScalarDistinctNamesAndRuleExpressionsRemainDirtyAndRecoverExactly() throws {
        let baseline = PageCollection(id: "c", name: "Caf\u{00e9}", pageIDs: ["a"], selectionMode: "variable", variable: .init(rules: [.init(expression: "Caf\u{00e9}", pageID: "a")], defaultPageID: "a"), revision: "r1", editProtocol: "collection-revision-v1")
        let current = model(baseline)
        current.edit { $0.name = "Cafe\u{0301}"; $0.rules[0].expression = "Cafe\u{0301}" }
        XCTAssertTrue(current.hasChanges); XCTAssertTrue(current.canSave)
        let restored = model(baseline); restored.checkRecovery(); restored.recoverDraft()
        XCTAssertEqual(Array(restored.draft.name.unicodeScalars).map(\.value), [67, 97, 102, 101, 769])
        XCTAssertEqual(Array(restored.draft.rules[0].expression.unicodeScalars).map(\.value), [67, 97, 102, 101, 769])
        XCTAssertTrue(restored.hasChanges)
    }
    func testEveryPersistedDraftTextFieldUsesScalarExactEquality() {
        let first = CollectionDraft(collection: collection())
        let changes: [(inout CollectionDraft) -> Void] = [
            { $0.name = "Cafe\u{0301}" }, { $0.pageIDs = ["Cafe\u{0301}"] }, { $0.selectionMode = "Cafe\u{0301}" },
            { $0.intervalText = "Cafe\u{0301}" }, { $0.randomIntervalText = "Cafe\u{0301}" },
            { $0.defaultPageID = "Cafe\u{0301}" }, { $0.pollText = "Cafe\u{0301}" },
            { $0.rules = [.init(expression: "Cafe\u{0301}", pageID: "x")] },
            { $0.rules = [.init(expression: "x", pageID: "Cafe\u{0301}")] }
        ]
        for change in changes {
            var decomposed = first; change(&decomposed)
            var composed = decomposed
            composed.name = composed.name.precomposedStringWithCanonicalMapping
            composed.pageIDs = composed.pageIDs.map { $0.precomposedStringWithCanonicalMapping }
            composed.selectionMode = composed.selectionMode.precomposedStringWithCanonicalMapping
            composed.intervalText = composed.intervalText.precomposedStringWithCanonicalMapping
            composed.randomIntervalText = composed.randomIntervalText.precomposedStringWithCanonicalMapping
            composed.defaultPageID = composed.defaultPageID.precomposedStringWithCanonicalMapping
            composed.pollText = composed.pollText.precomposedStringWithCanonicalMapping
            composed.rules = composed.rules.map { .init(expression: $0.expression.precomposedStringWithCanonicalMapping, pageID: $0.pageID.precomposedStringWithCanonicalMapping) }
            XCTAssertNotEqual(decomposed, composed)
        }
    }
    func testScalarDistinctEditAfterAdoptionCrossesPreservationBarrier() async throws {
        let fresh = collection("Caf\u{00e9}", revision: "r2")
        let current = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in }, compare: { fresh }))
        current.edit { $0.name = "Prior local work" }; await current.compare(); current.adoptComparison()
        current.edit { $0.name = "Cafe\u{0301}" }
        XCTAssertTrue(current.hasChanges)
        let stored = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertEqual(stored.first?.baseline?.revision, "r2")
        XCTAssertEqual(stored.first.map { Array($0.draft.name.unicodeScalars).map(\.value) }, [67, 97, 102, 101, 769])
    }

    func testRecoveredDiscardRetiresLineageAcrossCloseAndRestart() throws {
        let original = model(collection()); original.edit { $0.name = "Discard me" }; XCTAssertTrue(original.closeKeepingDraft())
        let recovered = model(collection()); recovered.checkRecovery(); recovered.recoverDraft(); XCTAssertTrue(recovered.closeKeepingDraft())
        let reopened = model(collection()); reopened.checkRecovery(); reopened.recoverDraft(); reopened.discard()
        XCTAssertEqual(reopened.status, .ended)
        let next = model(collection()); next.checkRecovery(); XCTAssertFalse(next.canRecover)
    }
    func testRecoveredAcknowledgementsRetireExactSourceAndOwnedClone() async throws {
        for deleting in [false, true] {
            let original = model(collection()); original.edit { $0.name = "Recovered" }; XCTAssertTrue(original.closeKeepingDraft())
            let receipt = collection("Recovered", revision: "r2")
            let recovered = model(collection(), actions: .init(save: { _, _ in receipt }, delete: { _ in }, compare: { nil }))
            recovered.checkRecovery(); recovered.recoverDraft()
            if deleting { await recovered.delete() } else { await recovered.save() }
            XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
        }
    }
    func testRetiringRecoveredSourceVersionKeepsNewerSourceAndConcurrentClone() throws {
        let original = model(collection()); original.edit { $0.name = "Source version 1" }
        let windowA = model(collection()); let windowB = model(collection())
        windowA.checkRecovery(); windowB.checkRecovery(); windowA.recoverDraft(); windowB.recoverDraft()
        windowA.edit { $0.name = "Window A" }
        original.edit { $0.name = "Source version 2" }
        windowB.discard()
        let remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertTrue(remaining.contains { $0.draft.name == "Window A" })
        XCTAssertTrue(remaining.contains { $0.draft.name == "Source version 2" })
        XCTAssertFalse(remaining.contains { $0.draft.name == "Source version 1" })
    }
    func testRecoveredCloseAndUnknownFailureDoNotRetireSource() async throws {
        let original = model(collection()); original.edit { $0.name = "Source version" }; XCTAssertTrue(original.closeKeepingDraft())
        let recovered = model(collection(), actions: .init(save: { _, _ in throw FiestaBoardError.unknownMutationOutcome }, delete: { _ in }, compare: { nil }))
        recovered.checkRecovery(); recovered.recoverDraft(); recovered.edit { $0.name = "Uncertain work" }; await recovered.save()
        XCTAssertTrue(recovered.closeKeepingDraft())
        let remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertTrue(remaining.contains { $0.draft.name == "Source version" })
        XCTAssertTrue(remaining.contains { $0.draft.name == "Uncertain work" && $0.status == .unknownOutcome })
    }
    func testAdoptionRetainsIndependentPriorCopyAfterNewWorkSaveOrDiscard() async throws {
        for saving in [false, true] {
            let original = model(collection()); original.edit { $0.name = "Keep prior" }; XCTAssertTrue(original.closeKeepingDraft())
            let fresh = collection("Server", revision: "r2")
            let receipt = collection("New work", revision: "r3")
            let current = model(collection(), actions: .init(save: { _, _ in receipt }, delete: { _ in }, compare: { fresh }))
            current.checkRecovery(); current.recoverDraft(); await current.compare()
            let preservedID = try XCTUnwrap(archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).first?.id)
            current.adoptComparison()
            current.edit { $0.name = "New work" }
            if saving { await current.save() } else { current.discard() }
            let remaining = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
            XCTAssertTrue(remaining.contains { $0.id == preservedID && $0.draft.name == "Keep prior" && $0.baseline?.revision == "r1" })
            XCTAssertFalse(remaining.contains { $0.draft.name == "New work" })
        }
    }
    func testAcknowledgedSaveAndDeleteRemainAcknowledgedWhenLocalCleanupFails() async throws {
        for deleting in [false, true] {
            let isolated = directory.appendingPathComponent(UUID().uuidString)
            let failingArchive = CollectionDraftArchive(directory: isolated)
            let original = CollectionEditorModel(identity: identity(), collection: collection(), canSave: true, archive: failingArchive,
                actions: .init(save: { _, _ in throw FiestaBoardError.invalidResponse }, delete: { _ in }, compare: { nil }))
            original.edit { $0.name = "Recover" }; XCTAssertTrue(original.closeKeepingDraft())
            let receipt = collection("Recover", revision: "r2")
            var saves = 0
            let blockCleanup: @MainActor @Sendable () throws -> Void = {
                try Data("block marker directory".utf8).write(to: isolated.appendingPathComponent("retired"))
            }
            let current = CollectionEditorModel(identity: identity(), collection: collection(), canSave: true, archive: failingArchive,
                actions: .init(save: { _, _ in saves += 1; try blockCleanup(); return receipt }, delete: { _ in try blockCleanup() }, compare: { nil }))
            current.checkRecovery(); current.recoverDraft()
            if deleting {
                await current.delete(); XCTAssertEqual(current.status, .ended)
            } else {
                await current.save(); XCTAssertEqual(current.status, .idle); XCTAssertEqual(current.originalRevision, "r2")
                XCTAssertFalse(current.hasChanges); await current.save(); XCTAssertEqual(saves, 1)
            }
            XCTAssertFalse(current.canSave)
            XCTAssertTrue(current.message?.contains("acknowledged") == true)
            XCTAssertTrue(current.message?.contains("cleanup") == true)
        }
    }

    func testLegacyArchiveAndMalformedBytesSurviveVersionRetirement() throws {
        let id = UUID()
        let legacy = CollectionDraftCheckpoint(id: id, deploymentID: "https://example.test", collectionID: "c", baseline: collection(), draft: CollectionDraft(collection: collection("Legacy draft")), sourceSupportsEditing: true, status: .idle)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "sourceVersions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let legacyBytes = try JSONSerialization.data(withJSONObject: json)
        try legacyBytes.write(to: legacyURL)
        let corruptURL = directory.appendingPathComponent("damaged.json")
        let corruptBytes = Data("{broken archive".utf8); try corruptBytes.write(to: corruptURL)
        let loaded = try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c"))
        XCTAssertTrue(loaded.isEmpty, "Legacy unassigned archives are export-only")
        let recovered = model(collection()); recovered.checkRecovery(); recovered.recoverDraft(); recovered.discard()
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
        XCTAssertEqual(try Data(contentsOf: corruptURL), corruptBytes)
    }
    func testVersionMarkerDoesNotHideNewerWriteToSameArchiveID() throws {
        let id = UUID()
        let first = CollectionDraftCheckpoint(id: id, identity: identity(), baseline: collection(), draft: CollectionDraft(collection: collection("Version 1")), sourceSupportsEditing: true, status: .idle)
        try archive.save(first)
        let version = try XCTUnwrap(archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).first?.archiveVersion)
        try archive.retire([version], identity: identity()); try archive.retire([version], identity: identity())
        XCTAssertTrue(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).isEmpty)
        let next = CollectionDraftCheckpoint(id: id, identity: identity(), baseline: collection(), draft: CollectionDraft(collection: collection("Version 2")), sourceSupportsEditing: true, status: .idle)
        try archive.save(next)
        XCTAssertEqual(try archive.load(identity: identity(deploymentID: "https://example.test", collectionID: "c")).first?.draft.name, "Version 2")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("retired").path).count, 1)
    }

    func testCreationAcknowledgementRetiresNilLineageThenRecoversAssignedDraft() async throws {
        let original = model()
        original.edit { $0.name = "New"; $0.pageIDs = ["a"] }
        let receipt = collection("New", revision: "created-original")
        let recovered = model(actions: .init(save: { _, expected in XCTAssertNil(expected); return receipt }, delete: { _ in }, compare: { nil }))
        recovered.checkRecovery(); recovered.recoverDraft()
        await recovered.save()
        XCTAssertEqual(recovered.identity, identity())
        XCTAssertTrue(try archive.load(identity: identity(collectionID: nil)).isEmpty)
        recovered.edit { $0.name = "Assigned dirty"; $0.intervalText = "-" }
        let restarted = model(receipt)
        restarted.checkRecovery(); restarted.recoverDraft()
        XCTAssertEqual(restarted.identity, identity())
        XCTAssertEqual(restarted.originalRevision, "created-original")
        XCTAssertEqual(restarted.draft.name, "Assigned dirty"); XCTAssertEqual(restarted.draft.intervalText, "-")
    }
    func testRecoveryRechecksExactIdentityAndVersionBeforeInstallingCachedChoice() throws {
        let original = model(collection()); original.edit { $0.name = "Old owned draft" }
        let fresh = model(collection("Fetched", revision: "fresh")); fresh.checkRecovery()
        let cached = try XCTUnwrap(fresh.recovery.first)
        let foreign = CollectionDraftIdentity(deploymentID: identity().deploymentID, installationID: identity().installationID, connectionID: UUID(), collectionID: "c")
        let replacement = CollectionDraftCheckpoint(id: cached.id, identity: foreign, baseline: collection(), draft: CollectionDraft(collection: collection("Different connection")), sourceSupportsEditing: true, status: .idle)
        let bytes = try JSONEncoder().encode(replacement)
        let path = directory.appendingPathComponent(cached.id.uuidString).appendingPathExtension("json")
        try bytes.write(to: path)
        fresh.recoverDraft(id: cached.id)
        XCTAssertEqual(fresh.draft.name, "Fetched"); XCTAssertEqual(fresh.originalRevision, "fresh")
        XCTAssertEqual(fresh.identity, identity()); XCTAssertFalse(fresh.canRecover)
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }
    func testForgedLineageCannotRetireOtherScopeLegacyFutureOrNewerBytes() throws {
        let owned = identity()
        let foreign = CollectionDraftIdentity(deploymentID: owned.deploymentID, installationID: owned.installationID, connectionID: UUID(), collectionID: "c")
        let foreignID = UUID()
        let foreignVersion = try archive.save(.init(id: foreignID, identity: foreign, baseline: collection(), draft: CollectionDraft(collection: collection("Foreign")), sourceSupportsEditing: true, status: .idle))
        let legacyID = UUID()
        let legacyVersion = try archive.save(.init(id: legacyID, deploymentID: owned.deploymentID, collectionID: "c", baseline: collection(), draft: CollectionDraft(collection: collection("Unassigned")), sourceSupportsEditing: true, status: .idle))
        let futureID = UUID()
        var future = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CollectionDraftCheckpoint(id: futureID, identity: owned, baseline: collection(), draft: CollectionDraft(collection: collection("Future")), sourceSupportsEditing: true, status: .idle))) as! [String: Any]
        future["formatVersion"] = 99
        let futureBytes = try JSONSerialization.data(withJSONObject: future)
        let futureURL = directory.appendingPathComponent(futureID.uuidString).appendingPathExtension("json")
        try futureBytes.write(to: futureURL)
        let futureVersion = CollectionDraftVersion(id: futureID, fingerprint: SHA256.hash(data: futureBytes).map { String(format: "%02x", $0) }.joined())
        let sourceID = UUID()
        let oldVersion = try archive.save(.init(id: sourceID, identity: owned, baseline: collection(), draft: CollectionDraft(collection: collection("Old version")), sourceSupportsEditing: true, status: .idle))
        try archive.save(.init(id: sourceID, identity: owned, baseline: collection(), draft: CollectionDraft(collection: collection("Newer version")), sourceSupportsEditing: true, status: .idle))
        let poisonID = UUID()
        try archive.save(.init(id: poisonID, identity: owned, baseline: collection(), draft: CollectionDraft(collection: collection("Recovered")), sourceSupportsEditing: true, status: .idle, sourceVersions: [foreignVersion, legacyVersion, futureVersion, oldVersion]))
        let current = model(collection()); current.checkRecovery(); current.recoverDraft(id: poisonID); current.discard()
        XCTAssertEqual(try archive.load(identity: foreign).count, 1)
        XCTAssertEqual(try archive.load(identity: owned).map(\.draft.name), ["Newer version"])
        XCTAssertEqual(try Data(contentsOf: futureURL), futureBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(legacyID.uuidString).appendingPathExtension("json").path))
    }
    func testMalformedScopedIdentityIsIgnoredWithoutChangingOriginalBytes() throws {
        let id = UUID()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CollectionDraftCheckpoint(id: id, identity: identity(), baseline: collection(), draft: CollectionDraft(collection: collection("Broken")), sourceSupportsEditing: true, status: .idle))) as! [String: Any]
        var scope = object["identity"] as! [String: Any]; scope["installationID"] = ""; object["identity"] = scope
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try bytes.write(to: url)
        XCTAssertTrue(try archive.load(identity: identity()).isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testDeploymentAndCollectionIdentityStringsUseExactUTF8AndNilIsDistinct() throws {
        let scope = identity()
        let deploymentA = CollectionDraftIdentity(deploymentID: "https://example.test/cafe\u{301}", installationID: scope.installationID, connectionID: scope.connectionID, collectionID: "c")
        let deploymentB = CollectionDraftIdentity(deploymentID: "https://example.test/café", installationID: scope.installationID, connectionID: scope.connectionID, collectionID: "c")
        let collectionA = identity(collectionID: "cafe\u{301}"), collectionB = identity(collectionID: "café")
        XCTAssertNotEqual(deploymentA, deploymentB); XCTAssertNotEqual(collectionA, collectionB)
        XCTAssertNotEqual(identity(collectionID: nil), identity(collectionID: ""))
        XCTAssertThrowsError(try identity(collectionID: "").validate())
    }
    func testScopedSaveCannotOverwriteUnassignedOriginalArchive() throws {
        let id = UUID()
        let legacy = CollectionDraftCheckpoint(id: id, deploymentID: identity().deploymentID, collectionID: "c", baseline: collection(), draft: CollectionDraft(collection: collection("Original unassigned")), sourceSupportsEditing: true, status: .idle)
        try archive.save(legacy)
        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let original = try Data(contentsOf: url)
        let replacement = CollectionDraftCheckpoint(id: id, identity: identity(), baseline: collection(), draft: CollectionDraft(collection: collection("Retagging")), sourceSupportsEditing: true, status: .idle)
        XCTAssertThrowsError(try archive.save(replacement))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(try archive.load(identity: identity()).isEmpty)
    }

}
