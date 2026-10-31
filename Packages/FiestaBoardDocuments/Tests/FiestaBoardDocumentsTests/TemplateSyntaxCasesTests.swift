import XCTest
import CryptoKit
@testable import FiestaBoardDocuments

/// `fixtures/template-syntax-cases.json` (PLAN §3.2, §4.0) is generated from the inline literals
/// of `TemplateSyntaxTests` so the Android port tests against the same cases. The canonical copy
/// lives in the handoff folder; the repo mirror is `Fixtures/shared/template-syntax-cases.json`.
/// Regenerate with `TEMPLATE_SYNTAX_CASES_OUT=<path> swift test --filter TemplateSyntaxCasesTests`.
final class TemplateSyntaxCasesTests: XCTestCase {
    static let sources: [String] = [
        // testBothFamiliesRoundTripWithoutNormalization
        "", "e\u{301} é \u{200B} 😀", "A{{RED}}{{fill_space_repeat:a:b}}Z", "{{weather:sf.temperature|pad:3}}", "{{= 1 + 1 }}",
        "{{red:{{demo.temp}}°}}", "{{black/white:A{{red:B}}C}}", "{{icon:sun}}", "broken {{red", "{{{future}}}", "{63}{red}",
        // testBalancedLEDSpanDoesNotEatAdjacentVariable
        "{{red:{{demo.temp}}°}}{{weather:sf.temp}}",
        // testAtomKindsAndIncompleteSyntax
        "{{RED}}{{fill_space}}{{= x }}{{icon:sun}}{{black/white:OPEN}}{blue}", "before {{unfinished",
        // testUTF16MappingPreservesTokenBoundaryAndEmoji
        "😀{{weather.temp}}e\u{301}",
        // PLAN B13 row 2 and fixture pages (§4.3)
        "TEMP {{weather.temperature|pad:3}} {{= IF(weather.temperature>70,\"HI\",\"\") }} {{blue}}",
        "{{weather.temperature|pad:3}}° {{weather.condition}}", "{{red}} LOVE {{red}}", "{{fill_space_repeat:-}}"
    ]

    static func casesJSON() throws -> Data {
        let cases: [[String: Any]] = sources.map { source in
            let fragments = TemplateSyntax.fragments(source)
            let sourceLength = source.utf16.count
            let displayLength = fragments.reduce(0) { $0 + $1.displayLength }
            return [
                "source": source,
                "fragments": fragments.map { ["source": $0.source, "kind": $0.kind.rawValue, "label": $0.label, "display_length": $0.displayLength] },
                "display_offset_for_source_offset": (0...sourceLength).map { TemplateSyntax.displayOffset(sourceOffset: $0, in: source) },
                "source_offset_for_display_offset": (0...displayLength).map { TemplateSyntax.sourceOffset(displayOffset: $0, in: source) }
            ]
        }
        let root: [String: Any] = [
            "description": "TemplateSyntax lexical cases generated from iOS FiestaBoardDocuments TemplateSyntaxTests literals. Offsets are UTF-16 code units; display offsets count one unit per non-text fragment.",
            "writer": "iOS-E1",
            "cases": cases
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testMirrorMatchesGeneratedCases() throws {
        let generated = try Self.casesJSON()
        if let out = ProcessInfo.processInfo.environment["TEMPLATE_SYNTAX_CASES_OUT"] {
            try generated.write(to: URL(fileURLWithPath: out))
        }
        let mirror = repoRoot.appendingPathComponent("Fixtures/shared/template-syntax-cases.json")
        let data = try Data(contentsOf: mirror)
        XCTAssertEqual(data, generated, "Regenerate the canonical fixture and copy it to the mirror")
        // Mirror provenance records the sha256 of the copied file.
        let provenance = repoRoot.appendingPathComponent("Fixtures/shared/source-provenance.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: provenance)) as? [String: Any])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let recorded = (object["template-syntax-cases.json"] as? [String: Any])?["sha256"] as? String
            ?? object["template-syntax-cases.json"] as? String
        XCTAssertEqual(recorded, digest)
    }

    func testEveryCaseRoundTripsItsSource() throws {
        for source in Self.sources {
            XCTAssertEqual(TemplateSyntax.fragments(source).map(\.source).joined(), source)
        }
    }
}
