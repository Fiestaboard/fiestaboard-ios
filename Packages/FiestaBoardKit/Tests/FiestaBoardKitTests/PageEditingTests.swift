import XCTest
@testable import FiestaBoardKit

@MainActor final class PageEditingTests: XCTestCase {
    func testPatchOnlyEncodesChangedFieldsAndOriginalRevision() throws {
        let patch = PageSavePatch(name: "Café 👨‍👩‍👧‍👦", expectedRevision: "original")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["name", "expected_revision"])
        XCTAssertEqual(object["name"] as? String, "Café 👨‍👩‍👧‍👦")
        XCTAssertThrowsError(try PageSavePatch(expectedRevision: "original").validate())
        XCTAssertThrowsError(try PageSavePatch(name: "x", expectedRevision: "").validate())
    }
    func testReceiptPreservesExactNestedPageBytes() throws {
        let page = #"{"id":"p","name":"e\u0301","type":"template","device_type":"flagship","revision":"r2","edit_protocol":"page-revision-v1","unknown":9007199254740993}"#
        let raw = Data("{\"page\": \(page), \"incompatible_references\":[]}".utf8)
        let receipt = try PageSaveReceipt(rawData: raw, expectedPageID: "p")
        XCTAssertEqual(receipt.rawData, raw)
        XCTAssertEqual(receipt.pageData, Data(page.utf8))
    }
    func testDemoPageSavePersistsAndRotatesRevisionWithoutChangingBoard() async throws {
        let demo = try DemoFiestaBoardService()
        _ = try await demo.connect(allowCandidateWrites: true)
        let before = try await demo.page(id: "page-selected")
        let target = try BoardTarget(deployment: demo.deployment, boardID: "board-2")
        let board = try await demo.board(target)
        let receipt = try await demo.savePage(id: before.id, patch: PageSavePatch(name: "é 🛰️", expectedRevision: try XCTUnwrap(before.revision)))
        let after = try JSONDecoder().decode(Page.self, from: receipt.pageData)
        XCTAssertEqual(after.name, "é 🛰️")
        XCTAssertNotEqual(after.revision, before.revision)
        let read = try await demo.page(id: before.id)
        XCTAssertEqual(read.name, after.name)
        let laterBoard = try await demo.board(target)
        XCTAssertEqual(laterBoard.characters, board.characters)
        do { _ = try await demo.savePage(id: before.id, patch: PageSavePatch(name: "stale", expectedRevision: before.revision!)); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageConflict) }
    }
}

private actor PageFixtureTransport: APITransport {
    var requests: [APIRequest] = []
    let version: String?
    let isDev: Bool
    let protocolName: String?
    let documentProtocol: String?
    let revision: String?
    var saveOutcome: FiestaBoardError?
    let saveStatus: Int
    let previewReply: Data
    private var delayRead = false
    private var readGate: CheckedContinuation<Void, Never>?
    private var readObservers: [CheckedContinuation<Void, Never>] = []
    func delayNextRead() { delayRead = true }
    func waitForRead() async {
        if readGate != nil { return }
        await withCheckedContinuation { readObservers.append($0) }
    }
    func releaseRead() { readGate?.resume(); readGate = nil }
    init(version: String? = "10.1.2", isDev: Bool = false, documentProtocol: String? = nil, protocolName: String? = "page-revision-v1", revision: String? = "original", saveOutcome: FiestaBoardError? = nil, saveStatus: Int = 200) {
        self.version = version; self.isDev = isDev; self.documentProtocol = documentProtocol; self.protocolName = protocolName; self.revision = revision; self.saveOutcome = saveOutcome; self.saveStatus = saveStatus
        previewReply = Data(#"{"rendered":"🛰️","lines":["🛰️"],"line_count":1,"charset":"rich_future","charset_issues":[{"row":0,"col":0,"token":{"x":9007199254740993},"reason":"icon","fallback":{}}],"layers":[{"future":true}],"canvas_issues":[{"future":"warning"}]}"#.utf8)
    }
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        if request.path == ["version"] {
            var body: [String: Any] = ["package_version": version ?? "package-only", "build_version": "fixture", "is_dev": isDev]
            body["running_version"] = version
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: body))
        }
        if request.path == ["v1", "boards"] { return APIResponse(status: 200, data: fixture("boards")) }
        if request.path == ["templates", "validate"] { return APIResponse(status: 200, data: Data(#"{"valid":false,"errors":[{"line":1,"column":2,"message":"bad expression"}]}"#.utf8)) }
        if request.path == ["templates", "render"] { return APIResponse(status: 200, data: previewReply) }
        var page: [String: Any] = ["id": "p", "name": "Original", "type": "template", "device_type": "panel", "grid_rows": 3, "grid_cols": 15, "template": ["a", "b", "c"]]
        page["revision"] = revision; page["edit_protocol"] = protocolName; page["document_protocol"] = documentProtocol
        if request.method == .put {
            if let saveOutcome { throw saveOutcome }
            let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
            page["name"] = body["name"] ?? page["name"]; page["template"] = body["template"] ?? page["template"]
            page["revision"] = "updated"
            return APIResponse(status: saveStatus, data: try JSONSerialization.data(withJSONObject: ["page": page, "incompatible_references": ["board-other"]]))
        }
        let response = APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: page))
        if delayRead {
            delayRead = false
            await withCheckedContinuation { readGate = $0; readObservers.forEach { $0.resume() }; readObservers = [] }
        }
        return response
    }
}

