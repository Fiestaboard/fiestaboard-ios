import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class BoardStoreTests: XCTestCase {
    func testDemoLoadsAndCapturedTargetIsInvalidatedByBoardChange() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        XCTAssertEqual(store.status?.access, .simulated)
        XCTAssertEqual(store.board?.summary.id, "board-2")
        let action = try XCTUnwrap(store.prepare(.text("CAPTURED")))
        await store.selectBoard("board-led").value
        await store.confirm(action).value
        await store.selectBoard("board-2").value
        XCTAssertNotEqual(store.board?.text, "CAPTURED")
    }
    func testConfirmationUsesOriginalTextAndSuppressesDuplicateTap() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let action = try XCTUnwrap(store.prepare(.text("ORIGINAL")))
        let first = store.confirm(action)
        XCTAssertTrue(store.commandBusy)
        let second = store.confirm(action)
        await first.value; await second.value
        XCTAssertEqual(store.board?.text, "ORIGINAL")
        XCTAssertFalse(store.commandBusy)
        XCTAssertTrue(store.message?.contains("Simulated") == true)
    }
    func testUnknownOutcomeRequiresReadbackAndDoesNotReplay() async throws {
        let demo = try FixtureFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("MAYBE")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("unknown") == true)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback)
        XCTAssertEqual(store.board?.text, "MAYBE")
    }
    func testHeldPageSeparatesSelectionFromReportedOutput() async throws {
        let demo = try FixtureFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        let previous = store.board?.characters
        await demo.setSimulation(.held)
        await store.confirm(try XCTUnwrap(store.prepare(.page("page-weather")))).value
        XCTAssertEqual(store.board?.activePageID, "page-weather")
        XCTAssertEqual(store.board?.characters, previous)
        XCTAssertTrue(store.message?.contains("selection stored") == true)
    }
    func testLateBoardSnapshotCannotReplaceAnotherBoard() async throws {
        let delayed = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(delayed).value
        await delayed.delayNextRead()
        let oldRead = store.refresh()
        await delayed.waitUntilBlocked()
        await store.selectBoard("board-led").value
        await delayed.release()
        await oldRead.value
        XCTAssertEqual(store.board?.summary.id, "board-led")
    }
    func testTargetRemainsLockedAfterChangingAwayDuringCommandUntilReadback() async throws {
        let delayed = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(delayed).value
        await delayed.delayNextMutation()
        let action = try XCTUnwrap(store.prepare(.text("ONCE")))
        let command = store.confirm(action)
        let duplicate = store.confirm(action)
        await delayed.waitUntilBlocked()
        await store.selectBoard("board-led").value
        await store.selectBoard("board-2").value
        XCTAssertTrue(store.commandBusy)
        await delayed.release()
        await command.value; await duplicate.value
        let count = await delayed.sentCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback)
        XCTAssertTrue(store.canWrite)
        XCTAssertEqual(store.board?.text, "ONCE")
    }
    func testPartialAndRejectedOutcomesAreNotAcknowledgedAsSuccess() async throws {
        let demo = try FixtureFiestaBoardService()
        let store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.partial)
        await store.confirm(try XCTUnwrap(store.prepare(.text("PART")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertTrue(store.message?.contains("Only part") == true)
        await store.refresh().value
        await demo.setSimulation(.rejected)
        await store.confirm(try XCTUnwrap(store.prepare(.text("REFUSED")))).value
        XCTAssertTrue(store.message?.contains("refused") == true)
        XCTAssertNotEqual(store.board?.text, "REFUSED")
    }
    func testRefreshAuthenticationLossInvalidatesControlsAndCapturedConfirmation() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertEqual(store.status?.access, .candidateWrites)
        let captured = try XCTUnwrap(store.prepare(.text("STALE")))
        await service.rejectNextRead()
        await store.refresh().value
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("sign in again") == true)
        await store.confirm(captured).value
        let sends = await service.sentCount
        XCTAssertEqual(sends, 0)
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertTrue(store.canWrite)
        await store.confirm(captured).value
        let sendsAfterReauthentication = await service.sentCount
        XCTAssertEqual(sendsAfterReauthentication, 0, "A confirmation from the expired session stays invalid after reconnecting")
    }
    func testAcknowledgedMutationReceiptSurvivesAuthenticationLossDuringReadback() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        let action = try XCTUnwrap(store.prepare(.text("ACKNOWLEDGED")))
        await service.rejectNextRead()
        await store.confirm(action).value
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("server acknowledged a send") == true)
        XCTAssertTrue(store.message?.contains("sign in again") == true)
        await store.confirm(action).value
        let sends = await service.sentCount
        XCTAssertEqual(sends, 1, "Readback authentication failure must not replay the acknowledged write")
    }
    func testFailedRemoteLogoutIsVisibleAfterImmediateLocalDisconnect() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service).value
        await service.configureLogout(fails: true, delayed: true)
        let logout = store.logout()
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(store.message?.contains("Signing out") == true)
        XCTAssertEqual(store.remoteLogoutState, .pending)
        await service.waitForLogout()
        await service.releaseLogout()
        await logout.value
        XCTAssertEqual(store.remoteLogoutState, .failed)
        XCTAssertTrue(store.message?.contains("could not be confirmed") == true)
        XCTAssertTrue(store.message?.contains("may still be active") == true)
    }
    func testSuccessfulRemoteLogoutIsAcknowledgedAfterImmediateLocalDisconnect() async throws {
        let service = try SessionFaultService()
        let store = BoardStore()
        await store.connect(service).value
        await store.logout().value
        XCTAssertNil(store.status)
        XCTAssertEqual(store.remoteLogoutState, .succeeded)
        XCTAssertTrue(store.message?.contains("Server sign-out confirmed") == true)
    }
    func testLateOldLogoutCannotOverwriteNewConnectionOrMessage() async throws {
        for fails in [false, true] {
            let old = try SessionFaultService()
            let store = BoardStore()
            await store.connect(old).value
            await old.configureLogout(fails: fails, delayed: true)
            let logout = store.logout()
            await old.waitForLogout()
            await store.connect(try FixtureFiestaBoardService()).value
            let selected = try XCTUnwrap(store.prepare(.text("NEW SESSION")))
            await store.confirm(selected).value
            let newMessage = store.message
            await old.releaseLogout()
            await logout.value
            XCTAssertEqual(store.status?.access, .simulated)
            XCTAssertEqual(store.connectionLabel, "Demo · simulated")
            XCTAssertEqual(store.board?.text, "NEW SESSION")
            XCTAssertEqual(store.message, newMessage)
            XCTAssertNil(store.remoteLogoutState)
        }
    }
    func testLateConnectionCannotRestoreDisconnectedSession() async throws {
        let delayed = try DelayedService()
        let store = BoardStore()
        let task = store.connect(delayed)
        await delayed.waitUntilBlocked()
        store.disconnect()
        await delayed.release()
        await task.value
        XCTAssertNil(store.status)
        XCTAssertNil(store.board)
        XCTAssertTrue(store.boards.isEmpty)
        XCTAssertEqual(store.connectionLabel, "Disconnected")
    }
    func testOldServerResultCannotReplaceNewDemo() async throws {
        let delayed = try DelayedService()
        let store = BoardStore()
        let first = store.connect(delayed)
        await delayed.waitUntilBlocked()
        await store.connect(try FixtureFiestaBoardService()).value
        await delayed.release()
        await first.value
        XCTAssertEqual(store.status?.access, .simulated)
        XCTAssertEqual(store.board?.summary.id, "board-2")
        XCTAssertNil(store.message)
    }
}

