import XCTest
import UIKit
import FiestaBoardDocuments
@testable import FiestaBoard

/// B31 (P5): the spoken labels of every chip in the document, as VoiceOver reads them from the
/// text view's attachments, for the B13 row and the fixture page "Good Morning". Printed as
/// `B31-LABEL` lines (the evidence dump is taken from the test log) and asserted.
@MainActor final class VoiceOverLabelDumpTests: XCTestCase {
    func testChipLabelsAsVoiceOverReadsThem() {
        let rows = [
            #"TEMP {{weather.temperature|pad:3}} {{= IF(weather.temperature>70,"HI","") }} {{blue}}"#,
            "GOOD MORNING", "{{weather.temperature|pad:3}}° {{weather.condition}}", "",
            "{{red}}{{orange}}{{yellow}}{{green}}{{blue}}{{violet}}",
            #"{{= IF(weather.temperature > 70, "WARM OUT", "BRING A COAT") }}"#, "{{fill_space_repeat:-}}",
        ]
        let view = TemplateUITextView(usingTextLayoutManager: false)
        view.allowsMultiline = true
        view.setTemplate(rows.joined(separator: "\n"), rich: true, font: .monospacedSystemFont(ofSize: 17, weight: .regular),
                         sourceSelection: NSRange(location: 0, length: 0))
        var labels: [String] = []
        let text = view.attributedText!
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let attachment = value as? TemplateAttachment { labels.append("\(attachment.source) → \(attachment.accessibilityLabel ?? "nil")") }
        }
        for line in labels { print("B31-LABEL \(line)") }
        XCTAssertEqual(labels[0], "{{weather.temperature|pad:3}} → variable weather.temperature, filter pad 3")
        XCTAssertTrue(labels[1].hasSuffix("→ formula, IF(weather.temperatu…"), labels[1])
        XCTAssertEqual(labels[2], "{{blue}} → blue tile")
        XCTAssertTrue(labels.contains("{{red}} → red tile"))
        XCTAssertEqual(view.accessibilityValue, rows.joined(separator: "\n"), "the document's value is its source")
    }
}
