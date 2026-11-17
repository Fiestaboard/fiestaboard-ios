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
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(#"{"id":"display","name":"Kitchen","rows":1,"cols":2,"device_type":"flagship","is_primary":true,"schedule_enabled":false,"paused":false,"output":"vestaboard","charset":"vestaboard_v1","source":"manual","text":"HI"}"#.utf8))
        let snapshot = ShellSnapshot(hub: hub, capturedAt: Date(timeIntervalSince1970: 1000), board: detail, displayName: "Kitchen", pages: [.init(id: "page", name: "Hello")])
        let written = try await store.write(snapshot, lease: lease)
        XCTAssertTrue(written)
        let reopened = ShellSnapshotStore(directory: directory)
        let fresh = try await reopened.read(for: hub, at: Date(timeIntervalSince1970: 1599))
        XCTAssertEqual(fresh?.displayName, "Kitchen")
        XCTAssertEqual(fresh?.pages.first?.name, "Hello")
        XCTAssertEqual(fresh?.board?.text, "HI")
        let encoded = try Data(contentsOf: directory.appendingPathComponent(hub.id.uuidString + ".json"))
        let keys = Set((try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys)
        XCTAssertEqual(keys, ["version", "hubID", "deployment", "installationID", "capturedAt", "board", "displayName", "pages"])
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
    func testInvalidGeometryCannotBeWrittenOrReadFromPersistedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hub = SavedServer(deployment: try DeploymentURL("https://hub.example"), alias: "Hub", installationID: "one")
        let store = ShellSnapshotStore(directory: directory)
        let lease = try await store.beginSession(for: hub)
        let base: [String: Any] = ["id": "display", "name": "Kitchen", "rows": 1, "cols": 2, "device_type": "flagship", "is_primary": true,
                                   "schedule_enabled": false, "paused": false, "output": "vestaboard", "source": "manual"]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(hub.id.uuidString + ".json")
        for patch in [["rows": 999999], ["cols": 999999], ["characters": [[1]]], ["source": "unknown"]] as [[String: Any]] {
            let object = base.merging(patch) { _, replacement in replacement }
            let invalidBoard = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: object))
            let invalid = ShellSnapshot(hub: hub, capturedAt: Date(timeIntervalSince1970: 1000), board: invalidBoard, displayName: "Kitchen", pages: [])
            do { _ = try await store.write(invalid, lease: lease); XCTFail("Invalid cached payload must not bypass live validation: \(patch)") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
            try JSONEncoder().encode(invalid).write(to: file)
            do { _ = try await store.read(for: hub, at: Date(timeIntervalSince1970: 1001)); XCTFail("Persisted payload must be validated again: \(patch)") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidResponse) }
        }
        try Data("{}".utf8).write(to: file)
        let corrupt = try await store.read(for: hub, at: Date(timeIntervalSince1970: 1001))
        XCTAssertNil(corrupt)
    }

}
