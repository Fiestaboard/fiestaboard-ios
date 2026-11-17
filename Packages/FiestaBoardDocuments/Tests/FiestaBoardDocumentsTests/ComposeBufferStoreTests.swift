import XCTest
@testable import FiestaBoardDocuments

final class ComposeBufferStoreTests: XCTestCase {
    private func identity(_ principal: String = "alex") -> ComposeBufferIdentity {
        ComposeBufferIdentity(deploymentID: "https://hub.example/api", installationID: "install-one", principalID: principal)
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cx-i8-compose-\(UUID())", isDirectory: true)
    }
    func testFreshStoreRestoresTextFormattingSelectionTargetAndDuration() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory)
        let scope = identity(), lease = try await store.open(scope)
        let snapshot = ComposeBufferSnapshot(identity: scope, revision: 1, text: "HELLO {{weather.temperature}}",
            targetID: "display-two", selection: .init(lowerUTF16: 6, upperUTF16: 29),
            lineMetadata: [.init(alignment: "center", wrap: false)], duration: .minutes(120))
        let saved = try await store.save(snapshot, using: lease)
        XCTAssertTrue(saved)
        let fresh = ComposeBufferStore(directory: directory)
        _ = try await fresh.open(scope)
        let restored = try await fresh.load(scope)
        XCTAssertEqual(restored, snapshot)
    }
    func testOtherVerifiedPrincipalOrInstallationNeverAdoptsBuffer() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "PRIVATE DRAFT"), using: lease)
        let otherUser = try await store.load(identity("jordan"))
        let otherInstall = try await store.load(.init(deploymentID: scope.deploymentID,
            installationID: "install-two", principalID: scope.principalID))
        XCTAssertNil(otherUser); XCTAssertNil(otherInstall)
    }
    func testNewerInputCannotBeOverwrittenByDelayedOlderSave() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope)
        let latest = try await store.save(.init(identity: scope, revision: 3, text: "LATEST"), using: lease)
        let older = try await store.save(.init(identity: scope, revision: 2, text: "OLDER"), using: lease)
        let restored = try await store.load(scope)
        XCTAssertTrue(latest); XCTAssertFalse(older); XCTAssertEqual(restored?.text, "LATEST")
    }
    func testRemovalRevokesPendingWriterAndDoesNotResurrectAfterRelaunch() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "SENT"), using: lease)
        let removed = try await store.remove(using: lease)
        let late = try await store.save(.init(identity: scope, revision: 2, text: "SENT"), using: lease)
        let fresh = ComposeBufferStore(directory: directory)
        _ = try await fresh.open(scope)
        let restored = try await fresh.load(scope)
        XCTAssertTrue(removed); XCTAssertFalse(late); XCTAssertNil(restored)
    }
    func testFreshLeaseAlsoRevokesWriterFromPreviousStoreInstance() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = ComposeBufferStore(directory: directory), scope = identity()
        let staleLease = try await first.open(scope)
        let second = ComposeBufferStore(directory: directory)
        let currentLease = try await second.open(scope)
        _ = try await second.save(.init(identity: scope, revision: 1, text: "CURRENT"), using: currentLease)
        let stale = try await first.save(.init(identity: scope, revision: 2, text: "STALE"), using: staleLease)
        let restored = try await second.load(scope)
        XCTAssertFalse(stale); XCTAssertEqual(restored?.text, "CURRENT")
    }
    func testCorruptDraftIsPreservedAndNeverSilentlyOverwritten() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope), url = await store.fileURL(for: scope)
        let damaged = Data("{saved-user-text:damaged}".utf8)
        try damaged.write(to: url)
        do { _ = try await store.load(scope); XCTFail("Expected corruption") } catch {}
        do { _ = try await store.save(.init(identity: scope, revision: 2, text: "NEW"), using: lease); XCTFail("Expected preservation") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }
    func testExpiredAbsoluteEndIsRetainedRatherThanConvertedToIndefinite() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope), end = Date(timeIntervalSince1970: 1234)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "KEPT", duration: .until(end)), using: lease)
        let restored = try await store.load(scope)
        XCTAssertEqual(restored?.duration, .until(end))
    }
}

extension ComposeBufferStoreTests {
    func testAcknowledgedOlderSendCannotClearNewerTyping() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "SENDING"), using: lease)
        _ = try await store.save(.init(identity: scope, revision: 2, text: "NEW TYPING"), using: lease)
        let removed = try await store.remove(using: lease, matchingRevision: 1)
        let retained = try await store.load(scope)
        XCTAssertFalse(removed); XCTAssertEqual(retained?.text, "NEW TYPING")
    }
}

extension ComposeBufferStoreTests {
    func testConcurrentStoreInstancesRetainHighestRevision() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = ComposeBufferStore(directory: directory), second = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await first.open(scope)
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            for revision in 1...100 {
                tasks.addTask {
                    let writer = revision.isMultiple(of: 2) ? first : second
                    _ = try await writer.save(.init(identity: scope, revision: UInt64(revision), text: "DRAFT \(revision)"), using: lease)
                }
            }
            try await tasks.waitForAll()
        }
        let restored = try await first.load(scope)
        XCTAssertEqual(restored?.revision, 100)
        XCTAssertEqual(restored?.text, "DRAFT 100")
    }
}
