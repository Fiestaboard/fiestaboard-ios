import XCTest
@testable import FiestaBoardKit

final class ServerAddressTests: XCTestCase {
    func testPastedBareAddressRequiresDeliberateLocalHTTPChoice() throws {
        XCTAssertEqual(try ServerAddress.parse(" fiestapi.local:4420 \n").description, "https://fiestapi.local:4420")
        XCTAssertEqual(try ServerAddress.parse("fiestapi.local:4420", allowLocalHTTP: true).description, "http://fiestapi.local:4420")
        XCTAssertEqual(try ServerAddress.parse("[fd00::1]:4420", allowLocalHTTP: true).description, "http://[fd00::1]:4420")
        XCTAssertEqual(try ServerAddress.parse("https://BOARD.test/proxy/", allowLocalHTTP: true).description, "https://board.test/proxy")
    }
    func testUnsafeAddressesAndBadExplicitSchemesNeverBecomeHostnames() {
        for address in ["ftp://board.local", "https:/board.local", "http:board.local", "https://name:secret@board.test", "board.local/a/../b", "board.local?secret=x", "http://example.com", "javascript:alert(1)"] {
            XCTAssertThrowsError(try ServerAddress.parse(address, allowLocalHTTP: true), address)
        }
    }
}
