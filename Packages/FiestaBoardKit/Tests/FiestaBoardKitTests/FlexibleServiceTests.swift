import Foundation
import XCTest
@testable import FiestaBoardKit

@MainActor final class FlexibleServiceTests: XCTestCase {
    func testFlexibleReadPreviewConditionalSaveAndReopenRetainExactDocument() async throws {
        let transport = FlexibleFixtureTransport()
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true)
        _ = try await service.boards()
        let before = try await service.pageDocumentData(id: "p")
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
        let body = Data(#"{"page":{"name":"P","type":"flexible","blocks":[{"id":"t","kind":"text","text":"Edited","large":900719925474099312345678}]},"board_id":"board-2"}"#.utf8)
        let result = try await service.previewFlexiblePage(requestData: body, target: target)
        XCTAssertEqual(result.layoutIssueCount, 1)
        let blocks = Data(#"[{"id":"t","kind":"text","text":"Edited","large":900719925474099312345678},{"id":"future","kind":"future","extension":null}]"#.utf8)
        let receipt = try await service.savePage(id: "p", patch: PageSavePatch(blocksData: blocks, expectedRevision: "original"))
        XCTAssertEqual(try RawJSONObject.members(receipt.pageData)["blocks"], blocks)
        let reopened = try await service.pageDocumentData(id: "p")
        XCTAssertEqual(reopened, receipt.pageData)
        XCTAssertNotEqual(reopened, before)
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.isMutation }.count, 1)
        let preview = try XCTUnwrap(requests.first { $0.path == ["pages", "preview", "flexible"] })
        XCTAssertEqual(preview.body, body)
        let put = try XCTUnwrap(requests.first { $0.method == .put })
        XCTAssertEqual(Set(try RawJSONObject.members(XCTUnwrap(put.body)).keys), ["blocks", "expected_revision"])
    }
    func testFlexibleConflictHasNoAutomaticRetryAndRequiresReadback() async throws {
        let transport = FlexibleFixtureTransport()
        await transport.setSaveStatus(412)
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true)
        _ = try await service.pageDocumentData(id: "p")
        for expected in [FiestaBoardError.pageConflict, .pageReadbackRequired] {
            do { _ = try await service.savePage(id: "p", patch: PageSavePatch(name: "Changed", expectedRevision: "original")); XCTFail() }
            catch { XCTAssertEqual(error as? FiestaBoardError, expected) }
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.method == .put }.count, 1)
    }
    func testFlexiblePreviewRejectsWrongDeploymentAndTargetBeforeTransportAnd404IsEvaluationFailure() async throws {
        let transport = FlexibleFixtureTransport()
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true); _ = try await service.boards()
        _ = try await service.pageDocumentData(id: "p")
        let body = Data(#"{"page":{"name":"P","type":"flexible","blocks":[{"id":"t","kind":"text","text":"A"}]},"board_id":"board-2"}"#.utf8)
        let wrong = try BoardTarget(deployment: DeploymentURL("https://other.test"), boardID: "board-2")
        do { _ = try await service.previewFlexiblePage(requestData: body, target: wrong); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .invalidTarget) }
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
        await transport.setPreviewStatus(404)
        do { _ = try await service.previewFlexiblePage(requestData: body, target: target); XCTFail() } catch { XCTAssertEqual(error as? FiestaBoardError, .rejected(status: 404)) }
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.path == ["pages", "preview", "flexible"] }.count, 1)
        XCTAssertFalse(requests.contains(where: \.isMutation))
    }
    func testUnknownShapeReplacementAndGridFieldsCannotReachTransport() async throws {
        let transport = FlexibleFixtureTransport()
        let service = LiveFiestaBoardService(deployment: try DeploymentURL("https://fixture.test"), transport: transport)
        _ = try await service.connect(allowCandidateWrites: true); _ = try await service.pageDocumentData(id: "p")
        let blocks = Data(#"[{"id":"c","kind":"canvas","canvas":{"content":{"shapes":[{"type":"future","large":900719925474099312345678}]}}}]"#.utf8)
        do { _ = try await service.savePage(id: "p", patch: PageSavePatch(blocksData: blocks, expectedRevision: "original")); XCTFail() } catch {}
        let requests = await transport.requests
        XCTAssertFalse(requests.contains(where: \.isMutation))
    }
}

private actor FlexibleFixtureTransport: APITransport {
    var requests: [APIRequest] = []
    private var saveStatus = 200
    private var previewStatus = 200
    private var document = Data(#"{"id":"p","name":"P","type":"flexible","document_protocol":"page-document-v2","edit_protocol":"page-revision-v1","revision":"original","blocks":[{"id":"t","kind":"text","text":"A","large":900719925474099312345678}],"style":null}"#.utf8)
    func setSaveStatus(_ status: Int) { saveStatus = status }
    func setPreviewStatus(_ status: Int) { previewStatus = status }
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        if request.path == ["version"] { return APIResponse(status: 200, data: Data(#"{"running_version":"99.0.0","package_version":"99.0.0","build_version":"synthetic-flexible-contract-864cfa6","is_dev":true}"#.utf8)) }
        if request.path == ["v1", "boards"] { return APIResponse(status: 200, data: fixture("boards")) }
        if request.path == ["pages", "preview", "flexible"] {
            return APIResponse(status: previewStatus, data: Data(#"{"available":true,"page_id":"unsaved","message":"A","lines":["A"],"display_type":"panel","raw":{},"layout_issues":[{"path":["blocks","t"],"code":"shrunk","severity":"warning","message":"synthetic warning"}]}"#.utf8))
        }
        if request.method == .put {
            guard saveStatus == 200 else { return APIResponse(status: saveStatus, data: Data("{}".utf8)) }
            var members = try RawJSONObject.members(document)
            for (key, value) in try RawJSONObject.members(request.body!) where key != "expected_revision" { members[key] = value }
            members["revision"] = Data(#""updated""#.utf8)
            var data = Data("{".utf8)
            for (index, pair) in members.sorted(by: { $0.key < $1.key }).enumerated() {
                if index > 0 { data.append(44) }
                data.append(try JSONEncoder().encode(pair.key)); data.append(58); data.append(pair.value)
            }
            data.append(125); document = data
            var receipt = Data(#"{"page":"#.utf8); receipt.append(data); receipt.append(Data(#", "incompatible_references":[]}"#.utf8))
            return APIResponse(status: 200, data: receipt)
        }
        return APIResponse(status: 200, data: document)
    }
}
