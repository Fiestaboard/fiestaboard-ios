import Foundation

/// What a `{{…}}` token looks like and says in the document editor (PLAN B13, B31). Pure: the
/// app draws it (`TemplateChipRenderer`), tests read it. Never evaluates anything.
public struct TemplateChip: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        /// Violet pill with the variable's path and nested filter sub-chips.
        case variable
        /// Same pill with the warning treatment: amber outline, "!" and a reason for the board's `???`.
        case unknownVariable(reason: String)
        /// Amber ƒ pill with the start of the expression.
        case formula
        /// A real board tile in this colour (board colour name, lowercase).
        case tile(color: String)
        /// Green flexible-space chip.
        case fill
        /// LED colour span: label is the span text, drawn in `color` (a board colour name or `#rrggbb`).
        case span(color: String)
        /// LED icon chip.
        case icon
    }

    public let style: Style
    /// The chip's main label (variable path, formula preview, span text, icon name…).
    public let title: String
    /// Variable filters in order (`pad:3`), drawn as sub-chips inside the pill.
    public let filters: [String]
    /// VoiceOver label (B31): "variable weather.temperature, filter pad 3", "red tile", "formula, IF(…".
    public let accessibilityLabel: String

    public static let formulaPreviewLength = 20

    /// The plugin a variable reads from (`weather` in `weather.temperature`); nil for other kinds.
    /// The chip shows it as a small source mark, so the label itself can be just the field.
    public var plugin: String? {
        switch style {
        case .variable, .unknownVariable:
            guard let dot = title.firstIndex(of: "."), dot != title.startIndex else { return nil }
            return String(title[..<dot])
        default: return nil
        }
    }

    /// Characters of a formula's expression shown in its compact pill when it starts with neither a
    /// function nor a variable (`ƒ 1+2`).
    public static let compactFormulaLength = 6

    /// The compact label of a formula, shared with Android (`TemplateChips.compactFormulaName`):
    /// the outer function as `IF(…)` (`NOW()` when it takes no arguments), else the first 6
    /// characters and "…".
    public static func formulaHead(_ expression: String) -> String {
        let flat = expression.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let match = flat.range(of: #"^[A-Za-z_][A-Za-z0-9_]*\s*\("#, options: .regularExpression) {
            let name = flat[match].dropLast().trimmingCharacters(in: .whitespaces).uppercased()
            let rest = flat[match.upperBound...].trimmingCharacters(in: .whitespaces)
            return name + (rest == ")" ? "()" : "(…)")
        }
        return flat.count > compactFormulaLength ? String(flat.prefix(compactFormulaLength)) + "…" : flat
    }
    /// A variable's short name longer than this falls back to its last segment (AND-P1).
    public static let shortNameLimit = 12

    /// The short label drawn inside a compact chip (shared design with AND-P1, a48ce26): for a
    /// variable, the field without its plugin and with numeric indexes dropped, or only the last
    /// segment when that is longer than 12 characters (`temperature`, `AAPL.price`,
    /// `stations.0.name` → `name`); for a formula, its first 9 characters and "…"; `fill` or
    /// `fill -` for flexible space. The full name lives in `title`/`filters` and the spoken label.
    public var shortTitle: String {
        switch style {
        case .variable, .unknownVariable:
            guard plugin != nil else { return title }
            let segments = title.split(separator: ".").dropFirst().map(String.init).filter { Int($0) == nil }
            guard !segments.isEmpty else { return title }
            let joined = segments.joined(separator: ".")
            return joined.count > Self.shortNameLimit ? segments.last! : joined
        case .formula:
            // Fully compact, like a variable chip (iOS-F1): the outer function's name (`IF`), else
            // the first variable's short name, else the expression's start. The callout, the
            // detail line and VoiceOver carry the whole formula.
            guard title != "new formula" else { return "new" }
            return Self.formulaHead(title.hasSuffix("…") ? String(title.dropLast()) : title)
        case .fill:
            guard title.lowercased() != "fill_space" else { return "fill" }
            let character = title.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            return character.isEmpty ? "fill" : "fill \(character)"
        default: return title
        }
    }

    /// The source mark drawn on a dot at the chip's start: the plugin's initial, upper-case
    /// (`W` for weather), or "!" for a variable that will draw ???. Nil for other kinds.
    public var sourceMark: String? {
        switch style {
        case .unknownVariable: return "!"
        case .variable: return plugin?.first.map { String($0).uppercased() }
        case .formula: return "ƒ"
        default: return nil
        }
    }

    /// Filters as tiny badges inside a compact chip (AND-P1): `pad:3` → `3`, `truncate:5` → `≤5`,
    /// `zeropad:2` → `02`, `upper` → `AB`, `lower` → `ab`, `wrap` → `↵`; anything else as written.
    public var compactFilters: [String] {
        filters.map { filter in
            let pieces = filter.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let name = pieces.first?.lowercased() ?? filter
            let argument = pieces.count > 1 ? pieces[1] : ""
            switch name {
            case "pad" where !argument.isEmpty: return argument
            case "truncate" where !argument.isEmpty: return "≤" + argument
            case "zeropad" where !argument.isEmpty: return "0" + argument
            case "upper": return "AB"
            case "lower": return "ab"
            case "wrap": return "↵"
            default: return filter
            }
        }
    }

    /// The full source for the detail line under the document (`chip-detail`): `weather.temperature
    /// | pad:3`, a formula in full, the reason when the board will show ???.
    public static func detail(source: String, chip: TemplateChip?) -> String {
        var inner = source.hasPrefix("{{") ? String(source.dropFirst(2).dropLast(2)) : String(source.dropFirst().dropLast())
        inner = inner.trimmingCharacters(in: .whitespaces)
        guard let chip else { return inner }
        switch chip.style {
        case .variable: return ([chip.title] + chip.filters).joined(separator: " | ")
        case .unknownVariable(let reason): return ([chip.title] + chip.filters).joined(separator: " | ") + " — " + reason
        case .formula:
            if inner.hasPrefix("=") { inner = String(inner.dropFirst()).trimmingCharacters(in: .whitespaces) }
            return "ƒ " + (inner.isEmpty ? chip.title : inner)
        default: return inner
        }
    }

    /// How many board cells the token fills, when that is known before the server renders it
    /// (PLAN B16 column guide): a colour tile is one; `pad:N` makes a variable exactly N; with a
    /// known value length (`sampleLength`), `truncate:N` caps it and `zeropad:N` widens it, as the
    /// server's filters do. An unknown variable renders `???`. Formulas, flexible space, spans and
    /// icons are unknown (nil): their width depends on the render.
    public func boardWidth(sampleLength: Int? = nil) -> Int? {
        switch style {
        case .tile: return 1
        case .variable, .unknownVariable:
            var width: Int?
            if case .unknownVariable = style { width = 3 } else { width = sampleLength }
            for filter in filters {
                let pieces = filter.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard let name = pieces.first?.lowercased() else { continue }
                let argument = pieces.count > 1 ? Int(pieces[1]) : nil
                switch (name, argument) {
                case ("pad", let n?): width = max(0, n)
                case ("truncate", let n?): width = width.map { min($0, max(0, n)) }
                case ("zeropad", let n?): width = width.map { max($0, n) }
                default: break
                }
            }
            return width
        case .formula, .fill, .span, .icon: return nil
        }
    }

    /// Board colour names a tile may use, normalised (`purple` is violet, `filled` is black).
    public static func tileColor(_ name: String) -> String {
        switch name.lowercased() {
        case "purple": return "violet"
        case "filled": return "black"
        default: return name.lowercased()
        }
    }

    public init(style: Style, title: String, filters: [String] = [], accessibilityLabel: String) {
        self.style = style; self.title = title; self.filters = filters; self.accessibilityLabel = accessibilityLabel
    }

    /// The chip for one non-text fragment. `variables` decides the unknown-variable warning;
    /// without an authoritative catalog every variable is drawn as known.
    public init?(fragment: TemplateSyntax.Fragment, variables: VariableCatalog? = nil) {
        let source = fragment.source
        let inner = source.hasPrefix("{{") ? String(source.dropFirst(2).dropLast(2)) : String(source.dropFirst().dropLast())
        switch fragment.kind {
        case .text: return nil
        case .tile:
            let color = Self.tileColor(inner.trimmingCharacters(in: .whitespaces))
            self.init(style: .tile(color: color), title: color, accessibilityLabel: "\(color) tile")
        case .fill:
            let label = inner.lowercased() == "fill_space" ? "fill_space" : inner
            let spoken = inner.lowercased() == "fill_space" ? "fill space" : "fill space, repeat \(inner.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "")"
            self.init(style: .fill, title: label, accessibilityLabel: spoken)
        case .formula:
            var expression = inner.trimmingCharacters(in: .whitespaces)
            if expression.hasPrefix("=") { expression.removeFirst() }
            expression = expression.trimmingCharacters(in: .whitespaces)
            let preview = expression.isEmpty ? "new formula"
                : (expression.count > Self.formulaPreviewLength ? String(expression.prefix(Self.formulaPreviewLength)) + "…" : expression)
            self.init(style: .formula, title: preview, accessibilityLabel: "formula, \(preview)")
        case .span:
            let parts = inner.split(separator: ":", maxSplits: 1).map(String.init)
            let color = parts.first?.split(separator: "/").first.map(String.init) ?? ""
            let text = parts.count > 1 ? parts[1] : ""
            self.init(style: .span(color: color.lowercased()), title: text, accessibilityLabel: "\(text), in \(color.lowercased())")
        case .icon:
            let name = String(inner.dropFirst(5))
            self.init(style: .icon, title: name, accessibilityLabel: "icon \(name)")
        case .expression:
            let parts = inner.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let path = parts.first ?? inner
            let filters = parts.dropFirst().filter { !$0.isEmpty }
            let spokenFilters = filters.map { ", filter " + $0.replacingOccurrences(of: ":", with: " ") }.joined()
            if let variables, case .unknown(let reason) = variables.status(of: path) {
                self.init(style: .unknownVariable(reason: reason), title: path, filters: Array(filters),
                          accessibilityLabel: "variable \(path)\(spokenFilters), warning: \(reason)")
            } else {
                self.init(style: .variable, title: path, filters: Array(filters), accessibilityLabel: "variable \(path)\(spokenFilters)")
            }
        }
    }
}

