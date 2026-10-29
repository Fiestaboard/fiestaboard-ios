import XCTest
@testable import FiestaBoardAppState
import FiestaBoardKit

@MainActor final class PageLibraryTests: XCTestCase {
    func testCreatePanelUpdatesLibraryAndPreservesGeometry() async throws {
        let store = BoardStore(); let demo = try DemoFiestaBoardService()
        await store.connect(demo).value
        let library = try XCTUnwrap(store.pageLibrary)
        library.name = "My LED"; library.isPanel = true; library.rows = 8; library.columns = 16
        let id = try await store.createLibraryPage()
        let page = try XCTUnwrap(store.pages.first { $0.id == id })
        XCTAssertEqual(page.name, "My LED"); XCTAssertEqual(page.deviceType, "panel")
        XCTAssertEqual(page.gridRows, 8); XCTAssertEqual(page.gridCols, 16)
        XCTAssertFalse(library.needsReview); XCTAssertFalse(library.busy)
        XCTAssertEqual(library.name, "")
    }
    func testUnknownCreationRetainsInputAndRequiresExplicitReadbackAndNewIntent() async throws {
        let store = BoardStore(); let demo = try DemoFiestaBoardService()
        await store.connect(demo).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Uncertain page"
        await demo.setSimulation(.unknown)
        do { _ = try await store.createLibraryPage(); XCTFail("Expected unknown") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        XCTAssertEqual(library.name, "Uncertain page"); XCTAssertTrue(library.needsReview)
        XCTAssertFalse(library.canCreate)
        await demo.setSimulation(.accepted)
        do { _ = try await store.createLibraryPage(); XCTFail("Must not dispatch again") } catch {}
        await store.reviewPageLibrary()
        XCTAssertEqual(store.pages.filter { $0.name == "Uncertain page" }.count, 1)
        XCTAssertTrue(library.needsReview, "Matching name is not a success receipt or replay permission")
        store.acknowledgePageLibraryReview()
        XCTAssertFalse(library.needsReview); XCTAssertTrue(library.canCreate)
        XCTAssertEqual(library.name, "Uncertain page")
    }
    func testDeleteOriginalRevisionRefusesAfterConcurrentEdit() async throws {
        let store = BoardStore(); let demo = try DemoFiestaBoardService()
        await store.connect(demo).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Delete test"
        let id = try await store.createLibraryPage()
        try await store.preparePageDeletion(id: id)
        let document = try await store.loadPageDocument(id: id)
        _ = try await store.savePage(patch: .init(name: "Edited", expectedRevision: try XCTUnwrap(document.context.originalRevision)), context: document.context)
        do { try await store.deleteLibraryPage(); XCTFail("Old confirmation must fail") } catch {}
        XCTAssertNotNil(store.pages.first { $0.id == id })
    }
    func testConfirmedDeletionRefreshesPagesAndBoardState() async throws {
        let store = BoardStore(); let demo = try DemoFiestaBoardService()
        await store.connect(demo).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Delete me"
        let id = try await store.createLibraryPage()
        try await store.preparePageDeletion(id: id)
        try await store.deleteLibraryPage()
        XCTAssertFalse(store.pages.contains { $0.id == id })
        XCTAssertNil(library.deletion); XCTAssertFalse(library.needsReview)
        XCTAssertTrue(library.phase.message?.contains("deleted") == true)
    }
    func testUnknownStateSurvivesDisconnectAndReconnect() async throws {
        let store = BoardStore(); let demo = try DemoFiestaBoardService()
        await store.connect(demo).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Keep me"
        await demo.setSimulation(.unknown)
        do { _ = try await store.createLibraryPage() } catch {}
        store.disconnect(); await store.connect(demo).value
        XCTAssertTrue(store.pageLibrary === library)
        XCTAssertEqual(store.pageLibrary?.name, "Keep me")
        XCTAssertEqual(store.pageLibrary?.needsReview, true)
    }
}

extension PageLibraryTests {
    func testExplicitReviewAfterUnknownUnchangedDeleteAllowsFreshConfirmation() async throws {
        let service = try LibraryGateService(); let store = BoardStore()
        await store.connect(service).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Keep until confirmed"
        let id = try await store.createLibraryPage()
        try await store.preparePageDeletion(id: id)
        await service.failDeletion(.unknownMutationOutcome)
        do { try await store.deleteLibraryPage(); XCTFail() } catch {}
        XCTAssertTrue(library.needsReview)
        await store.reviewPageLibrary(); store.acknowledgePageLibraryReview()
        await service.failDeletion(nil)
        try await store.preparePageDeletion(id: id)
        try await store.deleteLibraryPage()
        XCTAssertFalse(store.pages.contains { $0.id == id })
    }
    func testLibraryRefreshCannotRaceInFlightCreation() async throws {
        let service = try LibraryGateService(); let store = BoardStore()
        await store.connect(service).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "New page"
        await service.holdCreation()
        let create = Task { try await store.createLibraryPage() }
        await service.waitForCreation()
        let before = await service.libraryReads
        await store.refreshLibrary().value
        let after = await service.libraryReads
        XCTAssertEqual(after, before, "A refresh must not start from a mid-mutation snapshot")
        await service.releaseCreation()
        let id = try await create.value
        XCTAssertTrue(store.pages.contains { $0.id == id })
    }
    func testDeletionRemainsBusyUntilDependentReadbackFinishes() async throws {
        let service = try LibraryGateService(); let store = BoardStore()
        await store.connect(service).value
        let library = try XCTUnwrap(store.pageLibrary); library.name = "Delete me"
        let id = try await store.createLibraryPage()
        try await store.preparePageDeletion(id: id)
        await service.holdLibraryRead()
        let deletion = Task { try await store.deleteLibraryPage() }
        await service.waitForLibraryRead()
        XCTAssertTrue(library.busy, "Acknowledgement is not completion of dependent readback")
        await service.releaseLibraryRead()
        try await deletion.value
    }
}

private actor LibraryGateService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = true
    let base: DemoFiestaBoardService
    var libraryReads = 0
    private var deletionError: FiestaBoardError?
    private var gateCreation = false
    private var gateLibrary = false
    private var creationWaiter: CheckedContinuation<Void, Never>?
    private var libraryWaiter: CheckedContinuation<Void, Never>?
    init() throws { base = try DemoFiestaBoardService(); deployment = base.deployment }
    func failDeletion(_ error: FiestaBoardError?) { deletionError = error }
    func holdCreation() { gateCreation = true }
    func holdLibraryRead() { gateLibrary = true }
    func waitForCreation() async { while creationWaiter == nil { await Task.yield() } }
    func waitForLibraryRead() async { while libraryWaiter == nil { await Task.yield() } }
    func releaseCreation() { creationWaiter?.resume(); creationWaiter = nil; gateCreation = false }
    func releaseLibraryRead() { libraryWaiter?.resume(); libraryWaiter = nil; gateLibrary = false }
    func authStatus() async throws -> AuthStatus { try await base.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await base.login(username: username, password: password) }
    func logout() async throws { try await base.logout() }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus { try await base.connect(allowCandidateWrites: allowCandidateWrites) }
    func boards() async throws -> [BoardSummary] { try await base.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail { try await base.board(target) }
    func pages() async throws -> [Page] {
        libraryReads += 1; let result = try await base.pages()
        if gateLibrary { await withCheckedContinuation { libraryWaiter = $0 } }
        return result
    }
    func page(id: String) async throws -> Page { try await base.page(id: id) }
    func pageDocumentData(id: String) async throws -> Data { try await base.pageDocumentData(id: id) }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { try await base.savePage(id: id, patch: patch) }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { try await base.updateBoard(patch, on: target) }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await base.restoreBoard(target) }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { try await base.sendText(text, to: target) }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await base.selectPage(id: id, on: target) }
    func pageManagementCapability() async -> PageManagementCapability { await base.pageManagementCapability() }
    func preparePageCreation(_ input: PageCreationInput) async throws -> PageCreationContext { try await base.preparePageCreation(input) }
    func createPage(context: PageCreationContext) async throws -> PageCreationReceipt {
        if gateCreation { await withCheckedContinuation { creationWaiter = $0 } }
        return try await base.createPage(context: context)
    }
    func readPageForDeletion(id: String) async throws -> PageDeletionContext { try await base.readPageForDeletion(id: id) }
    func deletePage(context: PageDeletionContext) async throws -> PageDeletionReceipt {
        if let deletionError { throw deletionError }
        return try await base.deletePage(context: context)
    }
}
