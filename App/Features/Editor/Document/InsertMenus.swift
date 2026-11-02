import SwiftUI
import UIKit
import FiestaBoardDocuments

/// The insert buttons' actions (PLAN B15): Variables, Colors, Formatting open the searchable
/// pickers (iOS-F1, `Catalog/InsertPickerSheet`), Insert formula opens the formula editor
/// (`Formula/FormulaEditorSheet`). The toolbar, the accessory and the insertion path
/// (`DocumentBuffer.insert`) are unchanged.
@MainActor struct InsertPickers {
    var variables: VariableCatalog
    var onInsert: (String) -> Void
    var onFormula: () -> Void
    var onPicker: (InsertPickerKind) -> Void = { _ in }
    /// B32: Variables is disabled when the server has none; Colors/Formatting show only when listed.
    var variablesEnabled = true
    var colorsShown = true
    var formattingShown = true
}
