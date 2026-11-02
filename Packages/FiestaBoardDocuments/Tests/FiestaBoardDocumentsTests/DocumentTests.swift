import XCTest
@testable import FiestaBoardDocuments

final class DocumentTests: XCTestCase {
    private let raw = #"{"id":"p","name":"Original","type":"template","device_type":"panel","grid_rows":12,"grid_cols":64,"template":["{red}{{weather.temp}}","{% if x %}OK{% endif %}"],"line_metadata":[{"alignment":"center","wrap":true,"future":null},{"alignment":"right","wrap":false}],"canvases":[{"id":"art","area":{"row":1,"col":2,"rows":4,"cols":8},"layers":[{"future":[null,9223372036854775807123456789,0.123456789012345678901234567890,1.234567890123456789e+250]}]}],"transition_strategy":"plugin:future","transition_interval_ms":null,"unknown":{"nested":{"flag":true}}}"#

    func testRoundTripPreservesEveryNodeAndNumberToken() throws {
        let source = Data(raw.utf8)
        let json = try LosslessJSON.parse(source)
        let roundTrip = try LosslessJSON.parse(json.serializedData())
        XCTAssertEqual(json, roundTrip)
        let output = String(decoding: try json.serializedData(), as: UTF8.self)
        for token in ["9223372036854775807123456789", "0.123456789012345678901234567890", "1.234567890123456789e+250"] {
            XCTAssertTrue(output.contains(token), token)
        }
    }

    func testNameAndSingleSlotPatchPreserveMetadataAndUnknownNodes() throws {
        let baseline = try PageDocument(data: Data(raw.utf8))
        var changed = baseline
        try changed.setName("Edited")
        try changed.replaceTemplateLine(at: 1, with: "{{new_variable}} {blue}")
        let patch = try changed.changedFields(from: baseline)
        guard case .object(let fields) = patch else { return XCTFail("patch object") }
        XCTAssertEqual(Set(fields.keys), ["name", "template"])
        XCTAssertEqual(changed.root["line_metadata"], baseline.root["line_metadata"])
        XCTAssertEqual(changed.root["canvases"], baseline.root["canvases"])
        XCTAssertEqual(changed.root["transition_interval_ms"], .null)
        XCTAssertNil(changed.root["updated_at"])
        XCTAssertEqual(try PageDocument(data: changed.serializedData()), changed)
    }

    func testOmissionAndNullRemainDistinctAcrossAllPageTypes() throws {
        for type in ["single", "composite", "template", "future"] {
            let bytes = Data("{\"type\":\"\(type)\",\"explicit\":null,\"unknown\":[false,{\"value\":-0.0000e-999}]}".utf8)
            let document = try PageDocument(data: bytes)
            XCTAssertEqual(document.root["explicit"], .null)
            XCTAssertNil(document.root["omitted"])
            XCTAssertEqual(try PageDocument(data: document.serializedData()), document)
        }
    }

    func testStrictJSONRejectsMalformedOrAmbiguousDocuments() {
        for invalid in ["{\"x\":1,\"x\":2}", "{\"x\":1,\"\\u0078\":2}", "[01]", "[1.]", "[+1]", "[1e]", "[NaN]", "[true,]", "{\"a\":1,}", "\"\\uD800\"", "\"\\uDC00\"", "\"a\nb\"", "true false", "[", "", "\"\\x12\""] {
            XCTAssertThrowsError(try LosslessJSON.parse(Data(invalid.utf8)), invalid)
        }
        XCTAssertThrowsError(try LosslessJSON.parse(Data([0x22, 0xff, 0x22])))
        XCTAssertThrowsError(try LosslessJSON.number("1,\"injected\":true").serializedData())
    }