/// The variables a page may use, by plugin (PLAN B22's data, without its picker). Wave 2 ships a
/// built-in sample; iOS-F1 replaces the source with `GET /v1/variables` (`Service+Catalog.swift`).
public struct VariableCatalog: Equatable, Sendable {
    public struct Field: Equatable, Sendable {
        public let name: String
        /// A short sample value, shown faded beside the field (B22: 12 characters).
        public let preview: String?
        public init(_ name: String, preview: String? = nil) { self.name = name; self.preview = preview }
    }
    public struct Plugin: Equatable, Sendable {
        public let id: String
        public let name: String
        public let fields: [Field]
        public init(id: String, name: String, fields: [Field]) { self.id = id; self.name = name; self.fields = fields }
    }
    public enum Status: Equatable, Sendable { case known, unknown(reason: String) }

    public let plugins: [Plugin]
    /// Only an authoritative catalog (the server's own list) may mark a variable unknown.
    public let isAuthoritative: Bool

    public init(plugins: [Plugin], isAuthoritative: Bool) { self.plugins = plugins; self.isAuthoritative = isAuthoritative }

    /// `known` unless the catalog is authoritative and the plugin or its field is missing. Array
    /// paths (`plugin.items.0.name`) are known when their first segment is a field.
    public func status(of path: String) -> Status {
        guard isAuthoritative else { return .known }
        let segments = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let pluginID = segments.first, !pluginID.isEmpty else { return .unknown(reason: "This isn't a variable name. The board shows ??? here.") }
        guard let plugin = plugins.first(where: { $0.id.caseInsensitiveCompare(pluginID) == .orderedSame }) else {
            return .unknown(reason: "“\(pluginID)” isn't a plugin set up on this server. The board shows ??? here.")
        }
        guard segments.count > 1 else { return .unknown(reason: "Choose a \(plugin.name) field. The board shows ??? here.") }
        let field = segments[1]
        guard plugin.fields.contains(where: { $0.name.caseInsensitiveCompare(field) == .orderedSame }) else {
            return .unknown(reason: "\(plugin.name) has no “\(field)” value. The board shows ??? here.")
        }
        return .known
    }

