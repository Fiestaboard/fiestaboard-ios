import CryptoKit
import Foundation
import XCTest
@testable import FiestaBoardRender

/// The vendored assets are the cross-language contract: any byte drift from
/// the recorded provenance (tvOS a3df9c9; led-fonts and markup_icons also
/// FiestaBoard v10.3.2) fails here.
final class SpecDriftTests: XCTestCase {
    struct Provenance: Decodable {
        struct Entry: Decodable { let sha256: String; let fiestaboard_sha256: String? }
        let commit: String
        let files: [String: Entry]
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private func provenance() throws -> Provenance {
        let data = try XCTUnwrap(RenderResources.data("source-provenance", "json"), "source-provenance.json missing")
        return try JSONDecoder().decode(Provenance.self, from: data)
    }

    func testEveryVendoredAssetMatchesItsRecordedChecksum() throws {
        let provenance = try provenance()
        XCTAssertEqual(provenance.commit, "a3df9c9")
        let expected: [String: String] = [
            "board-spec.json": "1a81fcc1cdc12192466a45208cd9ee175d0fb93082a026e5bff1291a5ff676e9",
            "led-fonts.json": "975e1ee0eb0eea1e0138d1eeb3217eb3f4d9b610c55cfd66d6a7f65ecb02446d",
            "markup_icons.json": "fc7eb7cabc90ff6c295e197a8609d74bd5ddbb4832bd7a0c06ac973f6aa6e712",
            "SplineSansMono.ttf": "e20c1df32aa2f886e828cfcc81ca5c405d3f3b160990f6b892923e2e449bf525",
        ]
        for (file, hash) in expected {
            let parts = file.split(separator: ".")
            let data = try XCTUnwrap(RenderResources.data(String(parts[0]), String(parts[1])), "\(file) not bundled")
            XCTAssertEqual(sha(data), hash, "\(file) drifted from tvOS a3df9c9")
            XCTAssertEqual(provenance.files[file]?.sha256, hash, "\(file) provenance out of date")
        }
    }

    func testLedAssetsEqualFiestaBoardServerBytes() throws {
        let provenance = try provenance()
        for file in ["led-fonts.json", "markup_icons.json"] {
            let entry = try XCTUnwrap(provenance.files[file])
            // If FiestaBoard's bytes ever differ from tvOS's, both are recorded and this fails loudly.
            XCTAssertEqual(entry.fiestaboard_sha256, entry.sha256, "\(file): tvOS and FiestaBoard v10.3.2 bytes differ")
        }
    }

    func testBoardSpecDecodesAndAgreesWithTheSwiftConstants() throws {
        let url = try XCTUnwrap(RenderResources.url("board-spec", "json"))
        let spec = try BoardSpec.load(from: url)
        XCTAssertEqual(spec.tileRatios.width, BoardGeometry.tileWidthRatio)
        XCTAssertEqual(spec.tileRatios.gutter, BoardGeometry.tileGutterRatio)
        XCTAssertEqual(spec.tileRatios.radius, BoardGeometry.tileRadiusRatio)
        XCTAssertEqual(spec.colors["63"]?.lowercased(), BoardColor.red.hex)
    }

    func testTheBoardFontRegisters() {
        XCTAssertTrue(BoardFont.registerIfNeeded(), "Spline Sans Mono must load from the module bundle")
    }
}

/// Test-side twin of tvOS `SpecFixture`.
enum SpecFixture {
    static let spec: BoardSpec = try! BoardSpec.load(from: RenderResources.url("board-spec", "json")!)
}
