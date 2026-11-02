import Foundation
import FiestaBoardDocuments

/// What the editor's pickers offer (PLAN B21, B22, B32): the server's `GET /v1/variables`
/// (variables by plugin, metadata, groups, colours, formatting), each plugin's
/// `GET /plugins/{id}/manifest` (name, icon, arrays) and `GET /v1/functions`. Pure values: the
/// app draws them; tests read them. Nothing here evaluates a template.
public struct TemplateCatalog: Equatable, Sendable {
    public struct Field: Equatable, Sendable, Identifiable {
        public var id: String { path }
        /// The name after the plugin (`temperature`, `stations.0.name`).
        public let name: String
        /// `plugin.name`, the token's inside.
        public let path: String
        public let preview: String?
        public let summary: String?
        /// Readable label (shared rule with Android `VariableTree`): the metadata's `label`, else
        /// the name in sentence case (`day_of_week` → `Day of week`, `AAPL.price` → `AAPL price`).
        public let label: String
        public init(name: String, path: String, preview: String? = nil, summary: String? = nil, label: String? = nil) {
            self.name = name; self.path = path; self.preview = preview; self.summary = summary
            self.label = label ?? TemplateCatalog.sentence(name)
        }
        /// The faded value beside a pill (B22: 12 characters, then "…").
        public var shortPreview: String? {
            guard let preview, !preview.isEmpty else { return nil }
            return preview.count > 12 ? String(preview.prefix(12)) + "…" : preview
        }
    }
    public struct Group: Equatable, Sendable, Identifiable {
        public var id: String { key ?? "" }
        /// The manifest's group id; nil for the ungrouped "General" fields.
        public let key: String?
        public let label: String
        public let fields: [Field]
    }
    /// One item of an array variable (`stations.0`), shown as an expandable row.
    public struct ArrayItem: Equatable, Sendable, Identifiable {
        public var id: Int { index }
        public let index: Int
        /// The item's label value (its `label_field` preview), when known.
        public let label: String?
        public let fields: [Field]
    }
    public struct ArrayVariable: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let items: [ArrayItem]
        /// Field names every item has, from the manifest or the `name.*.field` patterns.
        public let itemFields: [String]
    }
    public struct Plugin: Equatable, Sendable, Identifiable {
        public let id: String
        /// Readable name: the manifest's, else the id in Title Case (`date_time` → `Date Time`).
        public let name: String
        /// The manifest's icon name (Lucide, e.g. `cloud-sun`), when it has one.
        public let icon: String?
        public let groups: [Group]
        public let arrays: [ArrayVariable]
        public var fieldCount: Int { groups.reduce(0) { $0 + $1.fields.count } + arrays.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.fields.count } } }
    }
    public struct Formatting: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        /// Readable name (`fill_space` → `Fill space`).
        public let title: String
        public let syntax: String
        public let summary: String?
        /// `fill_space_repeat`: asks for a colour or a character before inserting.
        public var takesPattern: Bool { syntax.contains("fill_space_repeat") }
    }

    public let plugins: [Plugin]
    /// Colour names the server lists, in the web picker's order.
    public let colors: [String]
    public let formatting: [Formatting]
    /// False when the server reported its plugin system unavailable.
    public let pluginSystemEnabled: Bool
    /// The server's own list (authoritative for unknown-variable warnings) or a built-in sample.
    public let isServerCatalog: Bool

    public init(plugins: [Plugin], colors: [String], formatting: [Formatting], pluginSystemEnabled: Bool = true, isServerCatalog: Bool) {
        self.plugins = plugins; self.colors = colors; self.formatting = formatting
        self.pluginSystemEnabled = pluginSystemEnabled; self.isServerCatalog = isServerCatalog
    }

    /// B32: no plugin variables at all ("No template variables available…").
    public var hasVariables: Bool { plugins.contains { $0.fieldCount > 0 || !$0.arrays.isEmpty } }

    /// The web picker's colour order (`ColorPickerContent.tsx`).
    public static let colorOrder = ["red", "orange", "yellow", "green", "blue", "violet", "white", "black"]

    // MARK: Decoding

    /// The subset of `GET /plugins/{id}/manifest` the picker uses.
    public struct Manifest: Equatable, Sendable {
        public let name: String?
        public let icon: String?
        /// Array variables and their `label_field` / item field names.
        public let arrays: [String: (labelField: String?, itemFields: [String])]
        public static func == (lhs: Manifest, rhs: Manifest) -> Bool {
            lhs.name == rhs.name && lhs.icon == rhs.icon && lhs.arrays.keys.sorted() == rhs.arrays.keys.sorted()
                && lhs.arrays.keys.allSatisfy { lhs.arrays[$0]!.labelField == rhs.arrays[$0]!.labelField && lhs.arrays[$0]!.itemFields == rhs.arrays[$0]!.itemFields }
        }
        public init(name: String? = nil, icon: String? = nil, arrays: [String: (labelField: String?, itemFields: [String])] = [:]) {
            self.name = name; self.icon = icon; self.arrays = arrays
        }
        public init(data: Data) throws {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FiestaBoardError.invalidResponse }
            name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            icon = (object["icon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            var arrays: [String: (labelField: String?, itemFields: [String])] = [:]
            if let variables = object["variables"] as? [String: Any], let declared = variables["arrays"] as? [String: Any] {
                for (key, value) in declared {
                    let config = value as? [String: Any] ?? [:]
                    let fields: [String]
                    if let list = config["item_fields"] as? [String] { fields = list }
                    else if let map = config["item_fields"] as? [String: Any] { fields = map.keys.sorted() }
                    else { fields = [] }
                    arrays[key] = (config["label_field"] as? String, fields)
                }
            }
            self.arrays = arrays
        }
    }

    /// Decodes `GET /v1/variables` (also the shape of the internal `GET /templates/variables`),
    /// combining it with the manifests that loaded. Plugins are sorted by their readable name;
    /// fields keep the server's order; groups follow the first field that uses them, with the
    /// ungrouped "General" fields last (as the web picker).
    ///
    /// `arrayData` (W4) is each plugin's live data from `POST /displays/raw/batch`, as the web
    /// picker reads it: a 10.3.2 server lists arrays only as `name.*.field` patterns, so the items
    /// (`stations.0`, label from `label_field`) come from that data. Indexed paths in the
    /// variables list are used only when a plugin has no live data for the array.
    public init(variablesData data: Data, manifests: [String: Manifest] = [:], arrayData: [String: [String: Any]] = [:]) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let variables = object["variables"] as? [String: Any] else { throw FiestaBoardError.invalidResponse }
        let metadata = object["variable_metadata"] as? [String: Any] ?? [:]
        let groupDefinitions = object["variable_groups"] as? [String: Any] ?? [:]
        var plugins: [Plugin] = []
        for (pluginID, raw) in variables {
            guard let names = raw as? [String] else { continue }
            let manifest = manifests[pluginID]
            let pluginMeta = metadata[pluginID] as? [String: Any] ?? [:]
            let groupLabels = (groupDefinitions[pluginID] as? [String: Any] ?? [:]).compactMapValues { value -> String? in
                (value as? [String: Any])?["label"] as? String ?? (value as? String)
            }
            func meta(_ name: String) -> [String: Any] { pluginMeta[name] as? [String: Any] ?? [:] }
            func field(_ name: String) -> Field {
                let info = meta(name)
                let preview: String? = {
                    if let text = info["preview"] as? String { return text }
                    if let number = info["preview"] as? NSNumber { return number.stringValue }
                    if let text = info["example"] as? String { return text }
                    return nil
                }()
                let label = (info["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return Field(name: name, path: pluginID + "." + name, preview: preview, summary: info["description"] as? String, label: label)
            }
            // Array variables: declared in the manifest, or seen as `name.N.field` / `name.*.field`.
            var arrayNames = manifest.map { Array($0.arrays.keys) } ?? []
            for name in names {
                let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                if parts.count >= 3, parts[1] == "*" || Int(parts[1]) != nil, !arrayNames.contains(parts[0]) { arrayNames.append(parts[0]) }
            }
            var arrays: [ArrayVariable] = []
            for arrayName in arrayNames.sorted() {
                var fieldNames = manifest?.arrays[arrayName]?.itemFields ?? []
                var items: [Int: [Field]] = [:]
                for name in names where name.hasPrefix(arrayName + ".") {
                    let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                    guard parts.count >= 3 else { continue }
                    let rest = parts[2...].joined(separator: ".")
                    if parts[1] == "*" { if !fieldNames.contains(rest) { fieldNames.append(rest) }; continue }
                    guard let index = Int(parts[1]) else { continue }
                    // An item's pill reads as its own field (`Bikes`), not the whole indexed path.
                    let full = field(name)
                    items[index, default: []].append(Field(name: full.name, path: full.path, preview: full.preview, summary: full.summary,
                                                           label: meta(name)["label"] as? String ?? Self.sentence(rest)))
                    if !fieldNames.contains(rest) { fieldNames.append(rest) }
                }
                let labelField = manifest?.arrays[arrayName]?.labelField ?? "name"
                if let live = arrayData[pluginID]?[arrayName] as? [Any] {
                    items = [:]
                    var liveLabels: [Int: String] = [:]
                    for (index, element) in live.enumerated() {
                        guard let item = element as? [String: Any] else { continue }
                        let names = fieldNames.isEmpty ? item.keys.sorted() : fieldNames
                        items[index] = names.map { name in
                            let full = "\(arrayName).\(index).\(name)"
                            return Field(name: full, path: pluginID + "." + full, preview: Self.previewText(item[name]),
                                         summary: meta("\(arrayName).*.\(name)")["description"] as? String,
                                         label: meta("\(arrayName).*.\(name)")["label"] as? String ?? Self.sentence(name))
                        }
                        liveLabels[index] = Self.previewText(item[labelField])
                    }
                    arrays.append(ArrayVariable(name: arrayName, items: items.keys.sorted().map { ArrayItem(index: $0, label: liveLabels[$0], fields: items[$0]!) },
                                                itemFields: fieldNames))
                    continue
                }
                let built = items.keys.sorted().map { index -> ArrayItem in
                    let fields = items[index]!
                    let label = fields.first { $0.name == "\(arrayName).\(index).\(labelField)" }?.preview
                    return ArrayItem(index: index, label: label, fields: fields)
                }
                arrays.append(ArrayVariable(name: arrayName, items: built, itemFields: fieldNames))
            }
            let simple = names.filter { name in !arrayNames.contains { name == $0 || name.hasPrefix($0 + ".") } }
            var order: [String?] = []
            var byGroup: [String?: [Field]] = [:]
            for name in simple {
                let declared = meta(name)["group"] as? String
                let key = declared.flatMap { groupLabels[$0] != nil ? $0 : nil }
                if byGroup[key] == nil { order.append(key) }
                byGroup[key, default: []].append(field(name))
            }
            // Ungrouped fields go last, under "General", only when the plugin declares groups.
            order = order.filter { $0 != nil } + order.filter { $0 == nil }
            let groups = order.map { key in
                Group(key: key, label: key.flatMap { groupLabels[$0].map { $0.isEmpty ? Self.titleCase(key!) : $0 } } ?? (groupLabels.isEmpty ? "" : "General"),
                      fields: byGroup[key] ?? [])
            }
            plugins.append(Plugin(id: pluginID, name: manifest?.name ?? Self.titleCase(pluginID), icon: manifest?.icon,
                                  groups: groups, arrays: arrays))
        }
        plugins.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let listed = (object["colors"] as? [String: Any]).map { Set($0.keys.map { $0.lowercased() }) }
        let colors = listed.map { names in Self.colorOrder.filter { names.contains($0) } } ?? Self.colorOrder
        var formatting: [Formatting] = []
        if let entries = object["formatting"] as? [String: Any] {
            for key in entries.keys.sorted(by: Self.formattingOrder) {
                guard let entry = entries[key] as? [String: Any], let syntax = entry["syntax"] as? String else { continue }
                formatting.append(Formatting(key: key, title: Self.sentenceCase(key), syntax: syntax, summary: entry["description"] as? String))
            }
        }
        self.init(plugins: plugins, colors: colors, formatting: formatting,
                  pluginSystemEnabled: object["plugin_system_enabled"] as? Bool ?? true, isServerCatalog: true)
    }

    private static func formattingOrder(_ lhs: String, _ rhs: String) -> Bool {
        let known = ["fill_space", "fill_space_repeat"]
        switch (known.firstIndex(of: lhs), known.firstIndex(of: rhs)) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs < rhs
        }
    }

    /// `date_time` → `Date Time`, `baywheels` → `Baywheels`, `home-assistant` → `Home Assistant`.
    /// A live value as a short preview (strings as they are, numbers without a trailing `.0`).
    static func previewText(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        default: return nil
        }
    }

    public static func titleCase(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
    /// Field names in sentence case (Android `Naming.sentence`): split on `._-` and spaces; a word
    /// already in capitals (`AAPL`) keeps them; the first word is capitalised, the rest lowercased.
    public static func sentence(_ id: String) -> String {
        let words = id.split(whereSeparator: { "._- ".contains($0) }).map(String.init)
        return words.enumerated().map { index, word in
            if word.count > 1 && word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return word }
            return index == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
        }.joined(separator: " ")
    }
    /// `fill_space_repeat` → `Fill space repeat`.
    public static func sentenceCase(_ id: String) -> String {
        let words = id.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: Search (B22)

    /// Words of a name for search: split on `.`, `_`, `-` and spaces, lowercased.
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { ".-_ ".contains($0) }).map(String.init)
    }

    /// Whether one field matches the query: every query word (split like names) is the start of a
    /// word of the plugin id, plugin name, group, array or field, or the whole query occurs in the
    /// dotted path (`weather.temp`, `feels_like`, `feels like`, `temp`).
    public static func matches(_ query: String, plugin: Plugin, field: Field, context: String = "") -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if field.path.lowercased().contains(trimmed) || plugin.name.lowercased().contains(trimmed) { return true }
        let haystack = words(plugin.id) + words(plugin.name) + words(field.name) + words(field.label) + words(context)
        return words(trimmed).allSatisfy { term in haystack.contains { $0.hasPrefix(term) || (term.count >= 3 && $0.contains(term)) } }
    }

    /// The catalog narrowed to a query: plugins with at least one matching field (or whose name
    /// matches, which keeps all their fields), empty groups and arrays dropped.
    public func filtered(_ query: String) -> [Plugin] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return plugins }
        return plugins.compactMap { plugin in
            let groups = plugin.groups.compactMap { group -> Group? in
                let fields = group.fields.filter { Self.matches(trimmed, plugin: plugin, field: $0, context: group.label) }
                return fields.isEmpty ? nil : Group(key: group.key, label: group.label, fields: fields)
            }
            let arrays = plugin.arrays.compactMap { array -> ArrayVariable? in
                let items = array.items.compactMap { item -> ArrayItem? in
                    let fields = item.fields.filter { Self.matches(trimmed, plugin: plugin, field: $0, context: array.name + " " + (item.label ?? "")) }
                    return fields.isEmpty ? nil : ArrayItem(index: item.index, label: item.label, fields: fields)
                }
                let named = Self.matches(trimmed, plugin: plugin, field: Field(name: array.name, path: plugin.id + "." + array.name))
                if items.isEmpty && !(named && array.items.isEmpty) { return nil }
                return ArrayVariable(name: array.name, items: items, itemFields: array.itemFields)
            }
            guard !groups.isEmpty || !arrays.isEmpty else { return nil }
            return Plugin(id: plugin.id, name: plugin.name, icon: plugin.icon, groups: groups, arrays: arrays)
        }
    }

    // MARK: Chips

    /// The chips' view of the catalog (unknown-variable warning, column-guide widths). Only the
    /// server's own list is authoritative.
    public var variableCatalog: VariableCatalog {
        VariableCatalog(plugins: plugins.map { plugin in
            var fields = plugin.groups.flatMap(\.fields).map { VariableCatalog.Field($0.name, preview: $0.preview) }
            fields += plugin.arrays.map { VariableCatalog.Field($0.name) }
            return VariableCatalog.Plugin(id: plugin.id, name: plugin.name, fields: fields)
        }, isAuthoritative: isServerCatalog)
    }

    // MARK: Fallback

    /// Used when the server's list can't be read (the demo, or an older server): the built-in
    /// sample, which may only warn about unknown variables in the demo (whose variables it is).
    public static func sample(authoritative: Bool) -> TemplateCatalog {
        let sample = VariableCatalog.sample(authoritative: authoritative)
        let icons = ["date_time": "clock", "weather": "cloud-sun", "stocks": "trending-up", "home_assistant": "house"]
        return TemplateCatalog(plugins: sample.plugins.map { plugin in
            Plugin(id: plugin.id, name: plugin.name, icon: icons[plugin.id],
                   groups: [Group(key: nil, label: "", fields: plugin.fields.map { Field(name: $0.name, path: plugin.id + "." + $0.name, preview: $0.preview) })],
                   arrays: [])
        }.sorted { $0.name < $1.name }, colors: colorOrder, formatting: [
            Formatting(key: "fill_space", title: "Fill space", syntax: "{{fill_space}}",
                       summary: "Expands to fill remaining space on the line. Use multiple for multi-column layouts."),
            Formatting(key: "fill_space_repeat", title: "Fill space repeat", syntax: "{{fill_space_repeat:pattern}}",
                       summary: "Fills remaining space with repeating colors or characters."),
        ], isServerCatalog: authoritative)
    }
}

