import XCTest
@testable import FiestaBoardDocuments

final class UnicodeTests: XCTestCase, @unchecked Sendable {
    private let composed = "\u{00e9}"
    private let decomposed = "e\u{0301}"

    func testRawTemplateNormalizationEditSurvivesDirtyUndoRedoAndPatch() throws {
        let raw = Data(#"{"name":"Original","type":"template","template":["{{\u00e9}}"],"line_metadata":[{"alignment":"center","future":12345678901234567890}]}"#.utf8)
        var session = try DocumentEditingSession(data: raw)
        let initial = session.document
        let edited = "{{\(decomposed)}}"
        try session.replaceTemplateLine(at: 0, with: edited)
        XCTAssertEqual(Array(session.document.templateLines![0].utf8), Array(edited.utf8))
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(session.canUndo)
        XCTAssertEqual(session.revision, 1)
        guard case .object(let fields) = try session.document.changedFields(from: initial) else { return XCTFail() }
        XCTAssertEqual(Set(fields.keys), ["template"])
        XCTAssertEqual(session.document.root["line_metadata"], initial.root["line_metadata"])
        let roundTrip = try PageDocument(data: session.document.serializedData())
        XCTAssertEqual(Array(roundTrip.templateLines![0].utf8), Array(edited.utf8))
        try session.undo()
        XCTAssertEqual(Array(session.document.templateLines![0].utf8), Array("{{\(composed)}}".utf8))
        XCTAssertFalse(session.hasUnsavedChanges)
        try session.redo()
        XCTAssertEqual(Array(session.document.templateLines![0].utf8), Array(edited.utf8))
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testNameNormalizationEditAndSavedCheckpointAreScalarExact() throws {
        var session = try DocumentEditingSession(data: Data(#"{"name":"\u00e9","type":"single"}"#.utf8))
        let original = session.document
        try session.setName(decomposed)
        XCTAssertEqual(Array(session.document.name!.utf8), Array(decomposed.utf8))
        XCTAssertEqual(session.revision, 1)
        XCTAssertTrue(session.hasUnsavedChanges)
        guard case .object(let fields) = try session.document.changedFields(from: original) else { return XCTFail() }
        XCTAssertEqual(Set(fields.keys), ["name"])
        session.markSaved(session.document)
        XCTAssertFalse(session.hasUnsavedChanges)
        try session.undo()
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(Array(session.document.name!.utf8), Array(composed.utf8))
    }

    func testDistinctScalarKeysRemainAddressableThroughNestedRoundTripAndEdits() throws {
        let raw = Data(#"{"name":"Page","type":"template","template":["{{raw}}"],"\u00e9":{"e\u0301":"first","\u00e9":"second"},"e\u0301":922337203685477580812345}"#.utf8)
        var document = try PageDocument(data: raw)
        XCTAssertEqual(document.root.count, 5)
        XCTAssertEqual(document.root[decomposed], .number("922337203685477580812345"))
        guard case .object(let nested) = document.root[composed] else { return XCTFail("missing composed key") }
        XCTAssertEqual(nested.count, 2)
        XCTAssertEqual(nested[decomposed], .string("first"))
        XCTAssertEqual(nested[composed], .string("second"))
        let baseline = document
        try document.setName("Changed")
        try document.replaceTemplateLine(at: 0, with: "{{\(decomposed)}}")
        let roundTrip = try PageDocument(data: document.serializedData())
        XCTAssertEqual(roundTrip.root[composed], baseline.root[composed])
        XCTAssertEqual(roundTrip.root[decomposed], baseline.root[decomposed])
        XCTAssertEqual(roundTrip, document)
    }

    func testDecodedDuplicateKeysAreStillRejectedAndStringEscapesAreEquivalent() throws {
        for raw in [#"{"é":1,"\u00e9":2}"#, #"{"é":1,"e\u0301":2}"#] {
            XCTAssertThrowsError(try LosslessJSON.parse(Data(raw.utf8)))
        }
        XCTAssertEqual(try LosslessJSON.parse(Data(#""\u00e9""#.utf8)), .string(composed))
        XCTAssertNotEqual(LosslessJSON.string(composed), .string(decomposed))
        XCTAssertNotEqual(LosslessJSON.array([.string(composed)]), .array([.string(decomposed)]))
        XCTAssertNotEqual(LosslessJSON.object([composed: .bool(true)]), .object([decomposed: .bool(true)]))
    }

    func testObjectLiteralAndMutationKeepScalarDistinctKeysSeparate() throws {
        var object: LosslessJSONObject = [composed: .string("one"), decomposed: .string("two")]
        XCTAssertEqual(object.count, 2)
        let baseline = try PageDocument(data: LosslessJSON.object(object).serializedData())
        object[composed] = .string("changed")
        XCTAssertEqual(object[composed], .string("changed"))
        XCTAssertEqual(object[decomposed], .string("two"))
        let value = LosslessJSON.object(object)
        XCTAssertEqual(try LosslessJSON.parse(value.serializedData()), value)
        let edited = try PageDocument(data: value.serializedData())
        guard case .object(let fields) = try edited.changedFields(from: baseline) else { return XCTFail() }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields[composed], .string("changed"))
        XCTAssertNil(fields[decomposed])
        object[composed] = nil
        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object[decomposed], .string("two"))
        XCTAssertNil(object[composed])
    }

    func testScalarDistinctKeyRenameRequiresDeletionPolicyRatherThanEmptyPatch() throws {
        let before = try PageDocument(data: Data(#"{"name":"Page","\u00e9":1}"#.utf8))
        let after = try PageDocument(data: Data(#"{"name":"Page","e\u0301":1}"#.utf8))
        XCTAssertThrowsError(try after.changedFields(from: before))
    }

    func testDraftIdentityUsesExactScalarsForEqualityAndHashCollections() {
        let original = DraftIdentity(deploymentID: composed, pageID: composed)
        let otherDeployment = DraftIdentity(deploymentID: decomposed, pageID: composed)
        let otherPage = DraftIdentity(deploymentID: composed, pageID: decomposed)
        XCTAssertNotEqual(original, otherDeployment)
        XCTAssertNotEqual(original, otherPage)
        XCTAssertEqual(Set([original, otherDeployment, otherPage]).count, 3)
        XCTAssertEqual(original, DraftIdentity(deploymentID: composed, pageID: composed))
    }

    func testCanonicallyEquivalentWrongDraftIdentityIsCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LocalDraftStore(directory: directory)
        let expected = DraftIdentity(deploymentID: composed, pageID: composed)
        let wrongIdentities = [
            DraftIdentity(deploymentID: decomposed, pageID: composed),
            DraftIdentity(deploymentID: composed, pageID: decomposed)
        ]
        let session = try DocumentEditingSession(data: Data(#"{"name":"Page"}"#.utf8))
        let expectedURL = await store.fileURL(for: expected)
        for wrong in wrongIdentities {
            let wrongURL = await store.fileURL(for: wrong)
            XCTAssertNotEqual(expectedURL.lastPathComponent, wrongURL.lastPathComponent)
            try JSONEncoder().encode(session.snapshot(identity: wrong)).write(to: expectedURL)
            guard case .corrupt = try await store.load(expected) else {
                XCTFail("Must reject scalar-distinct identity even when canonically equivalent")
                continue
            }
        }
    }
}
