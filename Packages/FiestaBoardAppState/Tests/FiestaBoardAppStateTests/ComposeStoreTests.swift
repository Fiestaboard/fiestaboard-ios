import XCTest
@testable import FiestaBoardKit
@testable import FiestaBoardAppState

private actor ComposeStoreService: FiestaBoardService, ComposeServicing, ComposePrincipalProviding, ComposeCatalogReading {
    nonisolated let deployment: DeploymentURL
    nonisolated let isDemo = false
    let base: FixtureFiestaBoardService
    let proof: ComposePrincipalProof
    private var details: [String: BoardDetail]
    private var active = true
    var sends: [ComposeRequest] = []
    var creates: [ComposeRequest] = []
    var polls = 0
    var catalogReads = 0
    var state = ComposeReceipt.State.sent
    var retrySeconds: Int?
    var readbackFails = false
    var createFails = false
    private var delayed = false
    private var sendGate: CheckedContinuation<Void, Never>?
    private var sendObserver: CheckedContinuation<Void, Never>?
    init() throws {
        deployment = try DeploymentURL("https://compose-store.test")
        base = try FixtureFiestaBoardService(deploymentString: deployment.description)
        proof = .init(deployment: deployment, installationID: "unit-install", principalID: "unit-user", connectionID: UUID(), verifiedOnline: true)
        var root = URL(fileURLWithPath: #filePath); for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/compose-authenticated.json"))
        let corpus = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        details = [:]
        for record in corpus["records"] as! [[String: Any]] where ["primary-capability", "secondary-capability"].contains(record["case"] as! String) {
            let detail = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: record["response"]!))
            details[detail.summary.id] = detail
        }
    }
    func request(target: BoardTarget, preparedAt: Date = Date(), text: String = "EXACT ORIGINAL") -> ComposeRequest {
        ComposeRequest(principal: proof, target: target, preparedAt: preparedAt, text: text, lineMetadata: [.init(alignment: "center", wrap: true)],
            geometry: details[target.boardID]!.summary.deviceType == "note" ? .note : .flagship, duration: .minutes(120), silence: .hold)
    }
    func configure(state: ComposeReceipt.State = .sent, retry: Int? = nil, readbackFails: Bool = false, createFails: Bool = false) {
        self.state = state; retrySeconds = retry; self.readbackFails = readbackFails; self.createFails = createFails
    }
    func blockSend() { delayed = true }
    func waitForSend() async { if sendGate == nil { await withCheckedContinuation { sendObserver = $0 } } }
    func releaseSend() { sendGate?.resume(); sendGate = nil; delayed = false }
    func composePrincipal() -> ComposePrincipalProof? { active ? proof : nil }
    func rememberedComposePrincipal(installationID: String) -> ComposePrincipalProof? { nil }
    func sendCompose(_ request: ComposeRequest) async throws -> ComposeReceipt {
        sends.append(request)
        if delayed { await withCheckedContinuation { sendGate = $0; sendObserver?.resume(); sendObserver = nil } }
        return try receipt(request)
    }
    func composeOutcome(_ request: ComposeRequest) async throws -> ComposeReceipt { polls += 1; return try receipt(request, read: true) }
    func previewCompose(_ request: ComposeRequest) async throws -> TemplatePreviewResult {
        let lines = request.text.components(separatedBy: "\n")
        return try TemplatePreviewResult(rawData: JSONSerialization.data(withJSONObject: ["rendered": request.text, "lines": lines, "line_count": lines.count, "charset": "ascii"]))
    }
    func composeTemplateCatalog(_ request: ComposeRequest) async throws -> TemplateCatalog {
        catalogReads += 1
        if delayed { await withCheckedContinuation { sendGate = $0; sendObserver?.resume(); sendObserver = nil } }
        return TemplateCatalog(plugins: [], colors: [], formatting: [], isServerCatalog: true)
    }
    func composeFormulaFunctions(_ request: ComposeRequest) async throws -> FunctionCatalog {
        catalogReads += 1; return FunctionCatalog(functions: [])
    }
    func validateComposeFormula(_ expression: String, request: ComposeRequest) async throws -> FormulaCheck {
        catalogReads += 1; return FormulaCheck(valid: true, messages: [])
    }
    func saveComposePage(name: String, request: ComposeRequest) async throws -> ComposePageReceipt {
        creates.append(request)
        if createFails { throw FiestaBoardError.unknownMutationOutcome }
        var object = try JSONSerialization.jsonObject(with: request.pageEncoded(name: name)) as! [String: Any]
        object["id"] = "created-compose"; object["document_protocol"] = "page-document-v1"
        object["edit_protocol"] = "page-revision-v1"; object["revision"] = "created-r1"
        return try ComposePageReceipt(pageData: JSONSerialization.data(withJSONObject: object), name: name, request: request)
    }
    private func receipt(_ request: ComposeRequest, read: Bool = false) throws -> ComposeReceipt {
        let requestObject = try JSONSerialization.jsonObject(with: request.encoded()) as! [String: Any]
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let accepted = state == .sent || state == .unchanged
        let sent: Any = state == .unknown || state == .partial ? NSNull() : (state == .sent)
        let code: Int
        if read { code = 200 }
        else {
            switch state {
            case .sent, .unchanged: code = 200
            case .held, .preparing, .dispatching: code = 202
            case .unknown: code = 503
            case .notSent: code = retrySeconds == nil ? 502 : 429
            case .partial: code = 502
            default: code = 409
            }
        }
        let start = Date()
        var body: [String: Any] = ["protocol": "compose-intent-v1", "request_id": request.requestID.uuidString,
            "board_id": request.target.boardID, "status": state.rawValue, "sent": sent,
            "duration": requestObject["duration"]!, "failed_regions": []]
        if accepted {
            body["started_at"] = formatter.string(from: start)
            body["expires_at"] = formatter.string(from: start.addingTimeInterval(7200))
        } else { body["started_at"] = NSNull(); body["expires_at"] = NSNull() }
        if state == .held { body["held_until"] = formatter.string(from: start.addingTimeInterval(3600)) }
        else { body["held_until"] = NSNull() }
        if let retrySeconds { body["retry_after_seconds"] = retrySeconds }
        else { body["retry_after_seconds"] = NSNull() }
        let envelope: [String: Any] = code >= 400 ? ["detail": body] : body
        let encoded = try JSONSerialization.data(withJSONObject: envelope)
        return try ComposeReceipt(rawData: encoded, httpStatus: code,
            expectedBoardID: request.target.boardID, expectedRequestID: request.requestID, expectedDuration: request.duration, isOutcomeRead: read)
    }
    func board(_ target: BoardTarget) throws -> BoardDetail {
        if readbackFails && (!sends.isEmpty || !creates.isEmpty) { throw FiestaBoardError.networkUnavailable }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(details[target.boardID]!)) as! [String: Any]
        if let last = sends.last, last.target == target, state == .sent || state == .unchanged {
            object["compose_receipt"] = ["request_id": last.requestID.uuidString, "status": state.rawValue, "sent": state == .sent]
        }
        return try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func bootstrap() throws -> BootstrapSnapshot { try .init(deployment: deployment, health: .init(status: "ok", serviceRunning: true, version: "11.0.0-alpha.3"), identity: .init(product: "FiestaBoard", version: "11.0.0-alpha.3", installationID: "unit-install", name: "Unit fixture"), auth: authStatus()) }
    func authStatus() -> AuthStatus { .init(enabled: true, setupRequired: false, authenticated: active, username: "unit-user", authKind: "mobile") }
    func connect(allowCandidateWrites: Bool) -> ConnectionStatus { .init(version: .init(packageVersion: "11.0.0-alpha.3", buildVersion: "unit", runningVersion: "11.0.0-alpha.3", isDev: true), access: .readOnly, isDemo: false, sessionPersistence: "Unit fixture") }
    func disconnect() { active = false }
    func logout() { active = false }
    func boards() -> [BoardSummary] { details.values.map(\.summary).sorted { $0.isPrimary && !$1.isPrimary } }
    func pages() async throws -> [Page] { try await base.pages() }
    func page(id: String) async throws -> Page { try await base.page(id: id) }
    func pageDocumentData(id: String) async throws -> Data { try await base.pageDocumentData(id: id) }
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt { throw FiestaBoardError.writesDisabled }
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult { throw FiestaBoardError.unsupportedOperation }
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult { throw FiestaBoardError.unsupportedOperation }
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt { throw FiestaBoardError.writesDisabled }
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt { throw FiestaBoardError.writesDisabled }
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult { throw FiestaBoardError.writesDisabled }
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult { throw FiestaBoardError.writesDisabled }
    func login(username: String, password: String) throws -> AuthStatus { authStatus() }
}

