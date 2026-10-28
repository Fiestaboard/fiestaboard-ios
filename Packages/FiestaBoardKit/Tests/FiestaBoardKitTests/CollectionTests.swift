import Foundation
import XCTest
@testable import FiestaBoardKit

final class CollectionTests: XCTestCase, @unchecked Sendable {
    func testInputValidationAndExplicitNullEncoding() throws {
        var input = collectionInput()
        input.name = String(repeating: "e\u{301}", count: 50)
        try input.validate()
        input.name += "x"
        XCTAssertThrowsError(try input.validate())
        input.name = " " // Backend counts scalars and does not trim names.
        try input.validate()
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
        XCTAssertTrue(body["variable"] is NSNull); XCTAssertTrue(body["random"] is NSNull)
        for ids in [[], ["p", "p"], ["collection:nested"], [""]] {
            input.pageIDs = ids; XCTAssertThrowsError(try input.validate())
        }
        input = collectionInput()
        for interval in [4, 86401] { input.time.intervalSeconds = interval; XCTAssertThrowsError(try input.validate()) }
        input = collectionInput(); input.selectionMode = .random
        XCTAssertThrowsError(try input.validate())
        input.random = .init(intervalSeconds: 86400); try input.validate()
        input.selectionMode = .variable; XCTAssertThrowsError(try input.validate())
        input.variable = .init(rules: [.init(expression: "true", pageID: "p")], defaultPageID: "p", pollSeconds: 2)
        try input.validate()
        input.variable?.rules[0].pageID = "missing"; XCTAssertThrowsError(try input.validate())
        input.variable?.rules = []; input.variable?.defaultPageID = "missing"; XCTAssertThrowsError(try input.validate())
        input.variable?.defaultPageID = "p"; input.variable?.pollSeconds = 601; XCTAssertThrowsError(try input.validate())
    }

