import XCTest
@testable import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class CollectionStoreTests: XCTestCase {
    func testOriginalRevisionSurvivesDirtyListRefresh() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let snapshot = try await store.beginCollectionEditor(id: collectionFixtureID)
        await service.replaceRemote(name: "Other writer", revision: "revision-2")
        await store.refreshCollections().value
        XCTAssertEqual(store.collections.first?.revision, "revision-2")
        await expect(.collectionConflict) {
            try await store.saveCollection(collectionFixtureInput(), expectedRevision: snapshot.context.originalRevision, context: snapshot.context)
        }
        let revisions = await service.submittedRevisions
        XCTAssertEqual(revisions, ["revision-1"])
    }

    func testSuccessfulSaveAdvancesContextAndDisablesOriginalEditor() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        let saved = try await store.saveCollection(collectionFixtureInput("Saved"), expectedRevision: "revision-1", context: original.context)
        XCTAssertEqual(saved.collection?.name, "Saved")
        XCTAssertNotEqual(saved.context.documentToken, original.context.documentToken)
        XCTAssertNotEqual(saved.context.originalRevision, "revision-1")
        await expect(.staleCollectionContext) {
            try await store.saveCollection(collectionFixtureInput("Old editor"), expectedRevision: "revision-1", context: original.context)
        }
        let calls = await service.updateCount
        XCTAssertEqual(calls, 1)
    }

    func testSameURLReconnectCannotAuthorizePreviousContext() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let old = try await store.beginCollectionEditor(id: collectionFixtureID)
        await store.reconnect(allowCandidateWrites: true).value
        await expect(.staleSession) {
            try await store.saveCollection(collectionFixtureInput(), expectedRevision: "revision-1", context: old.context)
        }
        let calls = await service.updateCount
        XCTAssertEqual(calls, 0)
    }

    func testLateDocumentReadCannotReplaceAcknowledgedGeneration() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        let latch = CollectionLatch()
        await service.delayNextRead(latch)
        let read = Task { try await store.beginCollectionEditor(id: collectionFixtureID) }
        await latch.waitUntilStarted()
        let saved = try await store.saveCollection(collectionFixtureInput("Winner"), expectedRevision: "revision-1", context: original.context)
        await latch.release()
        await expect(.staleCollectionContext) { try await read.value }
        let second = try await store.saveCollection(collectionFixtureInput("Next"), expectedRevision: saved.context.originalRevision, context: saved.context)
        XCTAssertEqual(second.collection?.name, "Next")
    }

    func testUnknownCreationRequiresListReviewAndNeverReplaysOldDraft() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let draft = try await store.beginCollectionEditor(id: nil)
        await service.loseNextCreateAcknowledgement()
        await expect(.unknownMutationOutcome) {
            try await store.saveCollection(collectionFixtureInput("Maybe created"), expectedRevision: nil, context: draft.context)
        }
        await expect(.collectionReadbackRequired) { try await store.beginCollectionEditor(id: nil) }
        await store.refreshCollections().value
        XCTAssertEqual(store.collections.first?.name, "Maybe created")
        await expect(.collectionReadbackRequired) {
            try await store.saveCollection(collectionFixtureInput("Maybe created"), expectedRevision: nil, context: draft.context)
        }
        _ = try await store.beginCollectionEditor(id: nil)
        let count = await service.createCount
        XCTAssertEqual(count, 1)
    }

    func testCancelledWriteRequiresExplicitReadback() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        let latch = CollectionLatch()
        await service.delayNextUpdate(latch)
        let save = Task { try await store.saveCollection(collectionFixtureInput("Applied"), expectedRevision: "revision-1", context: original.context) }
        await latch.waitUntilStarted()
        save.cancel()
        await latch.release()
        do { _ = try await save.value; XCTFail("Cancelled result must not authorize an editor") }
        catch { XCTAssertTrue(error is CancellationError) }
        await expect(.collectionReadbackRequired) {
            try await store.saveCollection(collectionFixtureInput("Retry"), expectedRevision: "revision-1", context: original.context)
        }
        let latest = try await store.readbackCollection(context: original.context)
        XCTAssertEqual(latest.collection?.name, "Applied")
        await expect(.staleCollectionContext) {
            try await store.saveCollection(collectionFixtureInput("Old"), expectedRevision: "revision-1", context: original.context)
        }
    }

    func testDeleteInUseKeepsCollectionAndDoesNotRetry() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        await store.refreshCollections().value
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        await service.setInUse(true)
        await expect(.collectionInUse) { try await store.deleteCollection(expectedRevision: "revision-1", context: original.context) }
        XCTAssertEqual(store.collections.count, 1)
        let attempts = await service.deleteCount
        XCTAssertEqual(attempts, 1)
        await service.setInUse(false)
        try await store.deleteCollection(expectedRevision: "revision-1", context: original.context)
        XCTAssertTrue(store.collections.isEmpty)
        await expect(.staleCollectionContext) { try await store.deleteCollection(expectedRevision: "revision-1", context: original.context) }
    }

    func testReadbackComparisonCannotSupplyFreshTokenForOldDraft() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        await service.replaceRemote(name: "Server winner", revision: "revision-2")
        let comparison = try await store.readbackCollection(context: original.context)
        await expect(.staleCollectionContext) {
            try await store.saveCollection(collectionFixtureInput("Old draft"), expectedRevision: "revision-1", context: comparison.context)
        }
        let calls = await service.updateCount
        XCTAssertEqual(calls, 0)
    }

    func testReadOnlyConnectionCannotCreateOrEdit() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service).value
        let existing = try await store.beginCollectionEditor(id: collectionFixtureID)
        let new = try await store.beginCollectionEditor(id: nil)
        XCTAssertFalse(existing.canSave)
        XCTAssertFalse(new.canSave)
        await expect(.collectionWritesDisabled) {
            try await store.saveCollection(collectionFixtureInput(), expectedRevision: "revision-1", context: existing.context)
        }
    }

    func testMissingProtocolOrRevisionCannotTurnAnExistingEditIntoCreation() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        await service.removeRevisionAndProtocol()
        let snapshot = try await store.beginCollectionEditor(id: collectionFixtureID)
        XCTAssertFalse(snapshot.canSave)
        await expect(.collectionWritesDisabled) {
            try await store.saveCollection(collectionFixtureInput(), expectedRevision: nil, context: snapshot.context)
        }
        let creates = await service.createCount
        XCTAssertEqual(creates, 0)
    }

    func testCollectionAuthenticationLossEndsSession() async throws {
        let service = try CollectionStoreFixture()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status, store.message ?? "Fixture connection failed")
        let original = try await store.beginCollectionEditor(id: collectionFixtureID)
        await service.expireNextList()
        await store.refreshCollections().value
        XCTAssertNil(store.status)
        await expect(.staleSession) { try await store.deleteCollection(expectedRevision: "revision-1", context: original.context) }
    }

    private func expect<T>(_ expected: FiestaBoardError, operation: @MainActor () async throws -> T) async {
        do { _ = try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? FiestaBoardError, expected) }
    }
}

