import Foundation
import FiestaBoardDocuments
import FiestaBoardKit

/// The editor's user-facing labels (iOS-E1's `Strings+Editor.swift`, merged here by iOS-E2).
/// Wording follows the web's terms (`reports/web-terminology-glossary.md`); `TerminologyTests`
/// checks the glossary terms against `Fixtures/shared/terminology.json`.
enum EditorStrings {
    static let navigationTitle = "Edit Page"
    static let titlePlaceholder = "My Custom Page"
    static let titleLabel = "Page name"
    static let close = "Close"
    static let save = "Save"
    static let undo = "Undo"
    static let redo = "Redo"
    static let alignLeft = "Align left"
    static let alignCenter = "Align center"
    static let alignRight = "Align right"
    static let wrap = "Wrap"
    static let hideKeyboard = "Hide keyboard"
    static let rich = "Rich"
    static let plain = "Plain"
    static let documentDetails = "Document details"
    static let variables = "Variables"
    static let colors = "Colors"
    static let formatting = "Formatting"
    static let insertFormula = "Insert formula"
    static let drawOnBoard = "Draw on board"
    static let insert = "Insert"
    static let cancel = "Cancel"
    static let formulaPlaceholder = "IF(weather.temperature > 70, \"WARM\", \"COOL\")"
    static let formulaFooter = "The server works out the value each time the board updates."
    static let formulaExamples = "Examples"
    static let editingMode = "Editing mode"
    static let boardSize = "Board size"
    static let flagship = "Flagship"
    static let note = "Note"
    static let noteArray = "Note Array"
    static let panel = "Panel"
    static let showWhen = "Show when"
    static let displayRestrictions = "Display restrictions"
    static let addText = "Add text"
    static let addCanvas = "Add canvas"
    static let addSpacer = "Add spacer"
    static func addBlock(_ kind: String) -> String {
        switch kind { case "text": addText; case "canvas": addCanvas; case "spacer": addSpacer; default: "Add \(kind)" }
    }
    static func shapeName(_ shape: PageGeometry) -> String {
        switch shape.deviceType {
        case "flagship": return "\(flagship) · 6 × 22"
        case "note": return "\(note) · 3 × 15"
        case "note_array": return "\(noteArray) (\(shape.notesWide ?? 1) wide / \(shape.notesTall ?? 1) tall) · \(shape.rows) × \(shape.columns)"
        case "panel": return "\(panel) · \(shape.rows) × \(shape.columns)"
        default: return "\(shape.rows) × \(shape.columns)"
        }
    }
    static let resizeTitle = "Change board size?"
    static let resizeMessage = "Content that doesn't fit the smaller board will be cut off."
    static let resizeAndSave = "Resize and save"
    static let plainHelp = [
        "{{weather.temperature}} shows a variable",
        "{{red}}, {{blue}}… draw colour tiles",
        "{{= IF(…) }} is a formula",
        "Start a row with {center}, {right} or {wrap} to align or wrap it",
    ]
    static func unknownVariableIssue(row: Int, name: String, reason: String) -> String { "Row \(row) · \(name): \(reason)" }

    static let discardTitle = "Discard unsaved changes?"
    static let discardMessage = "Your changes have not been saved to the server. A recovery copy stays on this device."
    static let keepEditing = "Keep editing"
    static let discardAndLeave = "Discard and leave"

    static let updating = "Updating…"
    static let previewUnavailable = "Preview unavailable"
    static let retry = "Retry"
    static let previewNow = "Refresh preview"
    static let displayPickerLabel = "Display preview"
    static let yourDisplays = "Your displays"
    static let noDisplay = "No display (local preview)"
    static let sampleValuesNote = "Sample values"
    static let chooseDisplayNote = "Choose a display to see live values"
    static func saveOff(_ reason: String) -> String { "Can't save: \(plainSaveReason(reason))" }
    /// The save gate's reasons are written for engineers; the editor says them plainly. The exact
    /// reason stays in Document details.
    static func plainSaveReason(_ reason: String) -> String {
        let lower = reason.lowercased()
        if lower.contains("opt-in") || lower.contains("page-revision") || lower.contains("revision protocol") || lower.contains("server version") {
            return "this server doesn't accept page edits from the app."
        }
        if lower.contains("unavailable for this local document") { return "this page isn't connected to a server." }
        if lower.contains("unsupported editing protocol") || lower.contains("cannot be safely saved") { return "the app can't save this kind of page yet." }
        if lower.contains("outside supported author fields") || lower.contains("complete line metadata") { return "some of these changes can't be saved from the app." }
        if lower.contains("at least one template line") { return "add some text first." }
        if lower.contains("changed on the server") { return "the page changed on the server. Compare first." }
        return reason
    }
    static func fits(_ name: String) -> String { "Fits \(name)" }
    static func doesNotFit(rows: Int, cols: Int) -> String { "Doesn't fit · \(rows) × \(cols)" }
    static func displayChoiceDetail(rows: Int?, cols: Int?, fits: Bool?) -> String? {
        guard let rows, let cols else { return nil }
        return fits == false ? "\(rows) × \(cols) · doesn't fit" : "\(rows) × \(cols)"
    }
    static func sizeReadout(rows: Int, cols: Int) -> String { "\(rows) × \(cols)" }

