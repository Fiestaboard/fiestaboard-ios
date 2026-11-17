import UIKit

/// Row numbers beside the document's paragraphs (PLAN §3.2). A sibling of the text view, not a
/// subview: a `UITextView` is one accessibility element and would hide its children, so the
/// per-row identifiers (`documentRow_<n>`, B12) live here. Positions follow TextKit 1 line
/// fragments of each paragraph's first glyph; the caret row's number is brighter.
final class RowGutterView: UIView {
    static let width: CGFloat = 34
    private var labels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityContainerType = .list
    }
    required init?(coder: NSCoder) { nil }

    /// - Parameters:
    ///   - textView: the document text view (TextKit 1).
    ///   - rows: source text of every paragraph, for the row elements' accessibility values.
    ///   - caretRows: rows touched by the caret/selection.
    ///   - boardRows: rows the board can show; later rows are numbered in the warning colour.
    func update(textView: UITextView, rows: [String], caretRows: ClosedRange<Int>, boardRows: Int) {
        let layout = textView.layoutManager
        let storage = textView.textStorage
        let text = storage.string as NSString
        layout.ensureLayout(for: textView.textContainer)
        // Paragraph start offsets in display (attachment) units.
        var starts: [Int] = [0]
        var index = 0
        while index < text.length {
            let range = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            guard range.location != NSNotFound else { break }
            starts.append(range.location + 1)
            index = range.location + 1
        }
        while labels.count < starts.count {
            let label = UILabel()
            label.textAlignment = .right
            label.isAccessibilityElement = true
            label.accessibilityTraits = .staticText
            addSubview(label)
            labels.append(label)
        }
        for (offset, label) in labels.enumerated() { label.isHidden = offset >= starts.count }
        let font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        for (row, start) in starts.enumerated() {
            let rect: CGRect
            if start >= text.length {
                rect = layout.extraLineFragmentRect.isEmpty && text.length > 0
                    ? layout.lineFragmentRect(forGlyphAt: max(0, layout.numberOfGlyphs - 1), effectiveRange: nil)
                    : layout.extraLineFragmentRect
            } else {
                let glyph = layout.glyphIndexForCharacter(at: start)
                rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let y = rect.minY + textView.textContainerInset.top - textView.contentOffset.y
            let label = labels[row]
            label.frame = CGRect(x: 0, y: y, width: Self.width - 8, height: max(rect.height, font.lineHeight))
            label.font = caretRows.contains(row) ? UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold) : font
            label.text = "\(row + 1)"
            let overflow = row >= boardRows
            label.textColor = overflow ? .systemOrange : (caretRows.contains(row) ? .label : .tertiaryLabel)
            label.accessibilityIdentifier = "documentRow_\(row + 1)"
            label.accessibilityLabel = "Row \(row + 1)"
            label.accessibilityValue = row < rows.count ? (rows[row].isEmpty ? "Empty" : rows[row]) : "Empty"
            if caretRows.contains(row) { label.accessibilityTraits = [.staticText, .selected] } else { label.accessibilityTraits = .staticText }
        }
        accessibilityElements = Array(labels.prefix(starts.count))
    }
}
