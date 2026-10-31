import XCTest
@testable import FiestaBoardKit

@MainActor final class PageManagementTests: XCTestCase {
    func testTypedCreationEncodesOnlyAuthorFieldsAndPreservesFullBareReceipt() async throws {
        let t = ManagementTransport()
        let s = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: t)
        _ = try await s.connect(allowCandidateWrites: true)
        let input = PageCreationInput(name: "LED 🌈", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"])
        let context = try await s.preparePageCreation(input)
        let receipt = try await s.createPage(context: context)
        XCTAssertEqual(receipt.page.id, "created")
        XCTAssertEqual(receipt.pageData, ManagementTransport.document)
        let requests = await t.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, ["v1", "pages"])
        let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
        XCTAssertEqual(Set(body.keys), ["name", "type", "device_type", "grid_rows", "grid_cols", "template"])
        XCTAssertEqual(body["grid_rows"] as? Int, 8)
        do { _ = try await s.createPage(context: context); XCTFail("Consumed context") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
    }
    func testDeleteUsesOriginalRevisionAndConsumesAllSamePageContexts() async throws {
        let t = ManagementTransport(); let s = try service(t)
        _ = try await s.connect(allowCandidateWrites: true)
        let a = try await s.readPageForDeletion(id: "created")
        let b = try await s.readPageForDeletion(id: "created")
        XCTAssertEqual(a.pageData, ManagementTransport.document)
        let receipt = try await s.deletePage(context: a)
        XCTAssertEqual(receipt.id, "created")
        XCTAssertFalse(receipt.defaultPageCreated)
        let last = await t.lastRequest()
        let request = try XCTUnwrap(last)
        XCTAssertEqual(request.method, .delete)
        XCTAssertEqual(request.queryItems, [.init(name: "expected_revision", value: "original")])
        do { _ = try await s.deletePage(context: b); XCTFail() }
        catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
    }
    private func service(_ t: ManagementTransport) throws -> LiveFiestaBoardService {
        LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: t)
    }
    func testReaderOnlyFamiliesAndUnknownProtocolsCannotMutate() async throws {
        let original = String(decoding: ManagementTransport.document, as: UTF8.self)
        let documents = [
            #"{"id":"created","name":"Flexible","type":"flexible","edit_protocol":"page-revision-v1","document_protocol":"page-document-v2","revision":"original"}"#,
            #"{"id":"created","name":"Future","type":"future-family","edit_protocol":"page-revision-v1","document_protocol":"page-document-v99","revision":"original"}"#,
            original.replacingOccurrences(of: "page-document-v1", with: "page-document-v99"),
            original.replacingOccurrences(of: #""document_protocol":"page-document-v1""#, with: #""document_protocol":{}"#),
        ]
        for raw in documents {
            let t = ManagementTransport(); await t.setReadDocument(Data(raw.utf8))
            let s = try service(t); _ = try await s.connect(allowCandidateWrites: true)
            let bytes = try await s.pageDocumentData(id: "created")
            XCTAssertEqual(bytes, Data(raw.utf8), "Unsupported documents must remain readable without rebuilding JSON")
            do { _ = try await s.readPageForDeletion(id: "created"); XCTFail("Unsupported deletion must refuse") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled) }
            do { _ = try await s.savePage(id: "created", patch: .init(name: "Changed", expectedRevision: "original")); XCTFail("Unsupported save must refuse") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled) }
            let requests = await t.requests
            XCTAssertFalse(requests.contains(where: \.isMutation), "No mutation may reach the transport")
        }
    }
}

