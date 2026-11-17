import Foundation
import XCTest
@testable import FiestaBoardKit

final class FlexiblePageReaderTests: XCTestCase {
    func testMixedPageListRetainsLegacyGeometryAndFlexibleIdentity() throws {
        let data = Data(#"[{"id":"grid","name":"Legacy","type":"template","device_type":"flagship","template":["HELLO"]},{"id":"flex","name":"Adaptive","type":"flexible","blocks":[{"id":"title","kind":"text","text":"Hello"}],"document_protocol":"page-document-v2","revision":"r1"}]"#.utf8)
        let pages = try JSONDecoder().decode([Page].self, from: data)
        XCTAssertEqual(pages.map(\.id), ["grid", "flex"])
        XCTAssertEqual(pages[0].deviceType, "flagship")
        XCTAssertEqual(pages[0].template, ["HELLO"])
        XCTAssertEqual(pages[1].type, "flexible")
        XCTAssertNil(pages[1].deviceType)
        XCTAssertNil(pages[1].template)
    }

    func testReadOnlyFlexibleSummaryIncludesTextAndCanvasWithoutGrantingEditing() throws {
        let raw = Data(#"{"id":"flex","name":"Flexible","type":"flexible","document_protocol":"page-document-v2","blocks":[{"id":"a","kind":"text","text":"HELLO {{weather.temperature}}","unknown":null},{"id":"b","kind":"canvas","canvas":{"unknown":"retained only in author document"}}]}"#.utf8)
        let page = try JSONDecoder().decode(Page.self, from: raw)
        XCTAssertEqual(page.blockSummaries?.map(\.kind), ["text", "canvas"])
        XCTAssertEqual(page.blockSummaries?.first?.text, "HELLO {{weather.temperature}}")
        XCTAssertFalse(page.supportsTemplateEditing)
        let unknown = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p","name":"P","type":"flexible","document_protocol":"future","blocks":{}}"#.utf8))
        XCTAssertNil(unknown.blockSummaries)
    }

    func testUnknownPageFamilyDoesNotBreakTheReadProjection() throws {
        let data = Data(#"{"id":"future","name":"Future","type":"future-family","document_protocol":"page-document-v3"}"#.utf8)
        let page = try JSONDecoder().decode(Page.self, from: data)
        XCTAssertEqual(page.id, "future")
        XCTAssertNil(page.deviceType)
    }
    func testUnknownFamilyProjectionFieldsDoNotInvalidateMixedLibrary() throws {
        let data = Data(#"[{"id":"grid","name":"Legacy","type":"template","device_type":"flagship","template":["HELLO"]},{"id":"future","name":"Future","type":"future-family","template":{},"device_type":{},"grid_rows":{}}]"#.utf8)
        let pages = try JSONDecoder().decode([Page].self, from: data)
        XCTAssertEqual(pages.map(\.id), ["grid", "future"])
        XCTAssertEqual(pages[0].template, ["HELLO"])
        XCTAssertNil(pages[1].template)
        XCTAssertNil(pages[1].deviceType)
        XCTAssertNil(pages[1].gridRows)
    }
    func testFutureTemplateProtocolDoesNotRequireLegacyProjectionFields() throws {
        let data = Data(#"{"id":"future","name":"Future template","type":"template","document_protocol":"page-document-v99","template":{},"edit_protocol":"page-revision-v1","revision":"r1"}"#.utf8)
        let page = try JSONDecoder().decode(Page.self, from: data)
        XCTAssertEqual(page.id, "future")
        XCTAssertFalse(page.supportsTemplateEditing)
        XCTAssertNil(page.deviceType)
        XCTAssertNil(page.template)
    }

    func testLegacyTemplateStillRequiresItsGeometryField() throws {
        let data = Data(#"{"id":"grid","name":"Legacy","type":"template","template":["HELLO"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Page.self, from: data))
    }
}