    func testUnicodeEscapesAndControlCharactersRoundTrip() throws {
        let value = try LosslessJSON.parse(Data(#"{"emoji":"\uD83D\uDE00","control":"\n\r\t\b\f\u0000","text":"日本語é/\\\""}"#.utf8))
        guard case .object(let object) = value else { return XCTFail() }
        XCTAssertEqual(object["emoji"], .string("😀"))
        XCTAssertEqual(try LosslessJSON.parse(value.serializedData()), value)
    }

    func testInvalidEditsAreAtomicAndStructuralChangesBlocked() throws {
        var document = try PageDocument(data: Data(raw.utf8))
        let baseline = document
        for bad in ["", String(repeating: "x", count: 101)] {
            XCTAssertThrowsError(try document.setName(bad))
            XCTAssertEqual(document, baseline)
        }
        for index in [-1, 2] {
            XCTAssertThrowsError(try document.replaceTemplateLine(at: index, with: "x"))
            XCTAssertEqual(document, baseline)
        }
        for content in ["a\nb", "a\rb"] {
            XCTAssertThrowsError(try document.replaceTemplateLine(at: 0, with: content))
            XCTAssertEqual(document, baseline)
        }
        for unsupported in [
            #"{"type":"single","template":["a"]}"#,
            #"{"type":"template","template":["a",{"future":"node"}]}"#,
            // `"line_metadata":[]` (shorter than `template`) moved to LosslessRoundTripTests: real pages
            // carry short arrays and PLAN §2.2 requires them editable, read as the server reads them.
            #"{"type":"template","template":["a"],"line_metadata":[null]}"#,
            #"{"type":"template","template":["a"],"line_metadata":[{"alignment":"future"}]}"#
        ] {
            var readOnly = try PageDocument(data: Data(unsupported.utf8))
            let before = readOnly
            XCTAssertNil(readOnly.editableTemplateLines)
            XCTAssertThrowsError(try readOnly.replaceTemplateLine(at: 0, with: "new"))
            XCTAssertEqual(before, readOnly)
        }
    }

    func testPatchIncludesExplicitNullAndRefusesImplicitDeletion() throws {
        let before = try PageDocument(data: Data(#"{"name":"a","value":1}"#.utf8))
        let after = try PageDocument(data: Data(#"{"name":"a","value":null}"#.utf8))
        XCTAssertEqual(try after.changedFields(from: before), .object(["value": .null]))
        let deleted = try PageDocument(data: Data(#"{"name":"a"}"#.utf8))
        XCTAssertThrowsError(try deleted.changedFields(from: before))
    }
}


final class EvaluationPayloadTests: XCTestCase {
    func testPreviewCopiesSupportedFieldsLosslesslyAndExcludesStorageFields() throws {
        let data = Data(#"{"id":"p","name":"N","revision":"r1","type":"template","template":["e\u0301"],"grid_cols":128,"line_metadata":[{"future":12345678901234567890}],"canvases":[{"unknown":1e+999}],"future_page":"kept on disk"}"#.utf8)
        let document = try PageDocument(data: data)
        let preview = try LosslessJSON.parse(document.evaluationData(boardID: "b", preview: true))
        guard case .object(let payload) = preview else { return XCTFail("object") }
        XCTAssertNil(payload["name"])
        XCTAssertNil(payload["revision"])
        XCTAssertNil(payload["future_page"])
        XCTAssertEqual(payload["board_id"], .string("b"))
        XCTAssertEqual(payload["grid_cols"], document.root["grid_cols"])
        XCTAssertEqual(payload["line_metadata"], document.root["line_metadata"])
        XCTAssertEqual(payload["canvases"], document.root["canvases"])
        guard case .object(let validate) = try LosslessJSON.parse(document.evaluationData(boardID: "b", preview: false)) else { return XCTFail("object") }
        XCTAssertEqual(validate.count, 2)
    }
    func testEvaluationRefusesMalformedShape() throws {
        for source in [#"{"type":"single","template":["x"]}"#, #"{"type":"template","template":[1]}"#, #"{"type":"template","template":["x"],"canvases":{}}"#, #"{"type":"template","template":["x"],"line_metadata":[1]}"#, #"{"type":"template","template":["x"],"device_type":"unknown"}"#, #"{"type":"template","template":["x"],"notes_wide":null}"#, #"{"type":"template","template":["x"],"device_type":"panel"}"#] {
            let document = try PageDocument(data: Data(source.utf8))
            XCTAssertThrowsError(try document.evaluationData(boardID: "b", preview: true))
        }
    }
    func testServerAdoptionClearsOldHistoryButDoesNotClaimDiskIsCurrent() throws {
        var session = try DocumentEditingSession(data: Data(#"{"name":"Old","revision":"r1"}"#.utf8))
        try session.setName("New")
        let saved = session.document
        session.markSaved(saved)
        try session.adoptServerDocument(Data(#"{"name":"New","revision":"r2"}"#.utf8))
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(session.baseline.root["revision"], .string("r2"))
        try session.undo()
        XCTAssertEqual(session.baseline.root["revision"], .string("r2"))
    }
}