private actor ManagementTransport: APITransport {
    static let document = Data(#"{"id":"created","name":"LED 🌈","type":"template","device_type":"panel","grid_rows":8,"grid_cols":16,"template":["{red}Hi"],"revision":"original","edit_protocol":"page-revision-v1","document_protocol":"page-document-v1","future":{"number":9007199254740993},"layers":[{"opaque":true}]}"#.utf8)
    var requests: [APIRequest] = []
    var version = "10.1.20"
    var dev = false
    var mutationStatus: Int?
    var mutationData: Data?
    var failure: FiestaBoardError?
    private var readDocument = document
    func setReadDocument(_ data: Data) { readDocument = data }
    private var hold = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func holdNextMutation() { hold = true }
    func waitForMutation(count: Int = 1) async { if pending.count >= count { return }; await withCheckedContinuation { observers.append((count, $0)) } }
    func releaseMutation() { if !pending.isEmpty { pending.removeFirst().resume() } }
    func set(version: String, dev: Bool = false) { self.version = version; self.dev = dev }
    func outcome(status: Int? = nil, data: Data? = nil, error: FiestaBoardError? = nil) { mutationStatus = status; mutationData = data; failure = error }
    func lastRequest() -> APIRequest? { requests.last }
    func resetSession() {}
    func send(_ r: APIRequest) async throws -> APIResponse {
        requests.append(r)
        if r.path == ["version"] { return APIResponse(status: 200, data: Data("{\"running_version\":\"\(version)\",\"package_version\":\"\(version)\",\"build_version\":\"fixture\",\"is_dev\":\(dev)}".utf8)) }
        if r.path == ["v1", "boards"] { return APIResponse(status: 200, data: Data(#"{"boards":[],"total":0}"#.utf8)) }
        if r.isMutation {
            if hold {
                hold = false
                await withCheckedContinuation { pending.append($0); let ready = observers.filter { $0.0 <= pending.count }; observers.removeAll { $0.0 <= pending.count }; ready.forEach { $0.1.resume() } }
            }
            if let failure { throw failure }
            return APIResponse(status: mutationStatus ?? (r.method == .post ? 201 : 200), data: mutationData ?? (r.method == .post ? Self.document : Data(#"{"id":"created","message":"Deleted","default_page_created":false,"new_page_id":null,"active_page_updated":false,"new_active_page_id":null}"#.utf8)))
        }
        return APIResponse(status: 200, data: readDocument)
    }
}

extension PageManagementTests {
    func testCapabilitiesRequireExactNondevelopmentVersionAndOptIn() async throws {
        for (version, dev, optIn) in [("10.1.17", false, true), ("10.1.21", false, true), ("10.1.20-dev", false, true), ("10.1.20", true, true), ("10.1.20", false, false)] {
            let t = ManagementTransport(); await t.set(version: version, dev: dev)
            let s = try service(t); _ = try await s.connect(allowCandidateWrites: optIn)
            let access = await s.pageManagementCapability()
            XCTAssertFalse(access.canCreate); XCTAssertFalse(access.canDelete)
            do { _ = try await s.preparePageCreation(.init(name: "x", family: .flagship)); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, .pageWritesDisabled) }
        }
    }
    func testCreateUnknownCannotReplayAndReconnectRetiresContexts() async throws {
        let t = ManagementTransport(); let s = try service(t)
        _ = try await s.connect(allowCandidateWrites: true)
        let input = PageCreationInput(name: "LED 🌈", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"])
        let context = try await s.preparePageCreation(input)
        await t.outcome(error: .unknownMutationOutcome)
        do { _ = try await s.createPage(context: context); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        do { _ = try await s.createPage(context: context); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        let next = try await s.preparePageCreation(input)
        _ = try await s.connect(allowCandidateWrites: true)
        do { _ = try await s.createPage(context: next); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
    }
    func testDeleteDistinctRefusalsAndUnknownMalformedSuccess() async throws {
        for (status, expected) in [(412, FiestaBoardError.pageConflict), (409, .pageInUse), (404, .rejected(status: 404)), (500, .unknownMutationOutcome), (202, .unknownMutationOutcome)] {
            let t = ManagementTransport(); let s = try service(t)
            _ = try await s.connect(allowCandidateWrites: true)
            let context = try await s.readPageForDeletion(id: "created")
            await t.outcome(status: status)
            do { _ = try await s.deletePage(context: context); XCTFail("status \(status)") } catch { XCTAssertEqual(error as? FiestaBoardError, expected) }
            do { _ = try await s.deletePage(context: context); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        }
        for raw in [#"{"id":"other","message":"x","default_page_created":false,"new_page_id":null,"active_page_updated":false,"new_active_page_id":null}"#,
                    #"{"id":"created","message":"x","default_page_created":false,"active_page_updated":false,"new_active_page_id":null}"#,
                    #"{"id":"created","message":"x","default_page_created":true,"new_page_id":null,"active_page_updated":false,"new_active_page_id":null}"#,
                    #"{"id":"created","message":"x","default_page_created":false,"new_page_id":null,"active_page_updated":true,"new_active_page_id":"created"}"#] {
            XCTAssertThrowsError(try PageDeletionReceipt(rawData: Data(raw.utf8), expectedPageID: "created"))
        }
        let replacement = try PageDeletionReceipt(rawData: Data(#"{"id":"created","message":"x","default_page_created":true,"new_page_id":"welcome","active_page_updated":true,"new_active_page_id":"welcome"}"#.utf8), expectedPageID: "created")
        XCTAssertEqual(replacement.newActivePageID, "welcome")
    }
    func testDemoCreatesReadsEditsAndDeletesPanelPage() async throws {
        let s = try DemoFiestaBoardService(); _ = try await s.connect()
        let capability = await s.pageManagementCapability(); XCTAssertTrue(capability.isSimulated)
        let context = try await s.preparePageCreation(.init(name: "Demo panel", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"]))
        let receipt = try await s.createPage(context: context)
        let document = try await s.pageDocumentData(id: receipt.page.id)
        XCTAssertEqual(document, receipt.pageData)
        _ = try await s.savePage(id: receipt.page.id, patch: .init(name: "Renamed", expectedRevision: receipt.page.revision!))
        let deletion = try await s.readPageForDeletion(id: receipt.page.id)
        XCTAssertEqual(deletion.page.name, "Renamed")
        let deleted = try await s.deletePage(context: deletion)
        XCTAssertFalse(deleted.defaultPageCreated, "Other pages remain and this panel is not active")
        let pages = try await s.pages(); XCTAssertFalse(pages.contains { $0.id == receipt.page.id })
    }
}

extension PageManagementTests {
    func testURLSessionRequestsPreservePrefixOriginalRevisionAndRefusalClassification() async throws {
        let log = RequestLog()
        for (status, expected) in [(200, Optional<FiestaBoardError>.none), (412, .pageConflict), (409, .pageInUse), (404, .rejected(status: 404)), (503, .unknownMutationOutcome)] {
            FixtureURLProtocol.handler = { r in
                log.append(r)
                if r.url!.path.hasSuffix("/version") { return (200, [:], Data(#"{"running_version":"10.1.20","package_version":"10.1.20","build_version":"test","is_dev":false}"#.utf8)) }
                if r.url!.path.hasSuffix("/boards") { return (200, [:], Data(#"{"boards":[],"total":0}"#.utf8)) }
                if r.httpMethod == "DELETE" { return (status, [:], Data(#"{"id":"created","message":"ok","default_page_created":false,"new_page_id":null,"active_page_updated":false,"new_active_page_id":null}"#.utf8)) }
                if r.httpMethod == "POST" { return (201, [:], ManagementTransport.document) }
                return (200, [:], ManagementTransport.document)
            }
            let deployment = try DeploymentURL("https://fixture.test/prefix")
            let s = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
            _ = try await s.connect(allowCandidateWrites: true)
            let creation = try await s.preparePageCreation(.init(name: "LED 🌈", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"]))
            _ = try await s.createPage(context: creation)
            let deletion = try await s.readPageForDeletion(id: "created")
            do { _ = try await s.deletePage(context: deletion); XCTAssertNil(expected) }
            catch { XCTAssertEqual(error as? FiestaBoardError, expected) }
            let request = try XCTUnwrap(log.requests.last)
            XCTAssertEqual(request.url?.path, "/prefix/api/v1/pages/created")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "expected_revision", value: "original")])
            XCTAssertNil(request.httpBody)
        }
    }
    func testMalformedCreateStatusesAndReceiptsRemainUnknown() async throws {
        let input = PageCreationInput(name: "LED 🌈", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"])
        for (status, bytes) in [(200, ManagementTransport.document), (201, Data("{}".utf8)), (201, Data("{\"page\":\(String(decoding: ManagementTransport.document, as: UTF8.self))}".utf8)), (302, Data())] {
            let t = ManagementTransport(); let s = try service(t); _ = try await s.connect(allowCandidateWrites: true)
            let c = try await s.preparePageCreation(input); await t.outcome(status: status, data: bytes)
            do { _ = try await s.createPage(context: c); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        }
    }
    func testCrossServiceContextCannotDispatchAndEditRetiresDeletionContext() async throws {
        let t = ManagementTransport(); let s = try service(t); let other = try service(ManagementTransport())
        _ = try await s.connect(allowCandidateWrites: true); _ = try await other.connect(allowCandidateWrites: true)
        let c = try await s.preparePageCreation(.init(name: "x", family: .flagship))
        XCTAssertEqual(c.deployment, s.deployment)
        do { _ = try await other.createPage(context: c); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        let deletion = try await s.readPageForDeletion(id: "created")
        _ = try await s.page(id: "created")
        // Even an uncertain editor dispatch invalidates the original management context.
        await t.outcome(error: .unknownMutationOutcome)
        do { _ = try await s.savePage(id: "created", patch: .init(name: "new", expectedRevision: "original")); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        do { _ = try await s.deletePage(context: deletion); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
    }
}


extension PageManagementTests {
    func testInFlightCreateRejectsDuplicateAndLateSessionReply() async throws {
        let t = ManagementTransport(); let s = try service(t)
        _ = try await s.connect(allowCandidateWrites: true)
        let c = try await s.preparePageCreation(.init(name: "LED 🌈", family: .panel(rows: 8, cols: 16), template: ["{red}Hi"]))
        await t.holdNextMutation()
        let write = Task { try await s.createPage(context: c) }
        await t.waitForMutation()
        do { _ = try await s.createPage(context: c); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        _ = try await s.connect(allowCandidateWrites: true)
        await t.releaseMutation()
        do { _ = try await write.value; XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
    }
    func testDeleteLocksEditorAndFreshReadThenCancellationIsUnknown() async throws {
        let t = ManagementTransport(); let s = try service(t)
        _ = try await s.connect(allowCandidateWrites: true)
        _ = try await s.page(id: "created")
        let c = try await s.readPageForDeletion(id: "created")
        await t.holdNextMutation()
        let write = Task { try await s.deletePage(context: c) }
        await t.waitForMutation()
        do { _ = try await s.readPageForDeletion(id: "created"); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        do { _ = try await s.savePage(id: "created", patch: .init(name: "x", expectedRevision: "original")); XCTFail() } catch { XCTAssertTrue([FiestaBoardError.pageWritesDisabled, .pageReadbackRequired].contains(error as? FiestaBoardError ?? .invalidResponse)) }
        write.cancel(); await t.releaseMutation()
        do { _ = try await write.value; XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        do { _ = try await s.deletePage(context: c); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
    }
}


extension PageManagementTests {
    func testReconnectReleasesOldDeleteLockAndLateCompletionCannotReleaseNewLock() async throws {
        try await verifyOldSessionLockRetires(editorSave: false)
    }
    func testOldEditorCompletionCannotReleaseNewSessionDeleteLock() async throws {
        try await verifyOldSessionLockRetires(editorSave: true)
    }
    private func verifyOldSessionLockRetires(editorSave: Bool) async throws {
        let t = ManagementTransport(); let s = try service(t)
        _ = try await s.connect(allowCandidateWrites: true)
        let original = try await s.readPageForDeletion(id: "created")
        await t.holdNextMutation()
        _ = try await s.page(id: "created")
        let old = Task {
            if editorSave { _ = try await s.savePage(id: "created", patch: .init(name: "x", expectedRevision: "original")) }
            else { _ = try await s.deletePage(context: original) }
        }
        await t.waitForMutation()
        _ = try await s.connect(allowCandidateWrites: true)
        let fresh: PageDeletionContext
        do { fresh = try await s.readPageForDeletion(id: "created") }
        catch {
            await t.releaseMutation(); _ = try? await old.value
            XCTFail("Reconnect must retire old session locks: \(error)"); return
        }
        await t.holdNextMutation()
        let current = Task { try await s.deletePage(context: fresh) }
        await t.waitForMutation(count: 2)
        await t.releaseMutation()
        do { _ = try await old.value; XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        do { _ = try await s.readPageForDeletion(id: "created"); XCTFail("Old completion must not clear current lock") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageReadbackRequired) }
        await t.releaseMutation(); _ = try await current.value
    }
    func testDemoCollectionReferenceRefusesDeletionAndRetainsPage() async throws {
        let s = try DemoFiestaBoardService(); _ = try await s.connect()
        let creation = try await s.preparePageCreation(.init(name: "Referenced", family: .flagship))
        let page = try await s.createPage(context: creation)
        _ = try await s.createCollection(.init(name: "Reference", pageIDs: [page.page.id]))
        let deletion = try await s.readPageForDeletion(id: page.page.id)
        do { _ = try await s.deletePage(context: deletion); XCTFail("Referenced page must remain") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .pageInUse) }
        let retained = try await s.pageDocumentData(id: page.page.id)
        XCTAssertEqual(retained, page.pageData)
    }
}
