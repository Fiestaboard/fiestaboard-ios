import XCTest
import FiestaBoardEditorState
@testable import FiestaBoard

/// PLAN B27: the editor's labels match the shared glossary (`Fixtures/shared/terminology.json`,
/// mirrored from the handoff's `fixtures/`). App-wide terms (Home, Now showing, Sign out, New Page)
/// belong to the app shell's string table and are checked there.
@MainActor final class TerminologyTests: XCTestCase {
    private struct Glossary: Decodable { struct Term: Decodable { let id: String; let text: String; let scope: String }; let terms: [Term] }

    private var editorStrings: [String: String] {
        [
            "editPage": EditorStrings.navigationTitle, "save": EditorStrings.save, "unsavedChanges": SaveStatus.unsaved.label,
            "discardTitle": EditorStrings.discardTitle, "keepEditing": EditorStrings.keepEditing, "discardAndLeave": EditorStrings.discardAndLeave,
            "rich": EditorStrings.rich, "plain": EditorStrings.plain, "variables": EditorStrings.variables, "colors": EditorStrings.colors,
            "formatting": EditorStrings.formatting, "insertFormula": EditorStrings.insertFormula, "wrap": EditorStrings.wrap,
            "drawOnBoard": EditorStrings.drawOnBoard, "displayPreview": EditorStrings.displayPickerLabel,
            "flagship": EditorStrings.flagship, "note": EditorStrings.note, "noteArray": EditorStrings.noteArray, "panel": EditorStrings.panel,
            "addText": EditorStrings.addText, "addCanvas": EditorStrings.addCanvas, "addSpacer": EditorStrings.addSpacer,
            "showWhen": EditorStrings.showWhen, "displayRestrictions": EditorStrings.displayRestrictions,
        ]
    }

    func testEditorLabelsMatchTheGlossary() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shared/terminology.json")
        let glossary = try JSONDecoder().decode(Glossary.self, from: Data(contentsOf: url))
        let editorTerms = glossary.terms.filter { $0.scope == "editor" }
        XCTAssertFalse(editorTerms.isEmpty)
        for term in editorTerms {
            XCTAssertEqual(editorStrings[term.id], term.text, "\(term.id)")
        }
        XCTAssertEqual(Set(editorStrings.keys), Set(editorTerms.map(\.id)), "every editor term is mapped")
    }
}
