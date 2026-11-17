import Foundation
import XCTest
@testable import FiestaBoardKit

@MainActor final class ShellSnapshotStoreTests: XCTestCase {
    func testFreshSnapshotSurvivesStoreRelaunchAndExpiresAtTenMinutes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = SavedServer(deployment: try DeploymentURL("https://hub.example/prefix"), alias: "Hub", installationID: "one")
        let store = ShellSnapshotStore(directory: directory)
        let lease = try await store.beginSession(for: hub)
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(timeIntervalSince1970: 1000), board: nil, displayName: "Kitchen", pages: [.init(id: "page", name: "Hello")])
        let written = try await store.write(snapshot, lease: lease)
        XCTAssertTrue(written)
        let reopened = ShellSnapshotStore(directory: directory)
        let fresh = try await reopened.read(for: hub, at: Date(timeIntervalSince1970: 1599))
        XCTAssertEqual(fresh?.displayName, "Kitchen")
        XCTAssertEqual(fresh?.pages.first?.name, "Hello")
        let expired = try await reopened.read(for: hub, at: Date(timeIntervalSince1970: 1600))
        XCTAssertNil(expired)
    }
    func testSnapshotCannotCrossAddressInstallationOrRevokedLease() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = SavedServer(deployment: try DeploymentURL("https://a.example"), alias: "A", installationID: "one")
        let store = ShellSnapshotStore(directory: directory)
        let lease = try await store.beginSession(for: hub)
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(timeIntervalSince1970: 1000), board: nil, displayName: "A", pages: [])
        _ = try await store.write(snapshot, lease: lease)
        var changed = hub; changed.installationID = "two"
        let otherInstallation = try await store.read(for: changed, at: Date(timeIntervalSince1970: 1001))
        XCTAssertNil(otherInstallation)
        changed = hub; changed.deployment = try DeploymentURL("https://b.example")
        let otherAddress = try await store.read(for: changed, at: Date(timeIntervalSince1970: 1001))
        XCTAssertNil(otherAddress)
        try await store.remove(hub)
        let staleWrite = try await store.write(snapshot, lease: lease)
        XCTAssertFalse(staleWrite)
        let removed = try await ShellSnapshotStore(directory: directory).read(for: hub, at: Date(timeIntervalSince1970: 1001))
        XCTAssertNil(removed)
    }
}
