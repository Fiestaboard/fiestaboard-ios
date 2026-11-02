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
