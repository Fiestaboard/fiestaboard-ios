import XCTest
import FiestaBoardDocuments
@testable import FiestaBoardKit

final class ComposePageReceiptTests: XCTestCase {
    private func page(_ name: String) throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/operations-authenticated.json"))
        let corpus = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        return try XCTUnwrap((corpus["records"] as? [[String: Any]])?.first { $0["case"] as? String == name }?["response"] as? [String: Any])
    }
    private func request(_ geometry: ComposeGeometry, text: String = "KEEP EXACT\nSECOND") throws -> ComposeRequest {
        let deployment = try DeploymentURL("https://board.test")
        return ComposeRequest(principal: .init(deployment: deployment, installationID: "install", principalID: "verified-user", connectionID: UUID(), verifiedOnline: true),
            target: try BoardTarget(deployment: deployment, boardID: "target"), text: text,
            lineMetadata: [.init(alignment: "right", wrap: true), .init(alignment: "center", wrap: false)],
            geometry: geometry, duration: .minutes(120), silence: .hold)
    }
    func testActualCreateReadbacksPreserveFormattingAndEveryAuditedFamily() throws {
        for (suffix, geometry) in [("hall-1", ComposeGeometry.flagship), ("note-fixture", .note), ("tc001-fixture", .panel(rows: 1, cols: 8))] {
            let original = try page("created-readback-" + suffix), data = try JSONSerialization.data(withJSONObject: original)
            let receipt = try ComposePageReceipt(pageData: data, name: "Captured " + suffix, request: request(geometry))
            XCTAssertEqual(receipt.page.template, ["KEEP EXACT", "SECOND"]); XCTAssertEqual(receipt.pageData, data)
        }
    }
    func testChangedOrNormalizedContentNeverAcknowledgesCapturedPage() throws {
        let original = try page("created-readback-hall-1")
        for (field, value) in [("name", "Different" as Any), ("template", ["ALTERED", "SECOND"]),
                               ("line_metadata", [["alignment": "left", "wrap": false], ["alignment": "left", "wrap": false]]),
                               ("device_type", "note"), ("document_protocol", "future-v2")] {
            var changed = original; changed[field] = value
            XCTAssertThrowsError(try ComposePageReceipt(pageData: JSONSerialization.data(withJSONObject: changed), name: "Captured hall-1", request: request(.flagship)), field)
        }
        var normalized = original; normalized["template"] = ["caf\u{00e9}", "SECOND"]
        XCTAssertThrowsError(try ComposePageReceipt(pageData: JSONSerialization.data(withJSONObject: normalized), name: "Captured hall-1", request: request(.flagship, text: "cafe\u{0301}\nSECOND")))
    }
}