// Delays an actual demo connect result even after task cancellation, modeling a late server reply.
private actor DelayedService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = true
    private let demo: FixtureFiestaBoardService
    private let delayConnection: Bool
    private var delaySchedule = false
    private var scheduleFailure: FiestaBoardError?
    func delayNextSchedule() { delaySchedule = true }
    func failSchedule(_ error: FiestaBoardError?) { scheduleFailure = error }
    func schedules(on target: BoardTarget) async throws -> ScheduleList {
        let result = try await demo.schedules(on: target)
        if delaySchedule { delaySchedule = false; await hold() }
        if let scheduleFailure { throw scheduleFailure }
        return result
    }
    private var delayRead = false
    private var delayMutation = false
    private var delayPage = false
    private var delayPreview = false
    private var flexibleDocument = false
    func useFlexibleDocument() { flexibleDocument = true }
    private var previewFailure: FiestaBoardError?
    func failNextPreview() { previewFailure = .networkUnavailable }
    func delayNextPreview() { delayPreview = true }
    private(set) var sentCount = 0
    func delayNextRead() { delayRead = true }
    func delayNextPageRead() { delayPage = true }
    func delayNextMutation() { delayMutation = true }
    private var gate: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    init(delayConnection: Bool = true) throws { let d = try FixtureFiestaBoardService(); demo = d; deployment = d.deployment; self.delayConnection = delayConnection }
    func waitUntilBlocked() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func release() { gate?.resume(); gate = nil }
    func authStatus() async throws -> AuthStatus { try await demo.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await demo.login(username: username, password: password) }
    func logout() async throws { try await demo.logout() }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        let value = try await demo.connect(allowCandidateWrites: allowCandidateWrites)
        if delayConnection { await hold() }
        return value
    }
    private func hold() async {
        await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] }
    }
    func boards() async throws -> [BoardSummary] { try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail {
        let detail = try await demo.board(target)
        if delayRead { delayRead = false; await hold() }
        return detail
    }
    func pages() async throws -> [Page] { try await demo.pages() }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func scopedPageDocument(id: String) async throws -> ScopedPageDocument {
        let value = try await demo.scopedPageDocument(id: id)
        if delayPage { delayPage = false; await hold() }
        if flexibleDocument {
            let data = Data(#"{"id":"page-selected","name":"Flexible","type":"flexible","document_protocol":"page-document-v2","edit_protocol":"page-revision-v1","revision":"original","blocks":[{"id":"text","kind":"text","text":"Text"}]}"#.utf8)
            return ScopedPageDocument(data: data, scope: value.scope)
        }
        return value
    }
    func pageDocumentData(id: String) async throws -> Data {
        let value = try await demo.pageDocumentData(id: id)
        if delayPage { delayPage = false; await hold() }
        return value
    }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt {
        sentCount += 1
        let value = try await demo.savePage(id: id, patch: patch)
        if delayMutation { delayMutation = false; await hold() }
        return value
    }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult {
        try await demo.validatePage(requestData: requestData, target: target)
    }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult {
        if let error = previewFailure { previewFailure = nil; throw error }
        let value = try await demo.previewPage(requestData: requestData, target: target)
        if delayPreview { delayPreview = false; await hold() }
        return value
    }
    func previewFlexiblePage(requestData: Data, target: BoardTarget) async throws -> FlexiblePreviewResult {
        if let error = previewFailure { previewFailure = nil; throw error }
        if delayPreview { delayPreview = false; await hold() }
        return try FlexiblePreviewResult(rawData: Data(#"{"available":true,"page_id":"unsaved","message":"Text","lines":["Text"],"display_type":"template","raw":{},"layout_issues":[]}"#.utf8))
    }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult {
        sentCount += 1
        let result = try await demo.sendText(text, to: target)
        if delayMutation { delayMutation = false; await hold() }
        return result
    }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt {
        sentCount += 1
        let result = try await demo.updateBoard(patch, on: target)
        if delayMutation { delayMutation = false; await hold() }
        return result
    }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await demo.restoreBoard(target) }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await demo.selectPage(id: id, on: target) }
}

// Real demo data/actions with bounded faults at the service boundary; never constructs networking.
private actor SessionFaultService: FiestaBoardService {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    private let demo: FixtureFiestaBoardService
    private var rejectRead = false
    private var pageFailure: FiestaBoardError?
    private var documentContract: (version: String?, advertised: Bool, dev: Bool, hasRevision: Bool)?
    private(set) var pageSaveCount = 0
    func configureDocumentContract(version: String?, advertised: Bool, dev: Bool, hasRevision: Bool) {
        documentContract = (version, advertised, dev, hasRevision)
    }
    private var managementAccess: PageManagementCapability?
    func setManagementAccess(_ value: PageManagementCapability) { managementAccess = value }
    func pageManagementCapability() async -> PageManagementCapability {
        managementAccess ?? .init(canCreate: false, canDelete: false)
    }
    private var detailFailure: FiestaBoardError?
    private var emptyBoards = false
    private var delayPages = false
    private var pagesGate: CheckedContinuation<Void, Never>?
    private var pagesObservers: [CheckedContinuation<Void, Never>] = []
    func blockPages() { delayPages = true }
    func waitForPages() async { if pagesGate != nil { return }; await withCheckedContinuation { pagesObservers.append($0) } }
    func releasePages() { pagesGate?.resume(); pagesGate = nil }
    private var delayDisconnect = false
    private var disconnectGate: CheckedContinuation<Void, Never>?
    private var disconnectObservers: [CheckedContinuation<Void, Never>] = []
    private(set) var lifecycle: [String] = []
    private var failLogout = false
    private var delayLogout = false
    private var logoutGate: CheckedContinuation<Void, Never>?
    private var logoutObservers: [CheckedContinuation<Void, Never>] = []
    private(set) var sentCount = 0
    init() throws { let demo = try FixtureFiestaBoardService(); self.demo = demo; deployment = demo.deployment }
    func rejectNextRead() { rejectRead = true }
    func failPages(_ error: FiestaBoardError?) { pageFailure = error }
    func failDetail(_ error: FiestaBoardError?) { detailFailure = error }
    func setEmptyBoards() { emptyBoards = true }
    func blockDisconnect() { delayDisconnect = true }
    func waitForDisconnect() async { if disconnectGate != nil { return }; await withCheckedContinuation { disconnectObservers.append($0) } }
    func releaseDisconnect() { disconnectGate?.resume(); disconnectGate = nil }
    func disconnect() async {
        lifecycle.append("disconnect-start")
        if delayDisconnect { await withCheckedContinuation { disconnectGate = $0; disconnectObservers.forEach { $0.resume() }; disconnectObservers = [] } }
        lifecycle.append("disconnect-end")
    }
    func configureLogout(fails: Bool, delayed: Bool) { failLogout = fails; delayLogout = delayed }
    func waitForLogout() async {
        if logoutGate != nil { return }
        await withCheckedContinuation { logoutObservers.append($0) }
    }
    func releaseLogout() { logoutGate?.resume(); logoutGate = nil }
    func authStatus() async throws -> AuthStatus { lifecycle.append("auth"); return try await demo.authStatus() }
    func login(username: String, password: String) async throws -> AuthStatus { try await demo.login(username: username, password: password) }
    func logout() async throws {
        if delayLogout {
            await withCheckedContinuation { logoutGate = $0; logoutObservers.forEach { $0.resume() }; logoutObservers = [] }
        }
        if failLogout { throw FiestaBoardError.networkUnavailable }
        try await demo.logout()
    }
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus {
        let status = try await demo.connect(allowCandidateWrites: true)
        // Only the UI permission projection differs from demo; service data/actions remain real and isolated.
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status)) as! [String: Any]
        value["access"] = "candidateWrites"; value["isDemo"] = false
        if let documentContract, var version = value["version"] as? [String: Any] {
            version["running_version"] = documentContract.version
            version["is_dev"] = documentContract.dev
            value["version"] = version
        }
        return try JSONDecoder().decode(ConnectionStatus.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func boards() async throws -> [BoardSummary] { if emptyBoards { return [] }; return try await demo.boards() }
    func board(_ target: BoardTarget) async throws -> BoardDetail {
        if let detailFailure { throw detailFailure }
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        return try await demo.board(target)
    }
    func pages() async throws -> [Page] {
        if delayPages { await withCheckedContinuation { pagesGate = $0; pagesObservers.forEach { $0.resume() }; pagesObservers = [] } }
        if let pageFailure { throw pageFailure }; return try await demo.pages()
    }
    func page(id: String) async throws -> Page { try await demo.page(id: id) }
    func scopedPageDocument(id: String) async throws -> ScopedPageDocument {
        let scope = try await demo.scopedPageDocument(id: id).scope
        return ScopedPageDocument(data: try await pageDocumentData(id: id), scope: scope)
    }
    func pageDocumentData(id: String) async throws -> Data {
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        let data = try await demo.pageDocumentData(id: id)
        guard let documentContract else { return data }
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if !documentContract.advertised { object.removeValue(forKey: "document_protocol") }
        if !documentContract.hasRevision { object.removeValue(forKey: "revision") }
        return try JSONSerialization.data(withJSONObject: object)
    }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt {
        pageSaveCount += 1
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        return try await demo.savePage(id: id, patch: patch)
    }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult {
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        return try await demo.validatePage(requestData: requestData, target: target)
    }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult {
        if rejectRead { rejectRead = false; throw FiestaBoardError.unauthenticated }
        return try await demo.previewPage(requestData: requestData, target: target)
    }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult {
        sentCount += 1
        return try await demo.sendText(text, to: target)
    }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { try await demo.updateBoard(patch, on: target) }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { try await demo.restoreBoard(target) }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { try await demo.selectPage(id: id, on: target) }
}


extension BoardStoreTests {
    func testControlsUseImmutableConfirmationAndConfigurationCopy() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let pause = try XCTUnwrap(store.prepare(.configuration(BoardPatch(paused: true))))
        await store.confirm(pause).value
        XCTAssertEqual(store.board?.summary.paused, true)
        XCTAssertEqual(store.boards.first?.paused, true)
        XCTAssertTrue(store.message?.contains("settings updated") == true)
        XCTAssertFalse(store.message?.contains("acknowledged a send") == true)
        await store.confirm(pause).value
        let stale = try XCTUnwrap(store.prepare(.configuration(BoardPatch(paused: false))))
        await store.selectBoard("board-led").value
        await store.confirm(stale).value
        await store.selectBoard("board-2").value
        XCTAssertEqual(store.board?.summary.paused, true)
        await store.confirm(try XCTUnwrap(store.prepare(.restore))).value
        XCTAssertTrue(store.message?.contains("refused") == true)
    }
    func testUnknownConfigurationNeedsRefreshAndCannotBeReplayed() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.unknown)
        let action = try XCTUnwrap(store.prepare(.configuration(BoardPatch(scheduleEnabled: true))))
        await store.confirm(action).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertNil(store.prepare(.restore))
        await store.refresh().value
        XCTAssertEqual(store.board?.summary.scheduleEnabled, true)
        await demo.setSimulation(.accepted)
        await store.confirm(try XCTUnwrap(store.prepare(.configuration(BoardPatch(scheduleEnabled: false))))).value
        await store.confirm(action).value
        XCTAssertEqual(store.board?.summary.scheduleEnabled, false)
    }
    func testLateConfigurationDoesNotReplaceDifferentBoardAndNoDuplicateWrites() async throws {
        let delayed = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(delayed).value
        await delayed.delayNextMutation()
        let action = try XCTUnwrap(store.prepare(.configuration(BoardPatch(paused: true))))
        let first = store.confirm(action), duplicate = store.confirm(action)
        await delayed.waitUntilBlocked()
        await store.selectBoard("board-led").value
        await delayed.release()
        await first.value; await duplicate.value
        XCTAssertEqual(store.board?.summary.id, "board-led")
        XCTAssertEqual(store.board?.summary.paused, false)
        let writes = await delayed.sentCount
        XCTAssertEqual(writes, 1)
        await store.selectBoard("board-2").value
        XCTAssertEqual(store.board?.summary.paused, true)
    }
}