    func testCreateUpdateDeleteStrictContractsAndOriginalRevision() async throws {
        let transport = CollectionTransport(), service = try makeCollectionService(transport)
        let connection = try await service.connect(allowCandidateWrites: true)
        XCTAssertEqual(connection.access, .readOnly)
        let access = await service.collectionAccess(); XCTAssertTrue(access.canCreate)
        let original = try await service.collection(id: "collection:c")
        await transport.setRevision("newer")
        _ = try await service.collection(id: original.id)
        let updated = try await service.updateCollection(id: original.id, input: collectionInput(), expectedRevision: "original")
        XCTAssertEqual(updated.revision, "updated")
        let requests = await transport.requests
        let put = try XCTUnwrap(requests.last)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(put.body)) as! [String: Any]
        XCTAssertEqual(body["expected_revision"] as? String, "original")
        try await service.deleteCollection(id: original.id, expectedRevision: "updated")
        let delete = await transport.requests.last
        XCTAssertEqual(delete?.method, .delete)
        XCTAssertEqual(delete?.queryItems, [URLQueryItem(name: "expected_revision", value: "updated")])
        let created = try await service.createCollection(collectionInput())
        XCTAssertEqual(created.id, "collection:created")
    }

    func testOptInVersionAndReadProtocolGates() async throws {
        for (version, dev, optIn, canCreate) in [("10.1.7", false, true, true), ("10.1.7", true, true, false), ("10.1.8", false, true, false), ("10.1.7", false, false, false)] {
            let t = CollectionTransport(version: version, dev: dev), s = try makeCollectionService(t)
            _ = try await s.connect(allowCandidateWrites: optIn)
            let access = await s.collectionAccess(); XCTAssertEqual(access.canCreate, canCreate)
            if !canCreate { await expectCollectionError(.collectionWritesDisabled) { _ = try await s.createCollection(collectionInput()) } }
        }
        for (mode, proto, revision) in [("future", "collection-revision-v1", "original"), ("time", "future", "original"), ("time", "", "original"), ("time", "collection-revision-v1", "")] {
            let t = CollectionTransport(mode: mode, proto: proto, revision: revision), s = try makeCollectionService(t)
            _ = try await s.connect(allowCandidateWrites: true)
            let read = try await s.collection(id: "collection:c"); XCTAssertEqual(read.selectionMode, mode)
            await expectCollectionError(.collectionWritesDisabled) { _ = try await s.updateCollection(id: read.id, input: collectionInput(), expectedRevision: revision) }
        }
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true)
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
        _ = try await s.collections()
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
    }

    func testRefusalsAndUncertainWriteReadbackBarriers() async throws {
        for (status, error) in [(400, FiestaBoardError.rejected(status: 400)), (404, .rejected(status: 404)), (409, .collectionInUse), (412, .collectionConflict), (500, .unknownMutationOutcome)] {
            let t = CollectionTransport(), s = try makeCollectionService(t)
            _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
            await t.setMutationStatus(status)
            await expectCollectionError(error) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
            if [412, 500].contains(status) {
                await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
                _ = try await s.collection(id: "collection:c")
            }
        }
        for kind in ["create", "update", "delete"] {
            let t = CollectionTransport(), s = try makeCollectionService(t)
            _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
            await t.setMutationStatus(202)
            if kind == "create" {
                await expectCollectionError(.unknownMutationOutcome) { _ = try await s.createCollection(collectionInput()) }
                _ = try await s.collections()
                await expectCollectionError(.collectionReadbackRequired) { _ = try await s.createCollection(collectionInput()) }
            } else if kind == "update" {
                await expectCollectionError(.unknownMutationOutcome) { _ = try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
                await expectCollectionError(.collectionReadbackRequired) { _ = try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
            } else {
                await expectCollectionError(.unknownMutationOutcome) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
                await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
            }
        }
    }

    func testReceiptIdentityProtocolAndGenerationAreStrict() async throws {
        for defect in ["id", "protocol", "revision", "sameRevision", "mode"] {
            let t = CollectionTransport(), s = try makeCollectionService(t)
            _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
            await t.setDefect(defect)
            await expectCollectionError(.unknownMutationOutcome) { _ = try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
        }
    }

    func testReconnectAndAuthLossInvalidateReadAuthorization() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        _ = try await s.connect(allowCandidateWrites: true)
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
        _ = try await s.collection(id: "collection:c")
        await t.setAuthLost()
        _ = try await s.authStatus()
        let access = await s.collectionAccess(); XCTAssertFalse(access.writesOptedIn)
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
    }

    func testLateGETCannotClearUncertainUpdateBarrier() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        await t.delayNextRead()
        let read = Task { try await s.collection(id: "collection:c") }; await t.waitForDelay()
        await t.setMutationStatus(202)
        await expectCollectionError(.unknownMutationOutcome) { _ = try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
        await t.release()
        await expectCollectionError(.staleCollectionContext) { _ = try await read.value }
        await expectCollectionError(.collectionReadbackRequired) { _ = try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
    }

    func testDelayedMutationCannotAuthorizeSameURLReconnection() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        await t.delayNextMutation()
        let write = Task { try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }; await t.waitForDelay()
        _ = try await s.connect(allowCandidateWrites: true)
        await t.release()
        await expectCollectionError(.staleSession) { _ = try await write.value }
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "updated") }
    }

    func testDemoCRUDAllModesFreshRevisionsAndUnknownCreatesDoNotReplay() async throws {
        let service = try DemoFiestaBoardService(); _ = try await service.connect()
        let access = await service.collectionAccess(); XCTAssertTrue(access.canCreate); XCTAssertTrue(access.isSimulated)
        var input = collectionInput(); input.pageIDs = ["page-selected", "page-weather"]
        var record = try await service.createCollection(input)
        for mode in [CollectionSelectionMode.variable, .random, .time] {
            input.selectionMode = mode
            input.variable = mode == .variable ? .init(rules: [.init(expression: "true", pageID: "page-weather")], defaultPageID: "page-selected", pollSeconds: 10) : nil
            input.random = mode == .random ? .init(intervalSeconds: 30) : nil
            let previous = record.revision
            record = try await service.updateCollection(id: record.id, input: input, expectedRevision: try XCTUnwrap(previous))
            XCTAssertNotEqual(record.revision, previous)
        }
        try await service.deleteCollection(id: record.id, expectedRevision: try XCTUnwrap(record.revision))
        await expectCollectionError(.rejected(status: 404)) { _ = try await service.collection(id: record.id) }
        await service.setSimulation(.unknown)
        await expectCollectionError(.unknownMutationOutcome) { _ = try await service.createCollection(input) }
        let list = try await service.collections()
        XCTAssertEqual(list.count, 1)
        await expectCollectionError(.collectionReadbackRequired) { _ = try await service.createCollection(input) }
    }
}

