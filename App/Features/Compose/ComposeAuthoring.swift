import Foundation
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit

/// Editing transformations retain the user's source and authoring choices.
/// Scope, durability and prepared-intent authority belong to ComposeSession.
enum ComposeAuthoring {
    static func replacingText(_ text: String, in input: ComposeInput, selection: ComposeBufferSelection) -> ComposeInput {
        let old = input.text.components(separatedBy: "\n"), new = text.components(separatedBy: "\n")
        let original = LosslessJSON.array(input.lineMetadata.map {
            .object(["alignment": .string($0.alignment), "wrap": .bool($0.wrap)])
        })
        let spliced = LineMetadataSplice.splice(old: old, new: new, metadata: original)
        let metadata: [ComposeBufferLine]
        if case .array(let entries)? = spliced {
            metadata = new.indices.map { index in
                guard index < entries.count, case .object(let fields) = entries[index] else { return .init() }
                let alignment: String = if case .string(let value)? = fields["alignment"] { value } else { "left" }
                let wrap: Bool = if case .bool(let value)? = fields["wrap"] { value } else { false }
                return .init(alignment: alignment, wrap: wrap)
            }
        } else { metadata = new.map { _ in .init() } }
        let lower = min(text.utf16.count, max(0, selection.lowerUTF16))
        let upper = min(text.utf16.count, max(lower, selection.upperUTF16))
        return .init(text: text, lineMetadata: metadata, selection: .init(lowerUTF16: lower, upperUTF16: upper),
                     duration: input.duration, silence: input.silence)
    }
    static func inserting(_ source: String, into input: ComposeInput) -> ComposeInput {
        let text = input.text as NSString
        let lower = min(text.length, max(0, input.selection.lowerUTF16))
        let upper = min(text.length, max(lower, input.selection.upperUTF16))
        let updated = text.replacingCharacters(in: NSRange(location: lower, length: upper - lower), with: source)
        let caret = lower + source.utf16.count
        return replacingText(updated, in: input, selection: .init(lowerUTF16: caret, upperUTF16: caret))
    }
    static func wrappingSelection(_ color: String, in input: ComposeInput) -> ComposeInput {
        let source = input.text as NSString
        let lower = min(source.length, max(0, input.selection.lowerUTF16))
        let upper = min(source.length, max(lower, input.selection.upperUTF16))
        return inserting("{{\(color):\(source.substring(with: NSRange(location: lower, length: upper - lower)))}}", into: input)
    }
    static func formatting(_ input: ComposeInput, alignment: String, wrap: Bool) -> ComposeInput {
        guard ["left", "center", "right"].contains(alignment) else { return input }
        let prefix = (input.text as NSString).substring(to: min(input.text.utf16.count, max(0, input.selection.lowerUTF16)))
        let row = prefix.components(separatedBy: "\n").count - 1
        var metadata = input.lineMetadata
        guard row < metadata.count else { return input }
        metadata[row] = .init(alignment: alignment, wrap: wrap)
        return .init(text: input.text, lineMetadata: metadata, selection: input.selection, duration: input.duration, silence: input.silence)
    }
}

struct ComposeTools {
    let textColor: Bool
    let tiles: Bool
    let icons: [String]
    init(drawing: BoardDrawing?) {
        textColor = drawing?.allowsTextColor == true
        tiles = drawing?.allowsTiles == true
        icons = drawing?.allowedIcons ?? []
    }
}

struct ComposePreviewNotice {
    enum State: Equatable { case live, stale, offline }
    let state: State
    let clipped: Bool
    init(diagnosticsData: Data?, stale: Bool, online: Bool) {
        state = !online ? .offline : stale ? .stale : .live
        clipped = diagnosticsData.flatMap { try? ComposePreviewDiagnostics(rawData: $0).hasClippedContent } ?? false
    }
    var label: String {
        switch state {
        case .live: "Live preview · Not sent yet"
        case .stale: "Last preview · Updating required"
        case .offline: "Last preview · Offline"
        }
    }
}