private let collectionFixtureID = "collection:00000000-0000-0000-0000-000000000001"
private func collectionFixtureInput(_ name: String = "Draft") -> CollectionInput {
    CollectionInput(name: name, pageIDs: ["page-selected"])
}
private func collectionFixtureValue(_ name: String = "Original", revision: String = "revision-1") -> PageCollection {
    PageCollection(id: collectionFixtureID, name: name, pageIDs: ["page-selected"], revision: revision, editProtocol: "collection-revision-v1")
}

private actor CollectionLatch {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var blocker: CheckedContinuation<Void, Never>?
    func block() async {
        started = true; waiter?.resume(); waiter = nil
        await withCheckedContinuation { blocker = $0 }
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { waiter = $0 } } }
    func release() { blocker?.resume(); blocker = nil }
}

private actor CollectionStoreFixture: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    private let demo: DemoFiestaBoardService
    private var writes = false
    private var stored: PageCollection? = collectionFixtureValue()
    private var replacementScope: VerifiedConnectionScope?
    func replaceConnectionScope() {
        replacementScope = VerifiedConnectionScope(deployment: deployment, installationID: "replacement-fixture", connectionID: UUID())
    }
    private var readLatch: CollectionLatch?
    private var updateLatch: CollectionLatch?
    private var unknownCreate = false
    private var inUse = false
    private var expiredList = false
    private(set) var submittedRevisions: [String] = []
    private(set) var updateCount = 0
    private(set) var createCount = 0
    private(set) var deleteCount = 0
    init() throws { demo = try DemoFiestaBoardService(); deployment = demo.deployment }
    func replaceRemote(name: String, revision: String) { stored = collectionFixtureValue(name, revision: revision) }
    func delayNextRead(_ latch: CollectionLatch) { readLatch = latch }
    func delayNextUpdate(_ latch: CollectionLatch) { updateLatch = latch }
    func loseNextCreateAcknowledgement() { unknownCreate = true }
    func removeRevisionAndProtocol() {
        stored = PageCollection(id: collectionFixtureID, name: "Legacy", pageIDs: ["page-selected"])
    }
    func setInUse(_ value: Bool) { inUse = value }
    func expireNextList() { expiredList = true }
    func acknowledgeCollectionCreationReview() async throws {}
    func collectionAccess() async -> CollectionWriteAccess { .init(writesOptedIn: writes, canCreate: writes, isSimulated: false) }
    func collections() async throws -> [PageCollection] {
        if expiredList { throw FiestaBoardError.unauthenticated }
        return stored.map { [$0] } ?? []
    }
    func collection(id: String) async throws -> PageCollection {
        let captured = stored
        if let latch = readLatch { readLatch = nil; await latch.block() }
        guard let captured else { throw FiestaBoardError.rejected(status: 404) }
        return captured
    }
    func scopedCollectionDocument(id: String?) async throws -> ScopedCollectionDocument {
        let scope: VerifiedConnectionScope
        if let replacementScope { scope = replacementScope }
        else { scope = try await demo.scopedPageDocument(id: "page-selected").scope }
        let value: PageCollection?
        if let id { value = try await collection(id: id) } else { value = nil }
        return ScopedCollectionDocument(collection: value, scope: scope)
    }
    func createCollection(_ input: CollectionInput) async throws -> PageCollection {
        createCount += 1
        let value = collectionFixtureValue(input.name, revision: "created-\(createCount)")
        stored = value
        if unknownCreate { unknownCreate = false; throw FiestaBoardError.unknownMutationOutcome }
        return value
    }
    func updateCollection(id: String, input: CollectionInput, expectedRevision: String) async throws -> PageCollection {
        updateCount += 1; submittedRevisions.append(expectedRevision)
        if let latch = updateLatch { updateLatch = nil; await latch.block() }
        guard stored?.revision == expectedRevision else { throw FiestaBoardError.collectionConflict }
        let value = collectionFixtureValue(input.name, revision: "saved-\(updateCount)")
        stored = value; return value
    }
    func deleteCollection(id: String, expectedRevision: String) async throws {
        deleteCount += 1
        if inUse { throw FiestaBoardError.collectionInUse }
        guard stored?.revision == expectedRevision else { throw FiestaBoardError.collectionConflict }
        stored = nil
    }
    func authStatus() async throws -> AuthStatus { try await demo.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await demo.authStatus() }
    func logout() async throws { try await demo.logout() }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        writes = allowCandidateWrites
        let status = try await demo.connect()
        var projection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        projection["access"] = "readOnly"; projection["isDemo"] = false
        return try JSONDecoder().decode(ConnectionStatus.self, from: JSONSerialization.data(withJSONObject: projection))
    }
    func boards() async throws -> [BoardSummary] { try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail { try await demo.board(target) }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func pageDocumentData(id: String) async throws -> Data { try await demo.pageDocumentData(id: id) }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { try await demo.savePage(id: id, patch: patch) }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { try await demo.validatePage(requestData: requestData, target: target) }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { try await demo.previewPage(requestData: requestData, target: target) }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { try await demo.updateBoard(patch, on: target) }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await demo.restoreBoard(target) }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { try await demo.sendText(text, to: target) }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await demo.selectPage(id: id, on: target) }
}