private func collectionInput() -> CollectionInput { .init(name: "Test 🛰️", pageIDs: ["p"], selectionMode: .time, time: .init(intervalSeconds: 30), variable: nil, random: nil) }
private func makeCollectionService(_ transport: CollectionTransport) throws -> LiveFiestaBoardService { LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test/prefix"), transport: transport) }
private func expectCollectionError(_ expected: FiestaBoardError, operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
    catch { XCTAssertEqual(error as? FiestaBoardError, expected, file: file, line: line) }
}

private actor CollectionTransport: APITransport {
    var requests: [APIRequest] = []
    let version: String; let dev: Bool
    var mode: String; var proto: String; var revision: String
    var mutationStatus: Int?; var defect: String?; var authLost = false
    var delayRead = false; var delayMutation = false
    var gate: CheckedContinuation<Void, Never>?; var observers: [CheckedContinuation<Void, Never>] = []
    init(version: String = "10.1.7", dev: Bool = false, mode: String = "time", proto: String = "collection-revision-v1", revision: String = "original") { self.version = version; self.dev = dev; self.mode = mode; self.proto = proto; self.revision = revision }
    func resetSession() {}
    func setRevision(_ value: String) { revision = value }
    func setMutationStatus(_ value: Int) { mutationStatus = value }
    func setDefect(_ value: String) { defect = value }
    func setAuthLost() { authLost = true }
    func delayNextRead() { delayRead = true }
    func delayNextMutation() { delayMutation = true }
    func waitForDelay() async { if gate != nil { return }; await withCheckedContinuation { observers.append($0) } }
    func release() { gate?.resume(); gate = nil }
    func send(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        if request.path == ["version"] { return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["package_version": version, "build_version": version, "running_version": version, "is_dev": dev])) }
        if request.path == ["v1", "boards"] { return APIResponse(status: 200, data: Data(#"{"boards":[],"total":0}"#.utf8)) }
        if request.path == ["auth", "logout"] { return APIResponse(status: 200, data: Data(#"{"status":"ok"}"#.utf8)) }
        if request.path == ["auth", "status"] { return APIResponse(status: 200, data: Data((authLost ? #"{"enabled":true,"setup_required":false,"authenticated":false}"# : #"{"enabled":false,"setup_required":false,"authenticated":false}"#).utf8)) }
        var record: [String: Any] = ["id": "collection:c", "name": "Test 🛰️", "page_ids": ["p"], "selection_mode": mode, "time": ["interval_seconds": 30], "variable": NSNull(), "random": NSNull(), "revision": revision, "edit_protocol": proto]
        if request.isMutation {
            record["id"] = request.method == .post ? "collection:created" : "collection:c"
            record["revision"] = "updated"
            if defect == "id" { record["id"] = "collection:wrong" }
            if defect == "protocol" { record["edit_protocol"] = "future" }
            if defect == "revision" { record["revision"] = NSNull() }
            if defect == "sameRevision" { record["revision"] = "original" }
            if defect == "mode" { record["selection_mode"] = "future" }
        }
        let object: [String: Any]
        if request.method == .delete { object = ["id": "collection:c"] }
        else if request.path == ["v1", "collections"] && !request.isMutation { object = ["collections": [record], "total": 1] }
        else { object = record }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        if (request.isMutation && delayMutation) || (!request.isMutation && delayRead) {
            delayRead = false; delayMutation = false
            await withCheckedContinuation { gate = $0; observers.forEach { $0.resume() }; observers = [] }
        }
        return APIResponse(status: request.isMutation ? mutationStatus ?? (request.method == .post ? 201 : 200) : 200, data: bytes)
    }
}

extension CollectionTests {
    func testBackendFixtureKnownModesNullClearsAndOrderedValuesDecode() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "collections-v1", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let cases = fixture["cases"] as! [[String: Any]]
        for id in ["create_time", "create_variable", "create_random", "get", "update_clear_configs"] {
            let item = try XCTUnwrap(cases.first { $0["id"] as? String == id })
            let response = item["response"] as! [String: Any]
            let record = try JSONDecoder().decode(PageCollection.self, from: JSONSerialization.data(withJSONObject: response["body"]!))
            XCTAssertTrue(record.supportsEditing, id)
            XCTAssertEqual(record.editProtocol, "collection-revision-v1")
            if id == "create_time" { XCTAssertEqual(record.pageIDs, ["page-b", "page-a"]); XCTAssertEqual(record.name, "Morning ☀️") }
            if id == "update_clear_configs" { XCTAssertNil(record.variable); XCTAssertNil(record.random) }
            if let requestBody = (item["request"] as? [String: Any])?["body"] {
                let input = try JSONDecoder().decode(CollectionInput.self, from: JSONSerialization.data(withJSONObject: requestBody))
                try input.validate()
                XCTAssertEqual(record.pageIDs, input.pageIDs)
                XCTAssertEqual(record.variable, input.variable)
            }
        }
    }

    func testUnknownFieldsInCollectionAndNestedConfigsRemainReadOnly() throws {
        let base = #"{"id":"collection:c","name":"x","page_ids":["p"],"selection_mode":"time","time":{"interval_seconds":30},"revision":"r","edit_protocol":"collection-revision-v1"}"#
        var object = try JSONSerialization.jsonObject(with: Data(base.utf8)) as! [String: Any]
        XCTAssertTrue(try JSONDecoder().decode(PageCollection.self, from: JSONSerialization.data(withJSONObject: object)).supportsEditing)
        for field in ["future", "time", "variable", "random"] {
            var unknown = object
            if field == "future" { unknown[field] = 1 }
            if field == "time" || field == "random" { unknown[field] = ["interval_seconds": 30, "future": 1] }
            if field == "variable" { unknown[field] = ["default_page_id": "p", "poll_seconds": 10, "rules": [["expression": "true", "page_id": "p", "future": 1]]] }
            XCTAssertFalse(try JSONDecoder().decode(PageCollection.self, from: JSONSerialization.data(withJSONObject: unknown)).supportsEditing, field)
        }
        object["selection_mode"] = "future"
        XCTAssertFalse(try JSONDecoder().decode(PageCollection.self, from: JSONSerialization.data(withJSONObject: object)).supportsEditing)
    }

    func testGETBegunDuringWriteCannotClearBarrierAfterUnknownAcknowledgement() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        await t.delayNextMutation(); await t.setMutationStatus(202)
        let write = Task { try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
        await t.waitForDelay()
        await expectCollectionError(.staleCollectionContext) { _ = try await s.collection(id: "collection:c") }
        await t.release()
        await expectCollectionError(.unknownMutationOutcome) { _ = try await write.value }
        await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
    }

    func testCancelledSuccessfulMutationKeepsReadbackBarrier() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        await t.delayNextMutation()
        let write = Task { try await s.updateCollection(id: "collection:c", input: collectionInput(), expectedRevision: "original") }
        await t.waitForDelay(); write.cancel(); await t.release()
        await expectCollectionError(.unknownMutationOutcome) { _ = try await write.value }
        await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
    }

    func testLogoutAndInFlightGETCannotRestoreAuthorization() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true); _ = try await s.collection(id: "collection:c")
        await t.delayNextRead()
        let read = Task { try await s.collection(id: "collection:c") }; await t.waitForDelay()
        try await s.logout(); await t.release()
        await expectCollectionError(.staleSession) { _ = try await read.value }
        await expectCollectionError(.collectionWritesDisabled) { try await s.deleteCollection(id: "collection:c", expectedRevision: "original") }
    }

    func testDemoConflictReadbackAndUnknownUpdateDelete() async throws {
        let s = try DemoFiestaBoardService(); _ = try await s.connect()
        var input = collectionInput(); input.pageIDs = ["page-selected"]
        let first = try await s.createCollection(input), second = try await s.createCollection(input)
        XCTAssertNotEqual(first.id, second.id); XCTAssertNotEqual(first.revision, second.revision)
        await s.setSimulation(.rejected)
        await expectCollectionError(.collectionConflict) { _ = try await s.updateCollection(id: first.id, input: input, expectedRevision: try XCTUnwrap(first.revision)) }
        await s.setSimulation(.accepted)
        await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: first.id, expectedRevision: try XCTUnwrap(first.revision)) }
        _ = try await s.collection(id: first.id)
        await s.setSimulation(.unknown)
        await expectCollectionError(.unknownMutationOutcome) { _ = try await s.updateCollection(id: first.id, input: input, expectedRevision: try XCTUnwrap(first.revision)) }
        let readback = try await s.collection(id: first.id)
        XCTAssertNotEqual(readback.revision, first.revision)
        await expectCollectionError(.unknownMutationOutcome) { try await s.deleteCollection(id: first.id, expectedRevision: try XCTUnwrap(readback.revision)) }
        await expectCollectionError(.rejected(status: 404)) { _ = try await s.collection(id: first.id) }
        await expectCollectionError(.collectionReadbackRequired) { try await s.deleteCollection(id: first.id, expectedRevision: try XCTUnwrap(readback.revision)) }
    }
}

extension TransportTests {
    func testCollectionIDPrefixAndOriginalDeleteRevisionAreSafelyEncoded() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data(#"{"id":"collection:c"}"#.utf8)) }
        let transport = try transport("https://board.test/reverse/prefix")
        let original = "revision +&=?#🛰️"
        _ = try await transport.send(APIRequest(.delete, path: ["v1", "collections", "collection:c"], queryItems: [.init(name: "expected_revision", value: original)]))
        let request = try XCTUnwrap(log.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/reverse/prefix/api/v1/collections/collection:c")
        XCTAssertFalse(request.url!.absoluteString.contains("+"), "Query values must preserve a literal plus through form-style server query decoding")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [.init(name: "expected_revision", value: original)])
        for invalid in ["collection:", "collection:../x", "collection:c?x=1", "collection:c%2f", "collection:a:b"] {
            do { _ = try await transport.send(APIRequest(path: ["v1", "collections", invalid])); XCTFail(invalid) }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidPath) }
        }
        XCTAssertEqual(log.requests.count, 1)
    }
    func testCollectionHTTPRefusalsAndUncertaintyAreDistinctWithoutReplay() async throws {
        let cases: [(Int, FiestaBoardError)] = [(400, .rejected(status: 400)), (404, .rejected(status: 404)), (409, .collectionInUse), (412, .collectionConflict), (500, .unknownMutationOutcome)]
        for (status, expected) in cases {
            let log = RequestLog()
            FixtureURLProtocol.handler = { request in log.append(request); return (status, [:], Data(#"{"detail":"private server diagnostic"}"#.utf8)) }
            do { _ = try await transport().send(APIRequest(.delete, path: ["v1", "collections", "collection:c"])); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, expected); XCTAssertFalse(error.localizedDescription.contains("private")) }
            XCTAssertEqual(log.requests.count, 1)
        }
    }
}


extension CollectionTests {
    func testExplicitCreationReviewRequiresListStartedAfterUnknownOutcome() async throws {
        let t = CollectionTransport(), s = try makeCollectionService(t)
        _ = try await s.connect(allowCandidateWrites: true)
        await t.delayNextRead()
        let oldList = Task { try await s.collections() }; await t.waitForDelay()
        await t.setMutationStatus(202)
        await expectCollectionError(.unknownMutationOutcome) { _ = try await s.createCollection(collectionInput()) }
        await expectCollectionError(.collectionReadbackRequired) { try await s.acknowledgeCollectionCreationReview() }
        await t.release(); _ = try await oldList.value
        await expectCollectionError(.collectionReadbackRequired) { try await s.acknowledgeCollectionCreationReview() }
        _ = try await s.collections()
        await expectCollectionError(.collectionReadbackRequired) { _ = try await s.createCollection(collectionInput()) }
        try await s.acknowledgeCollectionCreationReview()
        await t.setMutationStatus(201)
        _ = try await s.createCollection(collectionInput())
        let requests = await t.requests
        XCTAssertEqual(requests.filter { $0.method == .post }.count, 2)
    }
}