extension BoardStoreTests {
    func testPageDocumentSnapshotBindsDeploymentAndPageIdentity() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let snapshot = try await store.loadPageDocument(id: "page-selected")
        XCTAssertEqual(snapshot.id, "page-selected")
        XCTAssertEqual(snapshot.deployment, demo.deployment)
        XCTAssertEqual(snapshot.scope.deployment, demo.deployment)
        XCTAssertTrue(snapshot.scope.isDemo)
        XCTAssertEqual(snapshot.context.scope, snapshot.scope)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])?["id"] as? String, "page-selected")
        XCTAssertFalse(snapshot.data.isEmpty)
    }
}

extension BoardStoreTests {
    func testLatePageDocumentCannotCrossConnections() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        await service.delayNextPageRead()
        let old = Task { try await store.loadPageDocument(id: "page-selected") }
        await service.waitUntilBlocked()
        await store.connect(try FixtureFiestaBoardService()).value
        await service.release()
        do { _ = try await old.value; XCTFail("Expected stale snapshot rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
    func testPageDocumentAuthenticationLossInvalidatesSession() async throws {
        let service = try SessionFaultService(), store = BoardStore()
        await store.connect(service).value
        await service.rejectNextRead()
        do { _ = try await store.loadPageDocument(id: "page-selected"); XCTFail("Expected auth failure") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unauthenticated) }
        XCTAssertNil(store.status)
        XCTAssertTrue(store.message?.contains("sign in again") == true)
    }
}

extension BoardStoreTests {
    func testRefusedConfigurationStillRequiresReadbackBecauseSettersMayPartiallyApply() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        await demo.setSimulation(.rejected)
        await store.confirm(try XCTUnwrap(store.prepare(.configuration(BoardPatch(paused: true))))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        XCTAssertEqual(store.board?.summary.paused, false)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback)
        XCTAssertTrue(store.canWrite)
    }
    func testRestoreUnknownOutcomeRequiresRefreshWithoutClearingPinnedPage() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let pinned = store.board?.activePageID
        await demo.setSimulation(.unknown)
        let action = try XCTUnwrap(store.prepare(.restore))
        await store.confirm(action).value
        XCTAssertTrue(store.needsReadback)
        await store.refresh().value
        XCTAssertEqual(store.board?.activePageID, pinned)
        await demo.setSimulation(.accepted)
        await store.confirm(action).value
        XCTAssertTrue(store.message?.contains("unknown") == true, "Used restore confirmation cannot be replayed")
        await store.confirm(try XCTUnwrap(store.prepare(.restore))).value
        XCTAssertTrue(store.message?.contains("Restore write accepted") == true)
    }
}