/// `GET /v1/functions`: `{functions: {NAME: {category, signature, summary}}}` (PLAN B21).
public struct FunctionCatalog: Equatable, Sendable {
    public struct Function: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let category: String
        public let signature: String
        public let summary: String
        public init(name: String, category: String, signature: String, summary: String) {
            self.name = name; self.category = category; self.signature = signature; self.summary = summary
        }
    }
    public struct Category: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let functions: [Function]
    }

    /// Known categories in the picker's order; any other category is appended, sorted (the web's
    /// `categoriesToRender`: an unknown category is never dropped).
    public static let categoryOrder = ["logic", "array", "date", "math", "text", "convert", "color"]

    public let categories: [Category]
    public var names: Set<String> { Set(categories.flatMap { $0.functions.map(\.name) }) }

    public init(functions: [Function]) {
        let grouped = Dictionary(grouping: functions, by: \.category)
        let known = Self.categoryOrder.filter { grouped[$0]?.isEmpty == false }
        let unknown = grouped.keys.filter { !Self.categoryOrder.contains($0) && grouped[$0]?.isEmpty == false }.sorted()
        categories = (known + unknown).map { name in
            Category(name: name, functions: grouped[name]!.sorted { $0.name < $1.name })
        }
    }

    public init(data: Data) throws {
        struct Entry: Decodable { let category: String; let signature: String?; let summary: String? }
        struct Reply: Decodable { let functions: [String: Entry] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw FiestaBoardError.invalidResponse }
        self.init(functions: reply.functions.map { name, entry in
            Function(name: name, category: entry.category, signature: entry.signature ?? "\(name)()", summary: entry.summary ?? "")
        })
    }

    /// Readable category title (`convert` → `Conversion`, unknown → Title Case).
    public static func title(_ category: String) -> String {
        switch category {
        case "logic": return "Logic"
        case "array": return "Array"
        case "date": return "Date"
        case "math": return "Math"
        case "text": return "Text"
        case "convert": return "Conversion"
        case "color": return "Color"
        default: return TemplateCatalog.titleCase(category)
        }
    }

    /// A representative built-in list for the demo and when `/v1/functions` can't be read.
    public static let builtIn = FunctionCatalog(functions: [
        Function(name: "IF", category: "logic", signature: "IF(condition, then, else)", summary: "Returns then when the condition is true, else otherwise."),
        Function(name: "AND", category: "logic", signature: "AND(a, b, …)", summary: "True when every argument is true."),
        Function(name: "OR", category: "logic", signature: "OR(a, b, …)", summary: "True when any argument is true."),
        Function(name: "NOT", category: "logic", signature: "NOT(value)", summary: "The opposite of a true/false value."),
        Function(name: "COUNT", category: "array", signature: "COUNT(list)", summary: "How many items a list has."),
        Function(name: "JOIN", category: "array", signature: "JOIN(list, separator)", summary: "Joins a list's items into text."),
        Function(name: "NOW", category: "date", signature: "NOW()", summary: "The current date and time."),
        Function(name: "FORMAT_DATE", category: "date", signature: "FORMAT_DATE(date, format)", summary: "Formats a date."),
        Function(name: "DAYS_UNTIL", category: "date", signature: "DAYS_UNTIL(date)", summary: "Days from today until a date."),
        Function(name: "ROUND", category: "math", signature: "ROUND(number, digits)", summary: "Rounds a number."),
        Function(name: "ABS", category: "math", signature: "ABS(number)", summary: "A number without its sign."),
        Function(name: "MIN", category: "math", signature: "MIN(a, b, …)", summary: "The smallest argument."),
        Function(name: "MAX", category: "math", signature: "MAX(a, b, …)", summary: "The largest argument."),
        Function(name: "UPPER", category: "text", signature: "UPPER(text)", summary: "Text in capitals."),
        Function(name: "LOWER", category: "text", signature: "LOWER(text)", summary: "Text in lower case."),
        Function(name: "LEN", category: "text", signature: "LEN(text)", summary: "How many characters text has."),
        Function(name: "CONCAT", category: "text", signature: "CONCAT(a, b, …)", summary: "Joins text."),
        Function(name: "LEFT", category: "text", signature: "LEFT(text, count)", summary: "The first characters of text."),
        Function(name: "TRIM", category: "text", signature: "TRIM(text)", summary: "Text without surrounding spaces."),
        Function(name: "TEXT", category: "convert", signature: "TEXT(value)", summary: "A value as text."),
        Function(name: "NUMBER", category: "convert", signature: "NUMBER(text)", summary: "Text as a number."),
        Function(name: "COLOR", category: "color", signature: "COLOR(name)", summary: "A colour tile by name."),
    ])
}
