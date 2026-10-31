import Foundation

/// Labels introduced by the document editor (iOS-E1, D1). iOS-E2 merges these into
/// `App/Strings.swift` in wave 2. Wording follows the web's terms (`reports/web-terminology-glossary.md`).
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
    static let localPreviewNote = "Local preview · choose a display for the server's render"
    static let simulatedPreviewNote = "Demo · local preview, expressions are not evaluated"
    static func fits(_ name: String) -> String { "Fits \(name)" }
    static func sizeReadout(rows: Int, cols: Int) -> String { "\(rows) × \(cols)" }

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
