import XCTest
import UIKit
import FiestaBoardEditorState
@testable import FiestaBoard

@MainActor final class ComposeTextViewTests: XCTestCase {
    func testCommittedNativeEditPublishesSourceAndSelectionTogether() {
        var received: ComposeInput?
        let adapter = ComposeTextView(input: .init(text: "Hi"), enabled: true) { received = $0 }
        let coordinator = ComposeTextView.Coordinator(adapter)
        let native = TemplateUITextView(usingTextLayoutManager: false)
        native.allowsMultiline = true
        native.setTemplate("Hi 🌮", rich: true, font: .preferredFont(forTextStyle: .body), sourceSelection: NSRange(location: 5, length: 0))
        coordinator.textViewDidChange(native)
        XCTAssertEqual(received?.text, "Hi 🌮")
        XCTAssertEqual(received?.selection.lowerUTF16, 5)
        XCTAssertEqual(received?.selection.upperUTF16, 5)
    }
}