@MainActor final class ComposeStoreTests: XCTestCase {
    private func connected(now: @escaping @MainActor () -> Date = { Date() }) async throws -> (BoardStore, ComposeStoreService, ComposeRequest) {
        let service = try ComposeStoreService(), store = BoardStore(now: now)
        await store.connect(service, allowCandidateWrites: true).value
        let request = await service.request(target: try BoardTarget(deployment: service.deployment, boardID: XCTUnwrap(store.selectedBoardID)), preparedAt: now())
        return (store, service, request)
    }
    func testCapturedComposeUsesCommonBarrierAndExactOneShotTargetReadback() async throws {
        let (store, service, request) = try await connected()
        XCTAssertFalse(store.canWrite); XCTAssertTrue(store.canPerformCompose)
        let action = try XCTUnwrap(store.prepare(.compose(request)))
        await service.blockSend(); let sending = store.confirm(action); await service.waitForSend()
        XCTAssertTrue(store.commandBusy); XCTAssertTrue(store.needsReadback)
        XCTAssertNil(store.prepare(.compose(request)))
        await service.releaseSend(); await sending.value
        XCTAssertEqual(store.composeOperation?.receipt.state, .sent)
        XCTAssertTrue(store.composeOperation?.acceptedReadback == true)
        await store.confirm(action).value
        let sends = await service.sends
        XCTAssertEqual(sends.count, 1); XCTAssertEqual(sends[0].text, "EXACT ORIGINAL")
    }
    func testOfflineAndChangedTargetCannotDispatchCapturedCompose() async throws {
        let (store, service, request) = try await connected()
        store.networkAvailable = false; XCTAssertNil(store.prepare(.compose(request))); store.networkAvailable = true
        await store.probeReachability().value
        let action = try XCTUnwrap(store.prepare(.compose(request)))
        let other = try XCTUnwrap(store.boards.first { $0.id != request.target.boardID })
        await store.selectBoard(other.id).value; await store.confirm(action).value
        XCTAssertNil(store.prepare(.compose(request)))
        let sends = await service.sends; XCTAssertTrue(sends.isEmpty)
    }
    func testFailedReadbackRetainsReceiptAndHubProbeCannotClearMutationBarrier() async throws {
        let (store, service, request) = try await connected()
        await service.configure(readbackFails: true)
        await store.confirm(try XCTUnwrap(store.prepare(.compose(request)))).value
        XCTAssertEqual(store.composeOperation?.receipt.state, .sent); XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.composeOperation?.acceptedReadback ?? true)
        await service.configure(); await store.probeReachability().value
        XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canPerformCompose)
        await store.refresh().value
        XCTAssertFalse(store.needsReadback); XCTAssertTrue(store.composeOperation?.acceptedReadback == true)
    }
    func testRateLimitedTypedReceiptKeepsRetryAfterAcrossSuccessfulReadback() async throws {
        var now = Date()
        let (store, service, request) = try await connected(now: { now })
        await service.configure(state: .notSent, retry: 9)
        await store.confirm(try XCTUnwrap(store.prepare(.compose(request)))).value
        XCTAssertEqual(store.composeOperation?.receipt.state, .notSent)
        XCTAssertEqual(store.reachabilityRetryAt, now.addingTimeInterval(9)); XCTAssertFalse(store.canPerformCompose)
        now = now.addingTimeInterval(10); XCTAssertTrue(store.canPerformCompose)
    }
    func testUnknownReceiptIsImmutableAndOutcomeCheckNeverReplays() async throws {
        let (store, service, request) = try await connected()
        await service.configure(state: .unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.compose(request)))).value
        let original = try XCTUnwrap(store.composeOperation)
        XCTAssertEqual(original.receipt.state, .unknown); XCTAssertFalse(original.acceptedReadback)
        await service.configure(state: .sent); await store.checkComposeOutcome().value
        XCTAssertEqual(original.receipt.state, .unknown)
        XCTAssertEqual(store.composeOperation?.receipt.state, .sent)
        let sends = await service.sends, polls = await service.polls
        XCTAssertEqual(sends.count, 1); XCTAssertEqual(polls, 1)
    }
    func testSaveAsPageDoesNotSelectOrSendAndKeepsGenericWritesDisabled() async throws {
        let (store, service, request) = try await connected()
        let selected = store.selectedBoardID, active = store.board?.activePageID
        await store.confirm(try XCTUnwrap(store.prepare(.composePage(name: "Saved draft", request: request)))).value
        XCTAssertEqual(store.composePageOperation?.receipt.page.name, "Saved draft")
        XCTAssertEqual(store.selectedBoardID, selected); XCTAssertEqual(store.board?.activePageID, active)
        XCTAssertTrue(store.pages.contains { $0.id == "created-compose" }); XCTAssertFalse(store.canWrite)
        let sends = await service.sends, creates = await service.creates
        XCTAssertTrue(sends.isEmpty); XCTAssertEqual(creates.count, 1)
    }
    func testUncertainPageCreateBlocksLibraryWithoutReplayUntilExplicitReview() async throws {
        let (store, service, request) = try await connected()
        await service.configure(createFails: true)
        let action = try XCTUnwrap(store.prepare(.composePage(name: "Uncertain", request: request)))
        await store.confirm(action).value
        XCTAssertTrue(store.pageLibrary?.needsReview == true)
        XCTAssertNil(store.prepare(.compose(request)))
        await store.confirm(action).value
        let creates = await service.creates; XCTAssertEqual(creates.count, 1)
        await service.configure(); await store.reviewPageLibrary(); store.acknowledgePageLibraryReview()
        await store.refresh().value
        XCTAssertFalse(store.pageLibrary?.needsReview ?? true)
    }
}


