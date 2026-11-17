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


extension ComposeBufferStoreTests {
    func testExplicitSilenceConsentSurvivesFreshOfflineStoreAndLegacyDefaultsToHold() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity()
        let lease = try await store.open(scope)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "QUIET", silence: .override), using: lease)
        let fresh = ComposeBufferStore(directory: directory)
        let restored = try await fresh.load(scope)
        XCTAssertEqual(restored?.silence, .override)
        let url = await store.fileURL(for: scope)
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var snapshot = envelope["snapshot"] as! [String: Any]
        snapshot.removeValue(forKey: "silence"); envelope["snapshot"] = snapshot
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        let legacy = try await fresh.load(scope)
        XCTAssertEqual(legacy?.silence, .hold, "Old drafts never invent silence override consent")
    }
}

extension ComposeBufferStoreTests {
    func testColdOfflineBufferRetainsBoundedTargetPresentationBeyondShellCacheLifetime() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity(), lease = try await store.open(scope)
        let target = ComposeBufferTarget(id: "led-two", name: "Entry clock", deviceType: "panel", rows: 1, cols: 8,
            deviceModel: "tc001", charset: "led_rgb", drawingData: Data(#"{"source":"device","technology":"led_matrix","pixel_width":32,"pixel_height":8,"font":"3x5"}"#.utf8))
        _ = try await store.save(.init(identity: scope, revision: 1, text: "FULL UNTRUNCATED DRAFT", targetID: "led-two",
            targetPresentation: target, preview: .init(targetID: "led-two", inputDigest: "captured", responseData: Data("last-known-result".utf8), capturedAt: Date(timeIntervalSince1970: 1))), using: lease)
        let restored = try await ComposeBufferStore(directory: directory).load(scope)
        XCTAssertEqual(restored?.text, "FULL UNTRUNCATED DRAFT")
        XCTAssertEqual(restored?.targetPresentation, target)
        XCTAssertEqual(restored?.preview?.capturedAt, Date(timeIntervalSince1970: 1), "Authoring context never inherits the shell's600s expiration")
    }
    func testMismatchedOrUnboundedTargetPresentationCannotReplaceSavedDraft() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ComposeBufferStore(directory: directory), scope = identity(), lease = try await store.open(scope)
        _ = try await store.save(.init(identity: scope, revision: 1, text: "PRESERVED", targetID: "known"), using: lease)
        for target in [ComposeBufferTarget(id: "other", name: "Wrong", deviceType: "panel", rows: 1, cols: 8),
                       ComposeBufferTarget(id: "known", name: "Bad", deviceType: "panel", rows: 0, cols: 8),
                       ComposeBufferTarget(id: "known", name: "Huge", deviceType: "panel", rows: 1, cols: Int.max)] {
            do { _ = try await store.save(.init(identity: scope, revision: 2, text: "INVALID", targetID: "known", targetPresentation: target), using: lease); XCTFail("Invalid target cannot replace the draft") }
            catch { XCTAssertEqual(error as? ComposeBufferError, .invalidContent) }
        }
        let retained = try await store.load(scope)
        XCTAssertEqual(retained?.text, "PRESERVED")
    }
}
