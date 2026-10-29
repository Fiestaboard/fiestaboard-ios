import XCTest
@testable import FiestaBoardKit
final class CapabilityPolicyTests: XCTestCase {
    func testExactOperationEvidenceAndOptIn() {
        for operation in [BoardOperation.sendText, .selectPage, .restore, .scalarControls, .conditionalDefault] {
            XCTAssertTrue(CapabilityPolicy.allows(operation, version: "10.1.17", isDev: false, optedIn: true))
            XCTAssertTrue(CapabilityPolicy.allows(operation, version: "10.1.20", isDev: false, optedIn: true))
            for version: String? in [nil, "10.1.7", "10.1.18"] {
                XCTAssertFalse(CapabilityPolicy.allows(operation, version: version, isDev: false, optedIn: true))
            }
            XCTAssertFalse(CapabilityPolicy.allows(operation, version: "10.1.17", isDev: true, optedIn: true))
            XCTAssertFalse(CapabilityPolicy.allows(operation, version: "10.1.17", isDev: false, optedIn: false))
        }
        XCTAssertTrue(CapabilityPolicy.allows(.scalarControls, version: "10.0.0", isDev: false, optedIn: true))
        XCTAssertFalse(CapabilityPolicy.allows(.conditionalDefault, version: "10.0.0", isDev: false, optedIn: true))
    }
}