extension CollectionStoreTests {
    func testReplacedOwnershipCannotDispatchOriginalContextSaveDeleteOrCompare() async throws {
        for operation in ["save", "delete", "compare"] {
            let service = try CollectionStoreFixture(), store = BoardStore()
            await store.connect(service, allowCandidateWrites: true).value
            let original = try await store.beginCollectionEditor(id: collectionFixtureID)
            await service.replaceConnectionScope()
            do {
                switch operation {
                case "save": _ = try await store.saveCollection(collectionFixtureInput("Wrong connection"), expectedRevision: original.context.originalRevision, context: original.context)
                case "delete": try await store.deleteCollection(expectedRevision: original.context.originalRevision!, context: original.context)
                default: _ = try await store.readbackCollection(context: original.context)
                }
                XCTFail("A replacement scope cannot inherit the old editor")
            } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
            let updates = await service.updateCount, deletes = await service.deleteCount
            XCTAssertEqual(updates, 0); XCTAssertEqual(deletes, 0)
        }
    }
    func testLateCompareAndSaveCannotAdoptReplacementScope() async throws {
        for saving in [false, true] {
            let service = try CollectionStoreFixture(), store = BoardStore()
            await store.connect(service, allowCandidateWrites: true).value
            let original = try await store.beginCollectionEditor(id: collectionFixtureID)
            let latch = CollectionLatch()
            if saving { await service.delayNextUpdate(latch) } else { await service.delayNextRead(latch) }
            let pending = Task {
                if saving { return try await store.saveCollection(collectionFixtureInput("Pending"), expectedRevision: original.context.originalRevision, context: original.context) }
                return try await store.readbackCollection(context: original.context)
            }
            await latch.waitUntilStarted()
            await service.replaceConnectionScope(); await latch.release()
            do { _ = try await pending.value; XCTFail("Late response cannot be retagged") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        }
    }
}