extension ComposeStoreTests {
    func testComposeCatalogReadsRejectOfflineAndChangedCapturedTargetWithoutCallingService() async throws {
        let (store, service, request) = try await connected()
        store.networkAvailable = false
        do { _ = try await store.composeTemplateCatalog(request); XCTFail("Offline catalog cannot read") } catch {}
        store.networkAvailable = true; await store.probeReachability().value
        let other = try XCTUnwrap(store.boards.first { $0.id != request.target.boardID })
        await store.selectBoard(other.id).value
        do { _ = try await store.composeFormulaFunctions(request); XCTFail("Old target cannot read functions") } catch {}
        do { _ = try await store.validateComposeFormula("1+2", request: request); XCTFail("Old target cannot validate") } catch {}
        let reads = await service.catalogReads; XCTAssertEqual(reads, 0)
    }
    func testDelayedComposeCatalogCannotPublishAfterSelectedTargetChanges() async throws {
        let (store, service, request) = try await connected()
        await service.blockSend()
        let reading = Task { try await store.composeTemplateCatalog(request) }
        await service.waitForSend()
        let other = try XCTUnwrap(store.boards.first { $0.id != request.target.boardID })
        await store.selectBoard(other.id).value
        await service.releaseSend()
        do { _ = try await reading.value; XCTFail("Late catalog belongs to old target") } catch {}
        let reads = await service.catalogReads; XCTAssertEqual(reads, 1)
        let current = await service.request(target: try BoardTarget(deployment: service.deployment, boardID: other.id), text: "")
        let functions = try await store.composeFormulaFunctions(current)
        let check = try await store.validateComposeFormula("1+2", request: current)
        XCTAssertTrue(functions.names.isEmpty); XCTAssertTrue(check.valid)
    }
}