    /// The sample value of a `plugin.field` path (case-insensitive), when the catalog has one.
    public func preview(of path: String) -> String? {
        let segments = path.split(separator: ".").map(String.init)
        guard segments.count >= 2,
              let plugin = plugins.first(where: { $0.id.caseInsensitiveCompare(segments[0]) == .orderedSame }),
              let field = plugin.fields.first(where: { $0.name.caseInsensitiveCompare(segments[1]) == .orderedSame }) else { return nil }
        return field.preview
    }

    /// The sample catalog shown until the server's list is wired (iOS-F1). Mirrors the fixture
    /// pages' variables (`date_time`, `weather`) plus a few common plugins.
    public static func sample(authoritative: Bool) -> VariableCatalog {
        VariableCatalog(plugins: [
            Plugin(id: "date_time", name: "Date & Time", fields: [
                Field("time", preview: "08:15"), Field("time_12h", preview: "8:15 AM"), Field("date", preview: "NOV 1"),
                Field("day_of_week", preview: "SUNDAY"), Field("month", preview: "NOVEMBER"), Field("year", preview: "2026")]),
            Plugin(id: "weather", name: "Weather", fields: [
                Field("temperature", preview: "72"), Field("condition", preview: "SUNNY"), Field("high", preview: "78"),
                Field("low", preview: "61"), Field("feels_like", preview: "70"), Field("humidity", preview: "40")]),
            Plugin(id: "stocks", name: "Stocks", fields: [
                Field("symbol", preview: "AAPL"), Field("price", preview: "231.40"), Field("change_percent", preview: "+1.2%")]),
            Plugin(id: "home_assistant", name: "Home Assistant", fields: [
                Field("front_door", preview: "LOCKED"), Field("living_room_temperature", preview: "70")]),
        ], isAuthoritative: authoritative)
    }
}

