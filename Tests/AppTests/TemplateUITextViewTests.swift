import XCTest
import UIKit
import FiestaBoardDocuments
@testable import FiestaBoard

/// PLAN B14/B31: a chip is one character for the caret and for Backspace; attachments re-render
/// on light/dark and Dynamic Type changes.
@MainActor final class TemplateUITextViewTests: XCTestCase {
    private let font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)

    private func makeView(_ source: String) -> (UIWindow, TemplateUITextView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let view = TemplateUITextView(usingTextLayoutManager: false)
        view.frame = window.bounds
        view.allowsMultiline = true
        window.addSubview(view); window.makeKeyAndVisible()
        view.setTemplate(source, rich: true, font: font, sourceSelection: NSRange(location: 0, length: 0))
        return (window, view)
    }

    func testChipIsAtomicForCaretAndDelete() {
        let (window, view) = makeView("A{{weather.temperature|pad:3}}B")
        defer { window.isHidden = true }
        XCTAssertEqual(view.attributedText.length, 3, "the chip is one character")
        // → across the chip: from before it (1) to after it (2) in one step.
        view.selectedRange = NSRange(location: 1, length: 0)
        let after = view.position(from: view.selectedTextRange!.start, offset: 1)!
        XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: after), 2)
        // Every caret position maps to a source offset outside the token.
        for display in 0...3 {
            view.selectedRange = NSRange(location: display, length: 0)
            let offset = view.sourceSelection.location
            XCTAssertTrue([0, 1, 30, 31].contains(offset), "caret at source \(offset) is never inside the token")
        }
        // Backspace after the chip deletes the whole chip.
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: 2, length: 0)
        view.deleteBackward()
        XCTAssertEqual(view.templateSource, "AB")
    }

    func testCopyExportsTemplateSource() {
        let (window, view) = makeView("{{red}}HI{{= IF(1>0,\"A\",\"B\") }}")
        defer { window.isHidden = true }
        view.selectedRange = NSRange(location: 0, length: view.attributedText.length)
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "{{red}}HI{{= IF(1>0,\"A\",\"B\") }}")
    }

    func testInsertedTokenBecomesAChipWithTheCaretAfterIt() {
        let (window, view) = makeView("AB")
        defer { window.isHidden = true }
        view.selectedRange = NSRange(location: 1, length: 0)
        view.setTemplate("A{{red}}B", rich: true, font: font, sourceSelection: NSRange(location: 8, length: 0))
        XCTAssertEqual(view.attributedText.length, 3)
        XCTAssertEqual(view.selectedRange, NSRange(location: 2, length: 0))
        XCTAssertTrue(view.attributedText.attribute(.attachment, at: 1, effectiveRange: nil) is TemplateAttachment)
    }

    func testAttachmentsRerenderOnTraitChange() throws {
        let (window, view) = makeView("{{weather.temperature}}")
        defer { window.isHidden = true }
        let before = try XCTUnwrap(view.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? TemplateAttachment).image
        let count = view.traitRerenderCount
        window.overrideUserInterfaceStyle = window.traitCollection.userInterfaceStyle == .dark ? .light : .dark
        view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(view.traitRerenderCount, count, "a light/dark change re-rasterises the chips")
        let after = try XCTUnwrap(view.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? TemplateAttachment).image
        XCTAssertFalse(before === after)
        XCTAssertEqual(view.templateSource, "{{weather.temperature}}", "the source is unchanged")
    }
}
