import XCTest
@testable import FiestaBoardDocuments

final class DraftTests: XCTestCase, @unchecked Sendable {
    private let raw = Data(#"{"name":"Original","id":"p","type":"template","template":["{{raw}}","two"],"line_metadata":[{"future":9223372036854775807123},{}],"null":null}"#.utf8)

    func testHistoryUndoRedoDirtyCheckpointAndFailedEdit() throws {
        var session = try DocumentEditingSession(data: raw)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(session.revision, 0)
        try session.setName("New")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(session.revision, 1)
        let saved = session.document
        session.markSaved(saved)
        XCTAssertFalse(session.hasUnsavedChanges)
        try session.replaceTemplateLine(at: 1, with: "three")
        XCTAssertEqual(session.revision, 2)
        try session.undo()
        XCTAssertEqual(session.document, saved)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertTrue(session.canRedo)
        try session.redo()
        XCTAssertEqual(session.document.templateLines, ["{{raw}}", "three"])
        let revision = session.revision
        XCTAssertThrowsError(try session.replaceTemplateLine(at: 1, with: "bad\nline"))
        XCTAssertEqual(session.revision, revision)
        try session.undo()
        try session.setName("Branch")
        XCTAssertFalse(session.canRedo)
    }

    func testNoOpDoesNotConsumeHistoryAndSaveDuringEditsStaysDirty() throws {
        var session = try DocumentEditingSession(data: raw)
        try session.setName("Original")
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(session.revision, 0)
        try session.setName("Captured")
        let captured = session.document
        try session.setName("Newer")
        session.markSaved(captured)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testAtomicDraftRoundTripAndDeploymentIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalDraftStore(directory: directory)
        let identity = DraftIdentity(deploymentID: "https://one.example/path", pageID: "../p")
        let other = DraftIdentity(deploymentID: "https://two.example/path", pageID: "../p")
        var session = try DocumentEditingSession(data: raw)
        try session.setName("Local")
        let snapshot = try session.snapshot(identity: identity)
        try await store.save(snapshot)
        let loaded = try await store.load(identity)
        guard case .recovered(let recovered) = loaded else { return XCTFail("expected draft") }
        XCTAssertEqual(recovered, snapshot)
        XCTAssertEqual(try PageDocument(data: recovered.documentData), session.document)
        let missing = try await store.load(other)
        guard case .absent = missing else { return XCTFail("deployments must not share drafts") }
        let filename = await store.fileURL(for: identity).lastPathComponent
        XCTAssertEqual(filename.count, 64 + ".json".count)
        XCTAssertFalse(filename.contains("example"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testExplicitRecoveryPreservesBaseAndRevisionAndCanUndo() throws {
        let identity = DraftIdentity(deploymentID: "one", pageID: "p")
        var previous = try DocumentEditingSession(data: raw)
        try previous.setName("Recovered")
        let snapshot = try previous.snapshot(identity: identity)
        var session = try DocumentEditingSession(data: Data(#"{"name":"Server changed","type":"template","template":["new"]}"#.utf8))
        let fetchedBaseline = session.baseline
        try session.recover(snapshot)
        XCTAssertEqual(session.document.name, "Recovered")
        XCTAssertEqual(session.baseline, previous.baseline)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertGreaterThan(session.revision, snapshot.revision)
        try session.undo()
        XCTAssertEqual(session.document.name, "Server changed")
        XCTAssertEqual(session.baseline, fetchedBaseline)
        XCTAssertTrue(session.hasUnsavedChanges)
        try session.redo()
        XCTAssertEqual(session.baseline, previous.baseline)
        XCTAssertEqual(session.document.name, "Recovered")
    }

    func testUndoRecoveryTracksBaselineEvenWhenContentIsIdentical() throws {
        let identity = DraftIdentity(deploymentID: "one", pageID: "p")
        var previous = try DocumentEditingSession(data: raw)
        try previous.setName("New")
        let snapshot = try previous.snapshot(identity: identity)
        var session = try DocumentEditingSession(data: snapshot.documentData)
        try session.recover(snapshot)
        XCTAssertFalse(session.hasUnsavedChanges)
        try session.undo()
        XCTAssertEqual(session.document, previous.document)
        XCTAssertTrue(session.hasUnsavedChanges, "Restoring a different base is a local draft change")
    }

    func testCorruptionIsReportedAndNeverSilentlyOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LocalDraftStore(directory: directory)
        let identity = DraftIdentity(deploymentID: "one", pageID: "p")
        let url = await store.fileURL(for: identity)
        let corruptBytes = Data("not json".utf8)
        try corruptBytes.write(to: url)
        let outcome = try await store.load(identity)
        guard case .corrupt(let issue) = outcome else { return XCTFail("expected explicit corruption") }
        XCTAssertEqual(issue.fileURL, url)
        let session = try DocumentEditingSession(data: raw)
        do {
            try await store.save(session.snapshot(identity: identity))
            XCTFail("must preserve corrupt file")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
        let preserved = try await store.quarantineCorruptDraft(identity)
        XCTAssertEqual(try Data(contentsOf: preserved), corruptBytes)
        try await store.save(session.snapshot(identity: identity))
    }

    func testWrongIdentityAndInvalidEmbeddedDocumentAreCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LocalDraftStore(directory: directory)
        let identity = DraftIdentity(deploymentID: "one", pageID: "p")
        let other = DraftIdentity(deploymentID: "other", pageID: "p")
        let snapshot = try DocumentEditingSession(data: raw).snapshot(identity: other)
        let bytes = try JSONEncoder().encode(snapshot)
        let url = await store.fileURL(for: identity)
        try bytes.write(to: url)
        guard case .corrupt = try await store.load(identity) else { return XCTFail("wrong identity") }
        let invalid = DraftSnapshot(identity: identity, revision: 1, baselineData: raw, documentData: Data("[]".utf8))
        do { try await store.save(invalid); XCTFail("invalid document") } catch {}
    }
}


extension DraftTests {
    func testScopedIdentityNeverAdoptsLegacyAndInventoryPreservesOriginalBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalDraftStore(directory: directory)
        let legacy = DraftIdentity(deploymentID: "https://board.test", pageID: "p")
        let scoped = DraftIdentity(deploymentID: "https://board.test", installationID: "install", connectionID: UUID(), pageID: "p")
        let snapshot = try DocumentEditingSession(data: raw).snapshot(identity: legacy)
        try await store.save(snapshot)
        let legacyURL = await store.fileURL(for: legacy)
        XCTAssertEqual(legacyURL.lastPathComponent, "40c7569e9f9494c4bd9a20d63e6b10f2bdd08ce552971678e003e5cb3f726808.json")
        let bytes = try Data(contentsOf: legacyURL)
        let scopedSnapshot = DraftSnapshot(identity: scoped, revision: 9, baselineData: raw, documentData: raw)
        try await store.save(scopedSnapshot)
        guard case .recovered(let recovered) = try await store.load(scoped) else { return XCTFail("v2 draft") }
        XCTAssertEqual(recovered.schemaVersion, 2)
        XCTAssertEqual(recovered.baselineData, raw)
        XCTAssertEqual(recovered.documentData, raw)
        // Remove only this test's scoped file before checking the legacy-only inventory.
        try FileManager.default.removeItem(at: await store.fileURL(for: scoped))
        let missing = try await store.load(scoped)
        XCTAssertEqual(missing, .absent)
        let entries = try await store.recoveryInventory()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.snapshot, snapshot)
        XCTAssertEqual(entries.first?.fileURL, legacyURL)
        XCTAssertEqual(try Data(contentsOf: legacyURL), bytes)
        let corruptURL = directory.appendingPathComponent("preserved.json")
        try Data("broken".utf8).write(to: corruptURL)
        let all = try await store.recoveryInventory()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.fileURL == corruptURL && $0.corruptionReason != nil })
    }

    func testScopedHashSeparatesInstallationConnectionFramingAndExactUnicode() async throws {
        let store = LocalDraftStore(directory: FileManager.default.temporaryDirectory)
        let connection = UUID()
        let values = [
            DraftIdentity(deploymentID: "a", installationID: "bc", connectionID: connection, pageID: "é"),
            DraftIdentity(deploymentID: "ab", installationID: "c", connectionID: connection, pageID: "é"),
            DraftIdentity(deploymentID: "a", installationID: "bc", connectionID: UUID(), pageID: "é"),
            DraftIdentity(deploymentID: "a", installationID: "bc", connectionID: connection, pageID: "e\u{301}"),
            DraftIdentity(deploymentID: "a", pageID: "é")
        ]
        var urls: Set<URL> = []
        for value in values { urls.insert(await store.fileURL(for: value)) }
        XCTAssertEqual(urls.count, values.count)
        XCTAssertEqual(Set(values).count, values.count)
    }
}