extension PageEditingTests {
    func testPageProtocolAndOptInAreIndependentOfBoardVersionGate() async throws {
        let deployment = try DeploymentURL("https://fixture.test")
        for (protocolName, revision, optedIn) in [(nil, "original", true), ("unknown", "original", true), ("page-revision-v1", nil, true), ("page-revision-v1", "", true), ("page-revision-v1", "original", false)] {
            let transport = PageFixtureTransport(protocolName: protocolName, revision: revision)
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
            _ = try await service.connect(allowCandidateWrites: optedIn)
            _ = try await service.pageDocumentData(id: "p")
            do { _ = try await service.savePage(id: "p", patch: PageSavePatch(name: "Unsafe", expectedRevision: "original")); XCTFail("Gate must reject") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled) }
            let requests = await transport.requests
            XCTAssertFalse(requests.contains { $0.method == .put })
        }
        let transport = PageFixtureTransport()
        let gated = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let connection = try await gated.connect(allowCandidateWrites: true)
        XCTAssertEqual(connection.access, .readOnly, "10.1.2 board controls stay disabled")
        _ = try await gated.pageDocumentData(id: "p")
        let patch = PageSavePatch(name: "é 🛰️", expectedRevision: "recovered-original")
        let receipt = try await gated.savePage(id: "p", patch: patch)
        XCTAssertEqual(receipt.incompatibleReferenceCount, 1)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.path, ["v1", "pages", "p"])
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as! [String: String]
        XCTAssertEqual(body, ["name": "é 🛰️", "expected_revision": "recovered-original"])
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        do { _ = try await gated.sendText("unsafe", to: target); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .writesDisabled) }
    }
    func testConflictAndUnknownSavesStayLockedUntilExplicitPageRead() async throws {
        for outcome in [FiestaBoardError.pageConflict, .unknownMutationOutcome] {
            let transport = PageFixtureTransport(saveOutcome: outcome)
            let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
            _ = try await service.connect(allowCandidateWrites: true); _ = try await service.pageDocumentData(id: "p")
            let patch = PageSavePatch(template: ["a", "b", "c"], expectedRevision: "original")
            do { _ = try await service.savePage(id: "p", patch: patch); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, outcome) }
            do { _ = try await service.savePage(id: "p", patch: patch); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
            let requests = await transport.requests
            XCTAssertEqual(requests.filter { $0.method == .put }.count, 1)
        }
    }
    func testPreviewPreservesAllRequestBytesAndRejectsUnknownFieldsAndTargets() async throws {
        let deployment = try DeploymentURL("https://fixture.test")
        let transport = PageFixtureTransport()
        let adapter = LiveFiestaBoardService(deployment: deployment, transport: transport)
        _ = try await adapter.connect(allowCandidateWrites: false)
        let target = try BoardTarget(deployment: deployment, boardID: "board-2")
        let raw = Data(#"{ "template":["e\u0301"],"board_id":"board-2","device_type":"panel","grid_rows":3,"grid_cols":15,"line_metadata":[{"future":9007199254740993}],"canvases":[{"preserved":"🛰️"}] }"#.utf8)
        let result = try await adapter.previewPage(requestData: raw, target: target)
        XCTAssertEqual(result.lines, ["🛰️"]); XCTAssertEqual(result.charsetIssueCount, 1)
        XCTAssertEqual(result.canvasIssueCount, 1); XCTAssertTrue(result.hasLayers)
        let sent = await transport.requests
        XCTAssertEqual(sent.last?.body, raw)
        XCTAssertEqual(sent.last?.path, ["templates", "render"])
        let previewReply = transport.previewReply
        XCTAssertEqual(result.rawData, previewReply)
        let validate = try await adapter.validatePage(requestData: Data(#"{"template":["{{"],"board_id":"board-2"}"#.utf8), target: target)
        XCTAssertFalse(validate.valid); XCTAssertEqual(validate.errors.first?.column, 2)
        for invalid in [#"{"template":[],"board_id":"different"}"#, #"{"template":[],"board_id":"board-2","override_silence":true}"#, #"{"template":[],"board_id":"board-2","board_id":"board-2"}"#] {
            do { _ = try await adapter.previewPage(requestData: Data(invalid.utf8), target: target); XCTFail() } catch {}
        }
        let after = await transport.requests
        XCTAssertEqual(after.filter { $0.method == .post }.count, 2)
        XCTAssertFalse(after.contains { $0.path.contains("live") })
    }
    func testUnknownPreviewVersionRefusesBeforeRequest() async throws {
        let transport = PageFixtureTransport(version: "11.0.0")
        let deployment = try DeploymentURL("https://fixture.test"), service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true)
        do { _ = try await service.previewPage(requestData: Data(#"{"template":[],"board_id":"board-2"}"#.utf8), target: BoardTarget(deployment: deployment, boardID: "board-2")); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .previewUnsupported) }
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.method == .post })
    }
    func testReceiptSlicingEscapedKeysNestedStringsAndDuplicateAmbiguity() throws {
        let page = #"{"id":"p","name":"} , \"page\": [x] 🛰️","type":"template","device_type":"panel","revision":"r","edit_protocol":"page-revision-v1","unknown":[{"n":1.2300e+42,"nested":["\\",{}]}]}"#
        let raw = Data("{\"unrelated\":{\"page\":0},\"p\\u0061ge\": \(page),\"incompatible_references\":[]}".utf8)
        XCTAssertEqual(try PageSaveReceipt(rawData: raw, expectedPageID: "p").pageData, Data(page.utf8))
        let duplicate = Data("{\"page\":\(page),\"p\\u0061ge\":\(page),\"incompatible_references\":[]}".utf8)
        XCTAssertThrowsError(try PageSaveReceipt(rawData: duplicate, expectedPageID: "p"))
    }
}

extension PageEditingTests {
    func testBackendContractFixtureDecodesWithoutDroppingServerMetadata() throws {
        let members = try RawJSONObject.members(fixture("page-revision-v1"))
        let read = try JSONDecoder().decode(Page.self, from: XCTUnwrap(members["read"]))
        XCTAssertEqual(read.editProtocol, "page-revision-v1")
        XCTAssertEqual(read.gridRows, 3); XCTAssertEqual(read.gridCols, 15)
        let save = try PageSaveReceipt(rawData: XCTUnwrap(members["save"]), expectedPageID: read.id)
        let page = try JSONDecoder().decode(Page.self, from: save.pageData)
        XCTAssertNotEqual(read.revision, page.revision)
        let fields = try RawJSONObject.members(save.pageData)
        XCTAssertEqual(fields["line_metadata"], Data(#"[{"alignment": "right", "wrap": true}]"#.utf8))
        let request = try JSONSerialization.jsonObject(with: XCTUnwrap(members["request"])) as! [String: Any]
        XCTAssertEqual(Set(request.keys), ["template", "expected_revision"])
    }
}

extension PageEditingTests {
    func testRawReceiptAllowsUnknownExtremeNumbersAndDistinctUnicodeKeys() throws {
        let page = #"{"id":"p","name":"x","type":"template","device_type":"panel","revision":"r","edit_protocol":"page-revision-v1","future":1e9999}"#
        let raw = Data("{\"é\":1,\"e\\u0301\":2,\"page\":\(page),\"incompatible_references\":[]}".utf8)
        XCTAssertEqual(try PageSaveReceipt(rawData: raw, expectedPageID: "p").pageData, Data(page.utf8))
    }
}

extension PageEditingTests {
    func testEvaluationTransportFailureHasNoMutationUncertaintyOrReplay() async throws {
        let log = RequestLog(), deployment = try DeploymentURL("https://fixture.test")
        FixtureURLProtocol.handler = { request in log.append(request); throw URLError(.networkConnectionLost) }
        let transport = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self])
        for endpoint in ["validate", "render"] {
            let request = APIRequest(.post, path: ["templates", endpoint], body: Data("{}".utf8))
            XCTAssertFalse(request.isMutation)
            do { _ = try await transport.send(request); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, .networkUnavailable) }
        }
        XCTAssertEqual(log.requests.count, 2)
        XCTAssertTrue(APIRequest(.post, path: ["templates", "render", "live"]).isMutation)
    }
}

extension PageEditingTests {
    func testAsynchronousSaveStatusCannotAcknowledgeStorage() async throws {
        let transport = PageFixtureTransport(saveStatus: 202)
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true)
        _ = try await service.pageDocumentData(id: "p")
        do { _ = try await service.savePage(id: "p", patch: PageSavePatch(name: "Maybe", expectedRevision: "original")); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
    }
}

extension PageEditingTests {
    func testPageReadStartedBeforeSaveCannotClearUncertainWriteLock() async throws {
        let transport = PageFixtureTransport(saveOutcome: .unknownMutationOutcome)
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true)
        _ = try await service.pageDocumentData(id: "p")
        await transport.delayNextRead()
        let read = Task { try await service.pageDocumentData(id: "p") }
        await transport.waitForRead()
        let patch = PageSavePatch(name: "Maybe", expectedRevision: "original")
        do { _ = try await service.savePage(id: "p", patch: patch); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        await transport.releaseRead()
        do { _ = try await read.value; XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .stalePageContext) }
        do { _ = try await service.savePage(id: "p", patch: patch); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
    }
}


extension PageEditingTests {
    func testTemplateEvaluationUsesAuditedStableCompatibilityRange() async throws {
        let cases: [(String?, Bool, Bool)] = [
            ("10.0.0", false, true), ("10.1.7", false, true), ("10.1.8", false, true),
            ("10.1.20", false, true), ("10.3.2", false, true),
            ("9.9.9", false, false), ("10.3.3", false, false), ("11.0.0", false, false),
            ("10.3.2", true, false), ("10.3.2-dev", false, false), ("10.03.2", false, false),
            ("10.3", false, false), ("999999999999999999999.3.2", false, false), (nil, false, false)
        ]
        for (version, dev, permits) in cases {
            let transport = PageFixtureTransport(version: version, isDev: dev)
            let deployment = try DeploymentURL("https://fixture.test")
            let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
            let status = try await service.connect(allowCandidateWrites: true)
            if version == "10.1.7" { XCTAssertEqual(status.access, .readOnly, "Preview support never widens board controls") }
            let target = try BoardTarget(deployment: deployment, boardID: "board-2")
            let request = Data(#"{"template":["🛰️"],"board_id":"board-2"}"#.utf8)
            if permits {
                _ = try await service.validatePage(requestData: request, target: target)
                let preview = try await service.previewPage(requestData: request, target: target)
                XCTAssertEqual(preview.lines, ["🛰️"])
            } else {
                do { _ = try await service.validatePage(requestData: request, target: target); XCTFail() }
                catch { XCTAssertEqual(error as? FiestaBoardError, .previewUnsupported) }
                do { _ = try await service.previewPage(requestData: request, target: target); XCTFail() }
                catch { XCTAssertEqual(error as? FiestaBoardError, .previewUnsupported) }
            }
            let sent = await transport.requests
            XCTAssertEqual(sent.filter { $0.method == .post }.count, permits ? 2 : 0)
            XCTAssertEqual(sent.filter { $0.method == .post }.map(\.path), permits ? [["templates", "validate"], ["templates", "render"]] : [])
            XCTAssertFalse(sent.contains { $0.method == .put || $0.method == .delete || $0.path.contains("live") })
        }
    }
}


extension PageEditingTests {
    func testLegacyDocumentAbsenceRequiresAuditedAdapterWhileAdvertisedProtocolSurvivesNewVersion() async throws {
        let cases: [(String?, Bool, String?, Bool)] = [
            ("10.1.2", false, nil, true), ("10.1.2", true, nil, false),
            (nil, false, nil, false), ("11.0.0", false, nil, false),
            ("11.0.0", false, "page-document-v1", true),
            ("11.0.0", false, "page-document-v99", false)
        ]
        for (version, dev, documentProtocol, allowed) in cases {
            let transport = PageFixtureTransport(version: version, isDev: dev, documentProtocol: documentProtocol)
            let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
            _ = try await service.connect(allowCandidateWrites: true)
            _ = try await service.pageDocumentData(id: "p")
            do {
                _ = try await service.savePage(id: "p", patch: PageSavePatch(name: "Changed", expectedRevision: "original"))
                XCTAssertTrue(allowed, "Absent protocol cannot grant permission on an unaudited server")
            } catch {
                XCTAssertFalse(allowed)
                XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled)
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.filter { $0.method == .put }.count, allowed ? 1 : 0)
        }
    }
}