/// What the toolbar's insert buttons put at the caret (PLAN B15). Simple, fixed lists in wave 2;
/// the searchable pickers of iOS-F1 replace the menus, not these sources.
public enum TemplateInsertion {
    /// Board colours in the web's order (`ColorPickerContent.tsx`).
    public static let colors = ["red", "orange", "yellow", "green", "blue", "violet", "white", "black"]
    public static func color(_ name: String) -> String { "{{\(name)}}" }
    /// Code 62: a degree sign on most boards, a heart on some; typed as the literal character.
    public static let degree = "°"
    public struct Formatting: Equatable, Sendable {
        public let title: String
        public let source: String
        public let detail: String
    }
    public static let formatting: [Formatting] = [
        Formatting(title: "Fill space", source: "{{fill_space}}", detail: "Pushes what follows to the end of the row"),
        Formatting(title: "Fill with dashes", source: "{{fill_space_repeat:-}}", detail: "Fills the rest of the row with -"),
        Formatting(title: "Fill with =", source: "{{fill_space_repeat:=}}", detail: "Fills the rest of the row with ="),
        Formatting(title: "Fill with dots", source: "{{fill_space_repeat:.}}", detail: "Fills the rest of the row with ."),
    ]
    public static func variable(_ plugin: String, _ field: String) -> String { "{{\(plugin).\(field)}}" }
    /// `{{= expression }}`, or nil when the expression is blank.
    public static func formula(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("}}") else { return nil }
        return "{{= \(trimmed) }}"
    }
}
