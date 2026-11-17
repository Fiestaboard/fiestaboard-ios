import XCTest
import FiestaBoardDocuments
@testable import FiestaBoardKit

final class ComposeRequestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func request(text: String = "Hi {{weather.temp}}\nSECOND", duration: ComposeBufferDuration = .minutes(120),
                         preparedAt: Date? = nil, geometry: ComposeGeometry = .flagship) throws -> ComposeRequest {
        let deployment = try DeploymentURL("https://board.test/prefix")
        let principal = ComposePrincipalProof(deployment: deployment, installationID: "install", principalID: "authenticated-user",
            connectionID: UUID(), verifiedOnline: true)
        return ComposeRequest(principal: principal, target: try BoardTarget(deployment: deployment, boardID: "hall-1"),
            requestID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!, preparedAt: preparedAt ?? now,
            text: text, lineMetadata: text.components(separatedBy: "\n").map { _ in .init(alignment: "right", wrap: true) },
            geometry: geometry, duration: duration, silence: .hold)
    }
    func testCapturedBodyPreservesOriginalSourceFormattingDurationAndConsent() throws {
        let captured = try request()
        let data = try captured.encoded(now: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["protocol"] as? String, "compose-intent-v1")
        XCTAssertEqual(object["request_id"] as? String, "11111111-2222-4333-8444-555555555555")
        XCTAssertEqual(object["template"] as? [String], ["Hi {{weather.temp}}", "SECOND"])
        XCTAssertEqual(object["silence"] as? String, "hold")
        let metadata = try XCTUnwrap(object["line_metadata"] as? [[String: Any]])
        XCTAssertEqual(metadata.count, 2); XCTAssertEqual(metadata[0]["alignment"] as? String, "right")
        XCTAssertEqual(metadata[1]["wrap"] as? Bool, true)
        let duration = try XCTUnwrap(object["duration"] as? [String: Any])
        XCTAssertEqual(duration["kind"] as? String, "minutes"); XCTAssertEqual(duration["minutes"] as? Int, 120)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("authenticated-user"))
        XCTAssertNil(object["principal"]); XCTAssertNil(object["connectionID"])
    }
    func testExpiredAbsoluteAndOldPreparedIntentNeverEncodeAsIndefinite() throws {
        for duration in [ComposeBufferDuration.until(now), .until(now.addingTimeInterval(-1)), .until(now.addingTimeInterval(28_801)), .minutes(0), .minutes(481)] {
            XCTAssertThrowsError(try request(duration: duration).encoded(now: now))
        }
        XCTAssertThrowsError(try request(preparedAt: now.addingTimeInterval(-301)).encoded(now: now))
        XCTAssertThrowsError(try request(preparedAt: now.addingTimeInterval(301)).encoded(now: now))
        let indefinite = try JSONSerialization.jsonObject(with: request(duration: .untilCancel).encoded(now: now)) as! [String: Any]
        XCTAssertEqual((indefinite["duration"] as? [String: String])?["kind"], "until_cancel")
    }
    func testStrictTemplateAndPanelGeometryBoundsFailBeforeTransport() throws {
        for text in [String(repeating: "x", count: 4097), Array(repeating: "x", count: 513).joined(separator: "\n"), String(repeating: "x", count: 65_537)] {
            XCTAssertThrowsError(try request(text: text).encoded(now: now))
        }
        for geometry in [ComposeGeometry.panel(rows: 0, cols: 8), .panel(rows: 1, cols: 4), .panel(rows: 97, cols: 128), .noteArray(wide: 9, tall: 1)] {
            XCTAssertThrowsError(try request(geometry: geometry).encoded(now: now))
        }
        let panel = try JSONSerialization.jsonObject(with: request(geometry: .panel(rows: 1, cols: 8)).encoded(now: now)) as! [String: Any]
        XCTAssertEqual((panel["geometry"] as? [String: Any])?["grid_cols"] as? Int, 8)
    }
}

@MainActor final class ComposeTransportTests: XCTestCase {
    func testStructuredComposeErrorResponsesReachOperationDecoderWithoutMutationReplay() async throws {
        let deployment = try DeploymentURL("https://board.test/prefix")
        for status in [409, 429, 502, 503] {
            let log = RequestLog(), bytes = Data(#"{"detail":{"protocol":"compose-intent-v1","status":"unknown"}}"#.utf8)
            FixtureURLProtocol.handler = { request in log.append(request); return (status, [:], bytes) }
            let transport = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self])
            let response = try await transport.send(APIRequest(.post, path: ["v1", "boards", "hall-1", "compose"], body: Data("{}".utf8), cachePolicy: .noStore))
            XCTAssertEqual(response.status, status); XCTAssertEqual(response.data, bytes)
            XCTAssertEqual(log.requests.count, 1)
            XCTAssertEqual(log.requests.first?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        }
    }
    func testComposeErrorPassThroughNeverWidensOtherOperationsOrAuth() async throws {
        let deployment = try DeploymentURL("https://board.test/prefix")
        for path in [["v1", "boards", "hall-1", "message"], ["v1", "boards", "hall-1", "compose", "extra"], ["templates", "render", "live"]] {
            FixtureURLProtocol.handler = { _ in (409, [:], Data("{}".utf8)) }
            let transport = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self])
            do { _ = try await transport.send(APIRequest(.post, path: path)); XCTFail("Unrelated operation must retain its error") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .conflict) }
        }
        FixtureURLProtocol.handler = { _ in (401, [:], Data("{}".utf8)) }
        let transport = URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self])
        do { _ = try await transport.send(APIRequest(.post, path: ["v1", "boards", "hall-1", "compose"])); XCTFail("Auth remains fail closed") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unauthenticated) }
    }
}