extension BoardStoreTests {
    func testPageSaveReturnsNewContextAndRejectsOldContext() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let original = try await store.loadPageDocument(id: "page-selected")
        XCTAssertTrue(original.editingAccess.canSave)
        let saved = try await store.savePage(patch: PageSavePatch(name: "Stored only", expectedRevision: original.context.originalRevision!), context: original.context)
        XCTAssertTrue(saved.editingAccess.canSave)
        XCTAssertNotEqual(saved.context, original.context)
        XCTAssertEqual(store.pages.first?.name, "Stored only")
        do { _ = try await store.savePage(patch: PageSavePatch(name: "Replay", expectedRevision: original.context.originalRevision!), context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .stalePageContext) }
    }
    func testSameURLReconnectInvalidatesLoadedPageContext() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await store.reconnect(allowCandidateWrites: true).value
        do { _ = try await store.savePage(patch: PageSavePatch(name: "Old session", expectedRevision: original.context.originalRevision!), context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
    func testUnknownPageSaveRequiresExplicitReadAndDoesNotReplay() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await demo.setSimulation(.unknown)
        let patch = PageSavePatch(name: "Maybe stored", expectedRevision: original.context.originalRevision!)
        do { _ = try await store.savePage(patch: patch, context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        await demo.setSimulation(.accepted)
        do { _ = try await store.savePage(patch: patch, context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        let readback = try await store.loadPageDocument(id: original.id)
        XCTAssertNotEqual(readback.context.originalRevision, original.context.originalRevision)
        let page = try JSONDecoder().decode(Page.self, from: readback.data)
        XCTAssertEqual(page.name, "Maybe stored")
    }
}

extension BoardStoreTests {
    func testDuplicatePageSaveAndLateSameURLSessionAreGuardedUntilReadback() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await service.delayNextMutation()
        let patch = PageSavePatch(name: "Once", expectedRevision: original.context.originalRevision!)
        let first = Task { try await store.savePage(patch: patch, context: original.context) }
        await service.waitUntilBlocked()
        do { _ = try await store.savePage(patch: patch, context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        do { _ = try await store.readbackPage(context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        await store.reconnect(allowCandidateWrites: true).value
        await service.release()
        do { _ = try await first.value; XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let count = await service.sentCount
        XCTAssertEqual(count, 1)
        let readback = try await store.loadPageDocument(id: original.id)
        let page = try JSONDecoder().decode(Page.self, from: readback.data)
        XCTAssertEqual(page.name, "Once")
    }
    func testPreviewAcceptsAnyKnownBoardAndDropsReplyAfterBoardOrDocumentChanges() async throws {
        for changeDocument in [false, true] {
            let service = try DelayedService(delayConnection: false), store = BoardStore()
            await store.connect(service).value
            let original = try await store.loadPageDocument(id: "page-selected")
            let target = try BoardTarget(deployment: service.deployment, boardID: "board-led")
            let body = Data(#"{"template":["🛰️"],"board_id":"board-led"}"#.utf8)
            let accepted = try await store.previewPage(requestData: body, context: original.context, target: target)
            XCTAssertTrue(accepted.isSimulated)
            await service.delayNextPreview()
            let preview = Task { try await store.previewPage(requestData: body, context: original.context, target: target) }
            await service.waitUntilBlocked()
            if changeDocument { _ = try await store.loadPageDocument(id: original.id) }
            else { await store.selectBoard("board-led").value }
            await service.release()
            do { _ = try await preview.value; XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, changeDocument ? .stalePageContext : .staleSession) }
        }
    }
    func testPageActionsInvalidateAuthenticationAndDoNotCrossReadbackContext() async throws {
        for action in ["save", "validate", "preview"] {
            let service = try SessionFaultService(), store = BoardStore()
            await store.connect(service, allowCandidateWrites: true).value
            let original = try await store.loadPageDocument(id: "page-selected")
            let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
            let body = Data(#"{"template":[],"board_id":"board-2"}"#.utf8)
            await service.rejectNextRead()
            do {
                switch action {
                case "save": _ = try await store.savePage(patch: PageSavePatch(name: "Auth lost", expectedRevision: original.context.originalRevision!), context: original.context)
                case "validate": _ = try await store.validatePage(requestData: body, context: original.context, target: target)
                default: _ = try await store.previewPage(requestData: body, context: original.context, target: target)
                }
                XCTFail()
            } catch { XCTAssertEqual(error as? FiestaBoardError, .unauthenticated) }
            XCTAssertNil(store.status)
            await store.connect(service, allowCandidateWrites: true).value
            do { _ = try await store.readbackPage(context: original.context); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        }
    }
    func testRecoveredBaselineRevisionIsSentUnchangedAndConflicts() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let original = try await store.loadPageDocument(id: "page-selected")
        do { _ = try await store.savePage(patch: PageSavePatch(name: "Recovered", expectedRevision: "old-recovered-revision"), context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageConflict) }
        XCTAssertFalse(store.pageEditingAccess(context: original.context).canSave)
        let readback = try await store.readbackPage(context: original.context)
        XCTAssertTrue(readback.editingAccess.canSave)
    }
}

extension BoardStoreTests {
    func testPreviewFailureLeavesPageStorageAvailableWithoutReadback() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await service.failNextPreview()
        do {
            _ = try await store.previewPage(requestData: Data(#"{"template":[],"board_id":"board-2"}"#.utf8), context: original.context,
                                            target: BoardTarget(deployment: service.deployment, boardID: "board-2"))
            XCTFail()
        } catch { XCTAssertEqual(error as? FiestaBoardError, .networkUnavailable) }
        XCTAssertTrue(store.pageEditingAccess(context: original.context).canSave)
        let result = try await store.savePage(patch: PageSavePatch(name: "Can save", expectedRevision: original.context.originalRevision!), context: original.context)
        XCTAssertTrue(result.editingAccess.canSave)
    }
}

extension BoardStoreTests {
    func testReadStartedBeforeSaveCannotReplaceAcknowledgedRevision() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await service.delayNextPageRead()
        let read = Task { try await store.readbackPage(context: original.context) }
        await service.waitUntilBlocked()
        let saved = try await store.savePage(patch: PageSavePatch(name: "Newest", expectedRevision: original.context.originalRevision!), context: original.context)
        await service.release()
        do { _ = try await read.value; XCTFail("Old read must not replace save receipt") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .stalePageContext) }
        XCTAssertTrue(store.pageEditingAccess(context: saved.context).canSave)
        XCTAssertEqual(store.pages.first?.name, "Newest")
    }
}

extension BoardStoreTests {
    func testComparisonReadbackInvalidatesOldPageContextWithoutLosingSession() async throws {
        let demo = try FixtureFiestaBoardService(), store = BoardStore()
        await store.connect(demo).value
        let original = try await store.loadPageDocument(id: "page-selected")
        let comparison = try await store.readbackPage(context: original.context)
        let target = try BoardTarget(deployment: demo.deployment, boardID: "board-2")
        let body = Data(#"{"template":[],"board_id":"board-2"}"#.utf8)
        do { _ = try await store.validatePage(requestData: body, context: original.context, target: target); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .stalePageContext) }
        XCTAssertNotNil(store.status)
        XCTAssertTrue(store.pageEditingAccess(context: comparison.context).canSave)
        XCTAssertEqual(store.pageEditingAccess(context: original.context), .disabled(FiestaBoardError.stalePageContext.localizedDescription))
        await store.reconnect(allowCandidateWrites: true).value
        do { _ = try await store.readbackPage(context: comparison.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
}

extension BoardStoreTests {
    func testCancelledPreviewIsNotReportedAsSessionLoss() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
        await service.delayNextPreview()
        let preview = Task { try await store.previewPage(requestData: Data(#"{"template":[],"board_id":"board-2"}"#.utf8), context: original.context, target: target) }
        await service.waitUntilBlocked()
        preview.cancel()
        await service.release()
        do { _ = try await preview.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError, "Cancellation is not authentication or connection loss") }
        XCTAssertNotNil(store.status)
        XCTAssertTrue(store.pageEditingAccess(context: original.context).canSave)
    }
}

extension BoardStoreTests {
    func testCancelledSavePreservesReadbackLockWithoutClaimingSessionLoss() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        await service.delayNextMutation()
        let patch = PageSavePatch(name: "Stored before cancellation", expectedRevision: original.context.originalRevision!)
        let save = Task { try await store.savePage(patch: patch, context: original.context) }
        await service.waitUntilBlocked()
        save.cancel()
        await service.release()
        do { _ = try await save.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotNil(store.status)
        do { _ = try await store.savePage(patch: patch, context: original.context); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        let readback = try await store.readbackPage(context: original.context)
        let page = try JSONDecoder().decode(Page.self, from: readback.data)
        XCTAssertEqual(page.name, "Stored before cancellation")
        let count = await service.sentCount
        XCTAssertEqual(count, 1)
    }
}


extension BoardStoreTests {
    func testOptionalPageFailureKeepsAuthenticatedShell() async throws {
        let service = try SessionFaultService(); await service.failPages(.networkUnavailable)
        let store = BoardStore(); await store.connect(service).value
        XCTAssertNotNil(store.status); XCTAssertFalse(store.boards.isEmpty)
        XCTAssertNotNil(store.message); XCTAssertTrue(store.pages.isEmpty)
    }
    func testOptionalDetailFailureRequiresSuccessfulReadBeforeCommands() async throws {
        let service = try SessionFaultService(); await service.failDetail(.networkUnavailable)
        let store = BoardStore(); await store.connect(service, allowCandidateWrites: true).value
        XCTAssertNotNil(store.status); XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canWrite)
    }
    func testEmptyBoardListIsAConnectedServer() async throws {
        let service = try SessionFaultService(); await service.setEmptyBoards()
        let store = BoardStore(); await store.connect(service).value
        XCTAssertNotNil(store.status); XCTAssertTrue(store.boards.isEmpty); XCTAssertFalse(store.canWrite)
    }
    func testAuthenticationFailureInOptionalPagesInvalidatesConnection() async throws {
        let service = try SessionFaultService(); await service.failPages(.unauthenticated)
        let store = BoardStore(); await store.connect(service).value
        XCTAssertNil(store.status); XCTAssertFalse(store.canWrite)
    }
}

extension BoardStoreTests {
    func testOptionalLibraryCanBeRetriedWithoutReplacingSession() async throws {
        let service = try SessionFaultService(); await service.failPages(.networkUnavailable)
        let store = BoardStore(); await store.connect(service).value
        await service.failPages(nil)
        await store.refreshLibrary().value
        XCTAssertNotNil(store.status); XCTAssertFalse(store.pages.isEmpty)
    }
    func testDetailFailureUnlocksOnlyAfterSuccessfulRefresh() async throws {
        let service = try SessionFaultService(); await service.failDetail(.networkUnavailable)
        let store = BoardStore(); await store.connect(service, allowCandidateWrites: true).value
        await service.failDetail(nil); await store.refresh().value
        XCTAssertNotNil(store.board); XCTAssertFalse(store.needsReadback); XCTAssertTrue(store.canWrite)
    }
    func testReconnectDoesNotClearAmbiguousCommandBarrier() async throws {
        let demo = try FixtureFiestaBoardService(); let store = BoardStore(); await store.connect(demo).value
        await demo.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("UNKNOWN")))).value
        await store.reconnect(allowCandidateWrites: true).value
        XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canWrite)
        await store.refresh().value; XCTAssertTrue(store.canWrite)
    }
}

extension BoardStoreTests {
    func testSameServiceSettingReconnectPreservesActiveMemorySession() async throws {
        let service = try SessionFaultService(); let store = BoardStore()
        await store.connect(service).value; await store.reconnect(allowCandidateWrites: true).value
        let lifecycle = await service.lifecycle
        XCTAssertEqual(lifecycle, ["auth", "auth"])
    }
    func testDisconnectCleanupCompletesBeforeSameActorConnectCanAuthenticate() async throws {
        let service = try SessionFaultService(); let store = BoardStore()
        await store.connect(service).value; await service.blockDisconnect()
        store.disconnect(); await service.waitForDisconnect()
        let reconnect = store.connect(service)
        let suspended = await service.lifecycle; XCTAssertEqual(suspended, ["auth", "disconnect-start"])
        await service.releaseDisconnect(); await reconnect.value
        let lifecycle = await service.lifecycle
        XCTAssertEqual(lifecycle, ["auth", "disconnect-start", "disconnect-end", "auth"])
        XCTAssertNotNil(store.status)
    }
    func testStaleSessionInOptionalReadInvalidatesShell() async throws {
        let service = try SessionFaultService(); await service.failPages(.staleSession)
        let store = BoardStore(); await store.connect(service).value
        XCTAssertNil(store.status); XCTAssertFalse(store.canWrite)
    }
}

extension BoardStoreTests {
    func testOldLogoutWarningRemainsAvailableWithoutOverwritingNewConnection() async throws {
        let old = try SessionFaultService(); let store = BoardStore(); await store.connect(old).value
        await old.configureLogout(fails: true, delayed: true)
        let logout = store.logout(); await old.waitForLogout()
        await store.connect(try FixtureFiestaBoardService()).value
        await old.releaseLogout(); await logout.value
        XCTAssertEqual(store.status?.access, .simulated); XCTAssertNil(store.message)
        XCTAssertEqual(store.logoutNotices.last?.deployment, old.deployment)
        XCTAssertEqual(store.logoutNotices.last?.state, .failed)
    }
}

extension BoardStoreTests {
    func testLateOldOptionalPageAuthenticationFailureCannotDisconnectNewServer() async throws {
        let old = try SessionFaultService(); await old.blockPages(); await old.failPages(.unauthenticated)
        let store = BoardStore(); let first = store.connect(old); await old.waitForPages()
        await store.connect(try FixtureFiestaBoardService()).value
        await old.releasePages(); await first.value
        XCTAssertEqual(store.status?.access, .simulated); XCTAssertFalse(store.pages.isEmpty); XCTAssertNil(store.message)
    }
}

extension BoardStoreTests {
    func testInitialPreferredDetailLoadDoesNotRecoverAmbiguousCommand() async throws {
        for preferred in ["board-2", "board-led"] {
            let demo = try FixtureFiestaBoardService(); let store = BoardStore()
            await store.connect(demo).value
            await store.selectBoard(preferred).value
            await demo.setSimulation(.unknown)
            await store.confirm(try XCTUnwrap(store.prepare(.text("UNCERTAIN")))).value
            XCTAssertTrue(store.needsReadback)
            store.disconnect()
            await store.connect(demo, preferredBoardID: preferred).value
            XCTAssertEqual(store.selectedBoardID, preferred)
            XCTAssertEqual(store.board?.summary.id, preferred)
            XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canWrite)
            await store.refresh().value
            XCTAssertFalse(store.needsReadback); XCTAssertTrue(store.canWrite)
        }
    }
}

extension BoardStoreTests {
    func testMissingDefaultContextDisablesOnlyFallback() async throws {
        let store = BoardStore()
        let deployment = try DeploymentURL("https://board.test")
        let transport = try StoreDefaultTransport(failDefaultReads: true)
        await store.connect(LiveFiestaBoardService(deployment: deployment, transport: transport), allowCandidateWrites: true).value
        XCTAssertTrue(store.canWrite)
        XCTAssertFalse(store.canChangeDefaultPage)
        XCTAssertNil(store.prepare(.configuration(BoardPatch(defaultPage: .clear))))
        XCTAssertNotNil(store.prepare(.configuration(BoardPatch(paused: true))))
    }
}

extension BoardStoreTests {
    func testDefaultConfirmationRetainsOriginalRevisionAcrossExplicitRefreshAndRequiresReloadAfterConflict() async throws {
        let transport = try StoreDefaultTransport()
        let deployment = try DeploymentURL("https://board.test")
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let store = BoardStore()
        await store.connect(service, allowCandidateWrites: true).value
        XCTAssertTrue(store.canChangeDefaultPage)
        let prepared = try XCTUnwrap(store.prepare(.configuration(BoardPatch(defaultPage: .clear))))
        await store.refresh().value
        await store.confirm(prepared).value
        let revision = await transport.submittedRevision
        XCTAssertEqual(revision, "read-1")
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canChangeDefaultPage)
        XCTAssertTrue(store.message?.contains("changed") == true)
        await store.confirm(prepared).value
        let count = await transport.writes
        XCTAssertEqual(count, 1)
        await store.refresh().value
        XCTAssertTrue(store.canChangeDefaultPage)
    }
}
private actor StoreDefaultTransport: APITransport {
    private let fixtures: [String: Data]
    private var reads = 0
    private let failDefaultReads: Bool
    var writes = 0
    var submittedRevision: String?
    init(failDefaultReads: Bool = false) throws {
        self.failDefaultReads = failDefaultReads
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = packageRoot.appendingPathComponent("FiestaBoardKit/Tests/FiestaBoardKitTests/Fixtures")
        fixtures = try Dictionary(uniqueKeysWithValues: ["auth", "boards", "board", "pages"].map { ($0, try Data(contentsOf: directory.appendingPathComponent($0 + ".json"))) })
    }
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        if request.path == ["version"] { return APIResponse(status: 200, data: Data(#"{"package_version":"10.1.17","build_version":"test","running_version":"10.1.17","is_dev":false}"#.utf8)) }
        if request.path == ["schedules", "default-page"] {
            if request.method == .put {
                writes += 1
                submittedRevision = (try JSONSerialization.jsonObject(with: request.body!) as? [String: Any])?["expected_revision"] as? String
                return APIResponse(status: 412, data: Data())
            }
            if failDefaultReads { throw FiestaBoardError.networkUnavailable }
            reads += 1
            return APIResponse(status: 200, data: Data("{\"revision\":\"read-\(reads)\",\"edit_protocol\":\"schedule-default-revision-v1\",\"default_page_id\":null}".utf8))
        }
        let name = request.path == ["auth", "status"] ? "auth" : (request.path.last == "boards" ? "boards" : (request.path.last == "pages" ? "pages" : "board"))
        return APIResponse(status: 200, data: fixtures[name]!)
    }
}


extension BoardStoreTests {
    func testDemoFallbackSetAndClearThroughPreparedActions() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        XCTAssertTrue(store.canChangeDefaultPage)
        let selection = store.board?.activePageID
        let set = try XCTUnwrap(store.prepare(.configuration(BoardPatch(defaultPage: .set("page-weather")))))
        await store.confirm(set).value
        XCTAssertEqual(store.board?.defaultPageID, "page-weather")
        XCTAssertTrue(store.message?.contains("Simulated") == true)
        let clear = try XCTUnwrap(store.prepare(.configuration(BoardPatch(defaultPage: .clear))))
        await store.confirm(clear).value
        XCTAssertNil(store.board?.defaultPageID)
        XCTAssertEqual(store.board?.activePageID, selection)
        XCTAssertFalse(store.needsReadback)
    }
}


extension BoardStoreTests {
    func testSavePermissionMatchesLegacyAdapterAndAdvertisedDocumentCapability() async throws {
        let cases: [(String?, Bool, Bool, Bool, Bool)] = [
            ("10.1.2", false, false, true, true), ("10.1.2", false, true, true, false),
            ("11.0.0", false, false, true, false), (nil, false, false, true, false),
            ("11.0.0", true, false, true, true), ("11.0.0", true, false, false, false),
            ("10.1.2", false, false, false, false)
        ]
        for (version, advertised, dev, hasRevision, allowed) in cases {
            let service = try SessionFaultService(), store = BoardStore()
            await service.configureDocumentContract(version: version, advertised: advertised, dev: dev, hasRevision: hasRevision)
            await store.connect(service, allowCandidateWrites: true).value
            let snapshot = try await store.loadPageDocument(id: "page-selected")
            XCTAssertEqual(store.status?.version.runningVersion, version)
            XCTAssertEqual(snapshot.editingAccess.canSave, allowed)
            XCTAssertEqual(store.pageEditingAccess(context: snapshot.context).canSave, allowed)
            if !allowed {
                do {
                    _ = try await store.savePage(patch: PageSavePatch(name: "Blocked", expectedRevision: "original"), context: snapshot.context)
                    XCTFail("Store must reject before calling the permissive service")
                } catch { XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled) }
                let count = await service.pageSaveCount
                XCTAssertEqual(count, 0)
            }
        }
    }
}

private actor ReconnectIdentityTransport: APITransport {
    var installation = "original-installation"
    func replaceInstallation() { installation = "replacement-installation" }
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        let page = #"{"id":"p","name":"Page","type":"template","device_type":"panel","template":["raw"],"unknown":null}"#
        let raw: String
        switch request.path {
        case ["health"]: raw = #"{"status":"ok","service_running":true,"version":"10.1.20"}"#
        case ["discover"]: raw = "{\"product\":\"FiestaBoard\",\"version\":\"10.1.20\",\"id\":\"\(installation)\",\"name\":\"Test\"}"
        case ["auth", "status"]: raw = #"{"enabled":false,"setup_required":false,"authenticated":false,"mode":"disabled","first_run":false}"#
        case ["version"]: raw = #"{"package_version":"10.1.20","build_version":"test","running_version":"10.1.20","is_dev":false}"#
        case ["v1", "boards"]: raw = #"{"boards":[],"total":0}"#
        case ["v1", "pages"]: raw = "{\"pages\":[\(page)],\"total\":1}"
        case ["v1", "pages", "p"]: raw = page
        default: throw FiestaBoardError.invalidPath
        }
        return APIResponse(status: 200, data: Data(raw.utf8))
    }
}

extension BoardStoreTests {
    func testActualReconnectRetainsSameInstallationAndRotatesReplacedInstallationScope() async throws {
        let transport = ReconnectIdentityTransport()
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://board.test"), transport: transport)
        let store = BoardStore()
        _ = try await service.bootstrap()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "p")
        await store.reconnect(allowCandidateWrites: false).value
        let same = try await store.loadPageDocument(id: "p")
        XCTAssertEqual(original.scope, same.scope)
        await transport.replaceInstallation()
        await store.reconnect(allowCandidateWrites: false).value
        let replacement = try await store.loadPageDocument(id: "p")
        XCTAssertEqual(replacement.scope.installationID, "replacement-installation")
        XCTAssertNotEqual(original.scope.connectionID, replacement.scope.connectionID)
        do { _ = try await store.readbackPage(context: original.context); XCTFail("Old editor context") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
}


extension BoardStoreTests {
    func testReadbackRefusesScopeChangedInsideRetainedService() async throws {
        let transport = ReconnectIdentityTransport()
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://board.test"), transport: transport)
        let store = BoardStore()
        _ = try await service.bootstrap()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "p")
        await transport.replaceInstallation()
        _ = try await service.bootstrap()
        do { _ = try await store.readbackPage(context: original.context); XCTFail("Readback cannot move an editor into another scope") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
}


extension BoardStoreTests {
    func testScheduleListIsBoundToSelectedDisplayAndRejectsLateOldDisplay() async throws {
        let service = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(service).value
        await store.refreshSchedules().value
        XCTAssertEqual(store.scheduleTarget?.boardID, "board-2")
        XCTAssertEqual(store.scheduleList?.schedules.first?.boardID, "board-2")
        await service.delayNextSchedule()
        let old = store.refreshSchedules()
        await service.waitUntilBlocked()
        await store.selectBoard("board-led").value
        XCTAssertNil(store.scheduleList)
        await store.refreshSchedules().value
        await service.release()
        await old.value
        XCTAssertEqual(store.scheduleTarget?.boardID, "board-led")
        XCTAssertEqual(store.scheduleList?.schedules.first?.boardID, "board-led")
        let writes = await service.sentCount
        XCTAssertEqual(writes, 0)
    }

    func testLateScheduleFailureCannotReplaceNewerSameDisplayRead() async throws {
        let service = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(service).value
        await service.delayNextSchedule()
        let old = store.refreshSchedules()
        await service.waitUntilBlocked()
        await store.refreshSchedules().value
        XCTAssertNotNil(store.scheduleList)
        await service.failSchedule(.networkUnavailable)
        await service.release(); await old.value
        XCTAssertNotNil(store.scheduleList)
        XCTAssertNil(store.scheduleMessage)
        XCTAssertFalse(store.schedulesLoading)
    }

    func testScheduleLateResponseCannotCrossReconnectAndErrorsStayVisible() async throws {
        let service = try DelayedService(delayConnection: false)
        let store = BoardStore()
        await store.connect(service).value
        await service.delayNextSchedule()
        let old = store.refreshSchedules()
        await service.waitUntilBlocked()
        await store.reconnect(allowCandidateWrites: false).value
        await service.release()
        await old.value
        XCTAssertNil(store.scheduleList)
        XCTAssertFalse(store.schedulesLoading)
        for error in [FiestaBoardError.rejected(status: 404), .unsupportedOperation, .networkUnavailable] {
            await service.failSchedule(error)
            await store.refreshSchedules().value
            XCTAssertNil(store.scheduleList)
            XCTAssertNotNil(store.scheduleMessage)
            XCTAssertNotNil(store.status)
        }
        await service.failSchedule(nil)
        await store.refreshSchedules().value
        XCTAssertEqual(store.scheduleList?.total, 1)
        store.disconnect()
        XCTAssertNil(store.scheduleList)
        XCTAssertNil(store.scheduleTarget)
    }

    func testActionReasonsTrackDisconnectedNoDisplayBusyAndUncertainReadback() async throws {
        let store = BoardStore()
        XCTAssertEqual(store.boardActionDisabledReason, .disconnected)
        let empty = try SessionFaultService()
        await empty.setEmptyBoards()
        await store.connect(empty).value
        XCTAssertEqual(store.boardActionDisabledReason, .noDisplay)
        let service = try DelayedService(delayConnection: false)
        await store.connect(service).value
        XCTAssertNil(store.boardActionDisabledReason)
        await service.delayNextMutation()
        let command = store.confirm(try XCTUnwrap(store.prepare(.text("ONCE"))))
        await service.waitUntilBlocked()
        XCTAssertEqual(store.boardActionDisabledReason, .busy)
        await service.release(); await command.value
        let demo = try FixtureFiestaBoardService()
        await store.connect(demo).value
        await demo.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("MAYBE")))).value
        XCTAssertEqual(store.boardActionDisabledReason, .readbackRequired)
    }

    func testPageManagementUnsupportedReasonDoesNotSuggestSettingsAndDemoHasNoWebEscape() async throws {
        let store = BoardStore()
        let service = try SessionFaultService()
        await service.configureDocumentContract(version: "10.3.2", advertised: true, dev: false, hasRevision: true)
        await store.connect(service, allowCandidateWrites: false).value
        XCTAssertEqual(store.pageManagementDisabledReason, .unsupportedOperation)
        XCTAssertEqual(store.boardActionDisabledReason, .unsupportedOperation)
        await service.configureDocumentContract(version: "10.1.20", advertised: true, dev: false, hasRevision: true)
        await store.connect(service, allowCandidateWrites: false).value
        XCTAssertEqual(store.pageManagementDisabledReason, .changesDisabled)
        await store.connect(try FixtureFiestaBoardService()).value
        XCTAssertNil(store.pageManagementDisabledReason)
        XCTAssertNil(store.webEditorURL(pageID: "page-selected"))
    }
}


extension BoardStoreTests {
    func testDeletionGuidanceChecksDocumentProtocolAndRevisionBeforeOptIn() async throws {
        func page(type: String = "template", document: String? = "page-document-v1", revision: String? = "r1", edit: String? = "page-revision-v1") throws -> Page {
            var value: [String: Any] = ["id": "page-selected", "name": "Page", "type": type,
                "device_type": "flagship"]
            value["document_protocol"] = document; value["revision"] = revision; value["edit_protocol"] = edit
            return try JSONDecoder().decode(Page.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let unsupported: [(Page, ActionDisabledReason)] = [
            (try page(type: "flexible", document: "page-document-v2"), .unsupportedDocument),
            (try page(document: nil), .unsupportedDocument),
            (try page(revision: nil), .missingRevision),
            (try page(revision: "  "), .missingRevision),
            (try page(revision: String(repeating: "r", count: 257)), .missingRevision),
            (try page(edit: nil), .unsupportedRevisionProtocol),
            (try page(edit: "future-protocol"), .unsupportedRevisionProtocol)
        ]
        for optedIn in [false, true] {
            let service = try SessionFaultService(), store = BoardStore()
            await service.configureDocumentContract(version: "10.1.20", advertised: true, dev: false, hasRevision: true)
            await service.setManagementAccess(.init(canCreate: optedIn, canDelete: optedIn))
            await store.connect(service, allowCandidateWrites: optedIn).value
            XCTAssertEqual(store.pageManagementDisabledReason, optedIn ? nil : .changesDisabled,
                "Library-wide creation guidance remains independent of the current page")
            for (page, expected) in unsupported {
                let reason = store.pageDeletionDisabledReason(for: page)
                XCTAssertEqual(reason, expected)
                XCTAssertFalse(reason?.message.contains("Enable changes") == true)
            }
            XCTAssertEqual(store.pageDeletionDisabledReason(for: try page()), optedIn ? nil : .changesDisabled)
        }
    }
}

extension BoardStoreTests {
    func testFlexiblePreviewAndSaveAccessStayBoundToDocumentTargetAndSession() async throws {
        for transition in ["document", "board", "disconnect"] {
            let service = try DelayedService(delayConnection: false), store = BoardStore()
            await service.useFlexibleDocument()
            await store.connect(service).value
            let original = try await store.loadPageDocument(id: "page-selected")
            XCTAssertTrue(original.editingAccess.canSave)
            let target = try BoardTarget(deployment: service.deployment, boardID: "board-led")
            let body = Data(#"{"page":{"name":"Flexible","type":"flexible","blocks":[{"id":"text","kind":"text","text":"Text"}]},"board_id":"board-led"}"#.utf8)
            let result = try await store.previewFlexiblePage(requestData: body, context: original.context, target: target)
            XCTAssertEqual(result.lines, ["Text"])
            await service.delayNextPreview()
            let pending = Task { try await store.previewFlexiblePage(requestData: body, context: original.context, target: target) }
            await service.waitUntilBlocked()
            switch transition {
            case "document": _ = try await store.loadPageDocument(id: original.id)
            case "board": await store.selectBoard("board-led").value
            default: store.disconnect()
            }
            await service.release()
            do { _ = try await pending.value; XCTFail("Stale preview cannot be adopted") }
            catch { XCTAssertEqual(error as? FiestaBoardError, transition == "document" ? .stalePageContext : .staleSession) }
        }
    }
}

extension BoardStoreTests {
    func testTemplateContextCannotAcquireFlexiblePreviewPermission() async throws {
        let service = try DelayedService(delayConnection: false), store = BoardStore()
        await store.connect(service).value
        let original = try await store.loadPageDocument(id: "page-selected")
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-led")
        do {
            _ = try await store.previewFlexiblePage(requestData: Data("{}".utf8), context: original.context, target: target)
            XCTFail("A template context does not advertise the flexible endpoint")
        } catch { XCTAssertEqual(error as? FiestaBoardError, .previewUnsupported) }
    }
}
