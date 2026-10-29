import Foundation
import XCTest
@testable import FiestaBoardKit

@MainActor
final class ServerCatalogTests: XCTestCase {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testMissingCatalogAndNormalizedUpsertPersistStableIDAndMetadata() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = ServerCatalog(directory: directory)
        let empty = try await catalog.list()
        XCTAssertTrue(empty.isEmpty)
        let first = SavedServer(deployment: try DeploymentURL("https://BOARD.test/prefix/"), alias: "Kitchen", installationID: "one")
        _ = try await catalog.upsert(first)
        let replacement = SavedServer(deployment: try DeploymentURL("https://board.test/prefix"), alias: "Hall", installationID: "one", preferredBoardID: "board-2")
        let canonical = try await catalog.upsert(replacement)
        XCTAssertEqual(canonical.id, first.id)
        let records = try await ServerCatalog(directory: directory).list()
        XCTAssertEqual(records, [canonical])
        XCTAssertEqual(records.first?.alias, "Hall")
        XCTAssertEqual(records.first?.preferredBoardID, "board-2")
        let serialized = try String(contentsOf: directory.appendingPathComponent("servers.json"), encoding: .utf8)
        let keys = Set((try JSONSerialization.jsonObject(with: Data(serialized.utf8)) as! [[String: Any]])[0].keys)
        XCTAssertEqual(keys, ["id", "deployment", "alias", "installationID", "preferredBoardID"])
        try await catalog.remove(id: canonical.id)
        let removed = try await catalog.list()
        XCTAssertTrue(removed.isEmpty)
    }
    func testChangedKnownIdentityCannotOverwriteAndFullDeploymentsStayDistinct() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = ServerCatalog(directory: directory)
        let first = SavedServer(deployment: try DeploymentURL("https://board.test"), alias: "Original", installationID: "one")
        _ = try await catalog.upsert(first)
        do {
            _ = try await catalog.upsert(SavedServer(deployment: first.deployment, alias: "Changed", installationID: "two"))
            XCTFail("Expected identity change")
        } catch let error as ServerCatalogError {
            guard case .identityChanged(let existing, let proposed) = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(existing, first)
            XCTAssertEqual(proposed.installationID, "two")
        }
        for address in ["https://board.test:443", "https://board.test/prefix", "http://board.local"] {
            _ = try await catalog.upsert(SavedServer(deployment: try DeploymentURL(address, allowLocalHTTP: true), alias: address))
        }
        let records = try await catalog.list()
        XCTAssertEqual(records.count, 4)
        XCTAssertEqual(records.first, first)
    }
    func testEditByIDMovesAddressWithoutDuplicatingAndPreservesKnownIdentityWhenOmitted() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = ServerCatalog(directory: directory)
        let first = SavedServer(deployment: try DeploymentURL("https://board.test"), alias: "Before", installationID: "one")
        _ = try await catalog.upsert(first)
        let omitted = try await catalog.upsert(SavedServer(id: first.id, deployment: first.deployment, alias: "Still associated", installationID: ""))
        XCTAssertEqual(omitted.installationID, "one")
        let edited = try await catalog.upsert(SavedServer(id: first.id, deployment: try DeploymentURL("https://new.test"), alias: "After"))
        XCTAssertEqual(edited.installationID, "one")
        let records = try await catalog.list()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.deployment.description, "https://new.test")
    }
    func testCorruptAndUnwritableCatalogSurfaceTypedErrors() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("servers.json"))
        do { _ = try await ServerCatalog(directory: directory).list(); XCTFail("Expected corrupt catalog") }
        catch { XCTAssertEqual(error as? ServerCatalogError, .corrupt) }
        let blocked = directory.appendingPathComponent("file")
        try Data().write(to: blocked)
        do {
            _ = try await ServerCatalog(directory: blocked).upsert(SavedServer(deployment: try DeploymentURL("https://board.test"), alias: "Board"))
            XCTFail("Expected storage failure")
        } catch { guard case .storage = error as? ServerCatalogError else { return XCTFail("Wrong error: \(error)") } }
    }
}
