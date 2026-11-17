import Foundation
import XCTest
@testable import FiestaBoardKit
final class MetadataPatchTests: XCTestCase {
    func testMetadataOnlyPatchKeepsNumericSpellingAndRevision() throws {
        let metadata = Data(#"[{"alignment":"left","opaque":9223372036854775807123456789,"decimal":1.23000e+99}]"#.utf8)
        let patch = PageSavePatch(lineMetadataData: metadata, expectedRevision: "original")
        let members = try RawJSONObject.members(patch.serializedData())
        XCTAssertEqual(members["line_metadata"], metadata)
        XCTAssertNil(members["name"]); XCTAssertNil(members["template"])
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(members["expected_revision"])), "original")
    }
    @MainActor func testDemoStoresRawMetadataAndPreservesItThroughSubsequentNamePatch() async throws {
        let demo = try FixtureFiestaBoardService()
        _ = try await demo.connect(allowCandidateWrites: true)
        let before = try await demo.page(id: "page-selected")
        let metadata = Data(#"[{"alignment":"right","opaque":9223372036854775807123456789,"decimal":1.23000e+99}]"#.utf8)
        let saved = try await demo.savePage(id: before.id, patch: PageSavePatch(template: ["A"], lineMetadataData: metadata, expectedRevision: XCTUnwrap(before.revision)))
        XCTAssertEqual(try RawJSONObject.members(saved.pageData)["line_metadata"], metadata)
        let updated = try JSONDecoder().decode(Page.self, from: saved.pageData)
        let renamed = try await demo.savePage(id: before.id, patch: PageSavePatch(name: "Renamed", expectedRevision: XCTUnwrap(updated.revision)))
        XCTAssertEqual(try RawJSONObject.members(renamed.pageData)["line_metadata"], metadata)
        let read = try await demo.pageDocumentData(id: before.id)
        XCTAssertEqual(try RawJSONObject.members(read)["line_metadata"], metadata)
    }
    func testPublicMetadataRejectsWrongEnvelopesAndMalformedJSON() {
        for text in ["null", "{}", "[1]", "[null]", "[{}],\"injected\":true", "[{\"a\":1,}]", "[{\"a\":1,\"a\":2}]", "[{}] garbage", #"[{"nested":{"x":1,"x":2}}]"#] {
            XCTAssertThrowsError(try PageSavePatch(lineMetadataData: Data(text.utf8), expectedRevision: "r1").serializedData(), text)
        }
    }
}
