import XCTest
import FiestaBoardKit

/// Exercises the real app-hosted Keychain, including simulator signing entitlements.
@MainActor
final class SessionVaultRuntimeTests: XCTestCase {
    func testRememberedSessionVaultRoundTrip() async throws {
        let vault = KeychainSessionVault(service: "cx-vault-test-" + UUID().uuidString)
        let deployment = try DeploymentURL("https://fixture.test/vault-runtime")
        let payload = Data("opaque-test-session".utf8)
        do {
            try await vault.save(payload, for: deployment)
            let restored = try await vault.load(for: deployment)
            XCTAssertEqual(restored, payload)
            try await vault.remove(for: deployment)
            let removed = try await vault.load(for: deployment)
            XCTAssertNil(removed)
        } catch {
            try? await vault.remove(for: deployment)
            throw error
        }
    }
}
