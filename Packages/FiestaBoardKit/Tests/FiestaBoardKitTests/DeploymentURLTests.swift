import XCTest
@testable import FiestaBoardKit

final class DeploymentURLTests: XCTestCase {
    func testNormalizesIdentityAndPreservesPrefixPortAndIPv6() throws {
        let url = try DeploymentURL(" HTTPS://Board.Example:8443/fiesta/ ")
        XCTAssertEqual(url.description, "https://board.example:8443/fiesta")
        XCTAssertEqual(try url.apiURL(["v1", "boards", "board-2"]).absoluteString,
                       "https://board.example:8443/fiesta/api/v1/boards/board-2")
        let v6 = try DeploymentURL("http://[::1]:4420/prefix/", allowLocalHTTP: true)
        XCTAssertEqual(try v6.apiURL(["auth", "status"]).absoluteString,
                       "http://[::1]:4420/prefix/api/auth/status")
        XCTAssertNotEqual(url, try DeploymentURL("https://board.example:8443/other"))
    }

    func testRejectsCredentialsTraversalEscapesQueriesAndRemoteHTTP() {
        for input in ["https://user:password@example.com", "https://example.com/a/../b",
                      "https://example.com/%2e%2e", "https://example.com/%252e%252e",
                      "https://example.com/a%2fb", "https://example.com/a\\b", "https://example.com/?token=secret",
                      "https://example.com/#fragment", "ftp://example.com", "http://example.com",
                      "http://example.com.evil.localhost", "http://8.8.8.8"] {
            XCTAssertThrowsError(try DeploymentURL(input, allowLocalHTTP: true), input)
        }
    }

    func testLocalHTTPRequiresExplicitOptInAndPrivateScope() throws {
        for host in ["localhost", "127.0.0.1", "192.168.1.10", "10.0.0.5", "172.16.3.2", "board.local", "[fd12::1]"] {
            XCTAssertThrowsError(try DeploymentURL("http://\(host):4420"))
            XCTAssertNoThrow(try DeploymentURL("http://\(host):4420", allowLocalHTTP: true))
        }
        XCTAssertThrowsError(try DeploymentURL("http://172.32.0.1", allowLocalHTTP: true))
    }

    func testAPIPathsCannotEscapeDeploymentScope() throws {
        let url = try DeploymentURL("https://example.com/prefix")
        for segment in ["..", ".", "a/b", "%2f", "?x", "", "https://evil.test"] {
            XCTAssertThrowsError(try url.apiURL([segment]))
        }
    }
}
