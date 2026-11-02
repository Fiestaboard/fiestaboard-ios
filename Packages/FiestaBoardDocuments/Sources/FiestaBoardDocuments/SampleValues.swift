import Foundation

/// The demo's stand-in for the server's evaluation: variables become the sample catalog's values
/// and simple formulas a plausible result, so the local board reads like a board ("72° SUNNY")
/// instead of printing token names. Used only where no server renders (the demo); never sent.
public enum SampleValues {
    /// Rows with every variable and formula replaced by text; tiles and fills are kept as tokens.
    public static func resolve(_ rows: [String], catalog: VariableCatalog) -> [String] {
        rows.map { row in
            TemplateSyntax.fragments(row).map { fragment -> String in
                switch fragment.kind {
                case .expression: return variable(String(fragment.source.dropFirst(2).dropLast(2)), catalog)
                case .formula:
                    var expression = String(fragment.source.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                    if expression.hasPrefix("=") { expression.removeFirst() }
                    return formula(expression.trimmingCharacters(in: .whitespaces), catalog)
                default: return fragment.source
                }
            }.joined()
        }
    }

    static func lookup(_ path: String, _ catalog: VariableCatalog) -> String? {
        let segments = path.split(separator: ".").map(String.init)
        guard segments.count >= 2,
              let plugin = catalog.plugins.first(where: { $0.id.caseInsensitiveCompare(segments[0]) == .orderedSame }),
              let field = plugin.fields.first(where: { $0.name.caseInsensitiveCompare(segments[1]) == .orderedSame }) else { return nil }
        return field.preview ?? ""
    }

    static func variable(_ inner: String, _ catalog: VariableCatalog) -> String {
        let parts = inner.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard var value = parts.first.flatMap({ lookup($0, catalog) }) else { return "???" }
        for filter in parts.dropFirst() {
            let pieces = filter.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = pieces.count > 1 ? Int(pieces[1]) : nil
            switch (pieces[0].lowercased(), argument) {
            // The server's filters: `pad:N` is `ljust(N)[:N]`, `truncate:N` cuts to N, and
            // `zeropad:N` left-pads with zeros, keeping a leading minus
            // (`src/templates/engine.py`).
            case ("pad", let n?): value = String((value + String(repeating: " ", count: max(0, n - value.count))).prefix(max(0, n)))
            case ("truncate", let n?): value = String(value.prefix(max(0, n)))
            case ("zeropad", let n?) where n > 0:
                let negative = value.hasPrefix("-")
                let digits = negative ? String(value.dropFirst()) : value
                let width = negative ? n - 1 : n
                value = (negative ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
            case ("lower", _): value = value.lowercased()
            case ("upper", _): value = value.uppercased()
            default: break
            }
        }
        return value
    }

    /// `IF(path op number, "A", "B")` against the sample values, `UPPER(path)`, a bare path, or the
    /// first string literal; otherwise `???` (what the board shows for a formula it can't work out).
    static func formula(_ expression: String, _ catalog: VariableCatalog) -> String {
        let pattern = #"^IF\(\s*([A-Za-z_][\w.]*)\s*(>=|<=|!=|==|=|>|<)\s*(-?\d+(?:\.\d+)?)\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\)$"#
        if let match = expression.range(of: pattern, options: [.regularExpression, .caseInsensitive]) , match.lowerBound == expression.startIndex,
           let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let result = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)) {
            func group(_ i: Int) -> String { Range(result.range(at: i), in: expression).map { String(expression[$0]) } ?? "" }
            guard let left = lookup(group(1), catalog).flatMap({ Double($0.filter { "-0123456789.".contains($0) }) }),
                  let right = Double(group(3)) else { return "???" }
            let truth: Bool
            switch group(2) {
            case ">": truth = left > right
            case "<": truth = left < right
            case ">=": truth = left >= right
            case "<=": truth = left <= right
            case "!=": truth = left != right
            default: truth = left == right
            }
            return truth ? group(4) : group(5)
        }
        let upper = #"^UPPER\(\s*([A-Za-z_][\w.]*)\s*\)$"#
        if expression.range(of: upper, options: [.regularExpression, .caseInsensitive]) != nil {
            let path = expression.dropFirst(6).dropLast().trimmingCharacters(in: .whitespaces)
            return lookup(path, catalog)?.uppercased() ?? "???"
        }
        if let value = lookup(expression, catalog) { return value }
        if let literal = expression.range(of: #""[^"]*""#, options: .regularExpression) {
            return String(expression[literal].dropFirst().dropLast())
        }
        return "???"
    }
}
