import XCTest
import CryptoKit
import FiestaBoardKit
@testable import FiestaBoardEditorState

@MainActor final class CollectionRecoveryTests: XCTestCase {
    private var directory: URL!
    private var archive: CollectionDraftArchive!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        archive = CollectionDraftArchive(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private var identity: CollectionDraftIdentity {
        .init(deploymentID: "https://example.test", installationID: "recovery-fixture", connectionID: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!, collectionID: nil)
    }
    private func checkpoint(_ id: UUID = UUID()) -> CollectionDraftCheckpoint {
        var draft = CollectionDraft(collection: nil); draft.name = "Owned draft"; draft.intervalText = "-"
        return .init(id: id, identity: identity, baseline: nil, draft: draft, sourceSupportsEditing: true, status: .unknownOutcome)
    }
    private func write(_ object: [String: Any], id: UUID) throws -> URL {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
        return url
    }
    func testInventoryIncludesScopedLegacyFutureMalformedAndRetiredOriginalBytesWithoutMutation() throws {
        let scoped = checkpoint(), retired = checkpoint()
        try archive.save(scoped)
        let retiredVersion = try archive.save(retired)
        try archive.retire([retiredVersion], identity: identity)
        let legacyID = UUID()
        try archive.save(.init(id: legacyID, deploymentID: identity.deploymentID, collectionID: nil, baseline: nil, draft: scoped.draft, sourceSupportsEditing: true, status: .idle))
        let futureID = UUID()
        var future = try JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint(futureID))) as! [String: Any]
        future["formatVersion"] = 99
        _ = try write(future, id: futureID)
        let malformed = directory.appendingPathComponent("broken-original.json")
        try Data([0xff, 0x00, 0x7b]).write(to: malformed)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        let markerFiles = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("retired"), includingPropertiesForKeys: nil)
        let before = try Dictionary(uniqueKeysWithValues: (files + markerFiles).map { ($0, try Data(contentsOf: $0)) })
        let entries = try archive.recoveryInventory()
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(Set(entries.map(\.classification)), [.scoped, .retired, .unassigned, .future, .malformed])
        XCTAssertEqual(Set(entries.map(\.fileURL)), Set(files)); XCTAssertEqual(Set(entries.map(\.id)), Set(files))
        XCTAssertNil(entries.first { $0.fileURL.lastPathComponent == futureID.uuidString + ".json" }?.checkpoint)
        XCTAssertNil(entries.first { $0.fileURL == malformed }?.checkpoint)
        XCTAssertEqual(entries.first { $0.classification == .scoped }?.checkpoint?.draft.intervalText, "-")
        XCTAssertEqual(entries.first { $0.classification == .scoped }?.checkpoint?.status, .unknownOutcome)
        for (url, bytes) in before { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        XCTAssertEqual(try archive.load(identity: identity).map(\.id), [scoped.id])
        XCTAssertEqual(try archive.recoveryInventory().map(\.id), entries.map(\.id))
    }
    func testIdentityMismatchAndMalformedScopeAreUntrustedNotScoped() throws {
        let saved = checkpoint(); try archive.save(saved)
        let source = directory.appendingPathComponent(saved.id.uuidString + ".json")
        let renamed = directory.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.moveItem(at: source, to: renamed)
        let malformedID = UUID()
        var malformed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint(malformedID))) as! [String: Any]
        var scope = malformed["identity"] as! [String: Any]; scope["installationID"] = ""; malformed["identity"] = scope
        _ = try write(malformed, id: malformedID)
        let entries = try archive.recoveryInventory()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.classification == .untrusted && $0.checkpoint == nil && !$0.reason.isEmpty })
        XCTAssertTrue(try archive.load(identity: identity).isEmpty)
    }
    func testUnreadableOriginalHasExplicitEntryAndRetirementMetadataIsExcluded() throws {
        let unreadable = directory.appendingPathComponent("unreadable.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
        let retired = directory.appendingPathComponent("retired", isDirectory: true)
        try FileManager.default.createDirectory(at: retired, withIntermediateDirectories: false)
        try Data("marker".utf8).write(to: retired.appendingPathComponent("arbitrary.marker"))
        let entries = try archive.recoveryInventory()
        XCTAssertEqual(entries.count, 1); XCTAssertEqual(entries.first?.fileURL.resolvingSymlinksInPath(), unreadable.resolvingSymlinksInPath())
        XCTAssertEqual(entries.first?.classification, .unreadable); XCTAssertNil(entries.first?.checkpoint)
        XCTAssertFalse(entries.first?.reason.isEmpty ?? true)
    }
    func testUnsupportedBaselineRemainsReadOnlyInInventory() throws {
        let baseline = try JSONDecoder().decode(PageCollection.self, from: Data(#"{"id":"c","name":"Read only","page_ids":["a"],"selection_mode":"time","time":{"interval_seconds":30},"revision":"original","edit_protocol":"collection-revision-v1","future_setting":true}"#.utf8))
        let owned = identity.assigningCollectionID("c")
        try archive.save(.init(id: UUID(), identity: owned, baseline: baseline, draft: CollectionDraft(collection: baseline), sourceSupportsEditing: true, status: .idle))
        let entry = try XCTUnwrap(archive.recoveryInventory().first)
        XCTAssertEqual(entry.classification, .scoped)
        XCTAssertEqual(entry.checkpoint?.sourceSupportsEditing, false)
        XCTAssertEqual(entry.checkpoint?.baseline?.revision, "original")
    }
    func testCheckedInSyntheticOriginalsMatchManifestAndInventoryExportsTheirExactFiles() throws {
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/CollectionRecovery")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("manifest.json"))) as! [String: Any]
        let specifications = manifest["files"] as! [[String: Any]]
        XCTAssertEqual(specifications.count, 3)
        for specification in specifications {
            let filename = specification["filename"] as! String
            let data = try Data(contentsOf: fixture.appendingPathComponent("originals").appendingPathComponent(filename))
            XCTAssertEqual(data.count, specification["bytes"] as? Int)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), specification["sha256"] as? String)
            try data.write(to: directory.appendingPathComponent(filename))
        }
        let entries = try archive.recoveryInventory()
        XCTAssertEqual(entries.count, 3)
        for specification in specifications {
            let filename = specification["filename"] as! String
            let entry = try XCTUnwrap(entries.first { $0.fileURL.lastPathComponent == filename })
            XCTAssertEqual(entry.classification.rawValue, specification["classification"] as? String)
            XCTAssertEqual(try Data(contentsOf: entry.fileURL), try Data(contentsOf: fixture.appendingPathComponent("originals").appendingPathComponent(filename)))
        }
        XCTAssertTrue(try archive.load(identity: identity).isEmpty)
    }
    func testMissingStoreRemainsAbsentAndStoreEnumerationFailuresPropagate() throws {
        let missing = directory.appendingPathComponent("not-created")
        XCTAssertTrue(try CollectionDraftArchive(directory: missing).recoveryInventory().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let unavailable = directory.appendingPathComponent("not-a-directory")
        let original = Data("original inaccessible-store fixture".utf8)
        try original.write(to: unavailable)
        XCTAssertThrowsError(try CollectionDraftArchive(directory: unavailable).recoveryInventory())
        XCTAssertEqual(try Data(contentsOf: unavailable), original)
    }

}