    /// A validate error (W4): the server's `line` is 1-based and its `column` 0-based (10.3.2
    /// reports a formula error at column 0), so the column shown is `column + 1`.
    static func validationIssue(_ issue: TemplateValidationIssue) -> String {
        "Line \(issue.line), column \(max(0, issue.column) + 1): \(issue.message)"
    }
    /// B16 charset issues from `charset_issues` (0-based `row`/`col`): "Line L, column C: this
    /// board can't show “X” and draws “Y” instead.", at most five, then "…and N more".
    static func charsetIssueLines(_ issues: [TemplateCharsetIssue], limit: Int = 5) -> [String] {
        func describe(_ token: TemplateCharsetIssue.Token?) -> String {
            guard let token else { return "?" }
            if token.kind == "color" { return "\(token.code ?? "?") tile" }
            if let icon = token.icon { return "\(icon) icon" }
            if token.value == " " { return "a blank" }
            return token.value ?? "?"
        }
        var lines = issues.prefix(limit).map { issue in
            let shown = describe(issue.token), drawn = describe(issue.fallback)
            let quote = { (text: String) in text.hasSuffix(" tile") || text.hasSuffix(" icon") || text == "a blank" ? text : "“\(text)”" }
            return "Line \(issue.row + 1), column \(issue.col + 1): this board can't show \(quote(shown)) and draws \(quote(drawn)) instead."
        }
        if issues.count > limit { lines.append("…and \(issues.count - limit) more") }
        return lines
    }

    static func lineCounter(_ count: Int, limit: Int) -> String {
        count > limit ? "\(count) / \(limit) lines — exceeds the \(limit)-line board limit" : "\(count) / \(limit) lines"
    }
    static func overflowWarning(limit: Int) -> String {
        "Rows after row \(limit) don't fit on this board and won't be shown."
    }
    static let pageUpdated = "Page updated"
    static let pageUpdatedSimulated = "Page updated (simulated)"
    static let compareAndReload = "Compare and reload"
    static let conflictBanner = "The page changed on the server. Your work is kept on this device."
    static let unknownBanner = "The save result is unknown. Your work is kept on this device. Read the page back before saving again."
    static let reloadTitle = "Reload the server page?"
    static let reloadAction = "Preserve local draft and reload"
    static let keepLocalWork = "Keep local work"
    static let reloadMessage = "Your current work is saved on this device first. Undo history is cleared so an old server revision cannot return."
}

/// Pages and page detail, in plain words (P1).
enum LibraryStrings {
    static let webOnly = "This kind of page is edited in the web app."
    static let textSection = "Text"
    static func blocks(_ count: Int) -> String { count == 1 ? "1 block" : "\(count) blocks" }
    static func showOn(_ board: String?) -> String { board.map { "Show on \($0)" } ?? "Show on a display" }
    /// Kit's action reasons are written for engineers; these say the same thing plainly.
    static func plain(_ reason: ActionDisabledReason) -> String {
        switch reason {
        case .changesDisabled: "Changing this board from the app is turned off. Turn it on in Settings."
        case .noDisplay: "Choose a display first."
        case .disconnected: "Connect to your FiestaBoard first."
        case .busy: "Wait for the board to finish."
        case .readbackRequired: "Refresh to see the board before making another change."
        case .unsupportedOperation, .unsupportedDocument, .unsupportedRevisionProtocol, .missingRevision:
            "This can't be done from the app with this server. Use the web app."
        }
    }
}
