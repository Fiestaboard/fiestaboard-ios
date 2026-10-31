import Foundation

public enum FlexibleEditError: Error, LocalizedError {
    case unsupported, invalidOperation, invalidDocument
    public var errorDescription: String? {
        switch self {
        case .unsupported: "This flexible document uses an unsupported protocol or content structure."
        case .invalidOperation: "Choose an available block, shape, or supported field."
        case .invalidDocument: "Repair the highlighted document fields before saving or previewing."
        }
    }
}
public enum FlexibleLocation: Equatable, Sendable {
    case pageStyle, layout, targets, block(String), blockStyle(String), canvas(String), content(String), shape(String, Int)
}
public struct FlexibleBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let value: LosslessJSONObject
    public var isKnown: Bool { ["text", "canvas", "spacer"].contains(kind) }
}
public struct FlexibleIssue: Identifiable, Equatable, Sendable {
    public var id: String { "\(blockID ?? "page")/\(shapeIndex.map(String.init) ?? "")/\(key)/\(message)" }
    public let blockID: String?
    public let shapeIndex: Int?
    public let key: String
    public let message: String
    public let location: FlexibleLocation
}
public enum FlexibleNumber {
    /// Parsing the whole lexeme rejects partial input, whitespace and leading zeroes.
    /// An invalid intermediate stays a valid JSON string in the local recovery document.
    public static func draft(_ source: String) -> LosslessJSON {
        guard source.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
              case .number = try? LosslessJSON.parse(Data(source.utf8)) else { return .string(source) }
        return .number(source)
    }
    public static func display(_ value: LosslessJSON?) -> String {
        switch value {
        case .string(let text), .number(let text): text
        case nil, .null: ""
        default: String(decoding: (try? value?.serializedData()) ?? Data(), as: UTF8.self)
        }
    }
}

extension PageDocument {
    public var supportsFlexibleEditing: Bool { pageType == "flexible" && root["document_protocol"] == .string("page-document-v2") }
    public var flexibleBlocks: [FlexibleBlock] {
        guard case .array(let values) = root["blocks"] else { return [] }
        return values.enumerated().map { index, value in
            guard case .object(let object) = value else { return FlexibleBlock(id: "invalid-\(index)", kind: "invalid", value: [:]) }
            return FlexibleBlock(id: FlexibleNumber.display(object["id"]), kind: FlexibleNumber.display(object["kind"]), value: object)
        }
    }
    private func blockIndex(_ id: String) throws -> Int {
        guard supportsFlexibleEditing, case .array(let values) = root["blocks"],
              let index = values.firstIndex(where: { if case .object(let o) = $0 { o["id"] == .string(id) } else { false } }) else { throw FlexibleEditError.unsupported }
        return index
    }
    private func path(_ location: FlexibleLocation) throws -> [PathComponent] {
        switch location {
        case .pageStyle: return [.key("style")]
        case .layout: return [.key("layout")]
        case .targets: return [.key("targets")]
        case .block(let id): return [.key("blocks"), .index(try blockIndex(id))]
        case .blockStyle(let id): return try path(.block(id)) + [.key("style")]
        case .canvas(let id): return try path(.block(id)) + [.key("canvas")]
        case .content(let id): return try path(.canvas(id)) + [.key("content")]
        case .shape(let id, let index): return try path(.content(id)) + [.key("shapes"), .index(index)]
        }
    }
    private enum PathComponent { case key(String), index(Int) }
    private func value(at path: [PathComponent]) -> LosslessJSON? {
        var value: LosslessJSON? = .object(root)
        for component in path {
            switch (component, value) {
            case (.key(let key), .object(let object)): value = object[key]
            case (.index(let index), .array(let values)) where values.indices.contains(index): value = values[index]
            default: return nil
            }
        }
        return value
    }
    private mutating func put(_ value: LosslessJSON?, at path: [PathComponent]) throws {
        func replace(_ node: LosslessJSON?, _ depth: Int) throws -> LosslessJSON? {
            if depth == path.count { return value }
            switch path[depth] {
            case .key(let key):
                var object: LosslessJSONObject
                if case .object(let current) = node { object = current }
                else if node == nil || node == .null { object = [:] }
                else { throw FlexibleEditError.invalidOperation }
                object[key] = try replace(object[key], depth + 1)
                return .object(object)
            case .index(let index):
                guard case .array(var values) = node, values.indices.contains(index), let next = try replace(values[index], depth + 1) else { throw FlexibleEditError.invalidOperation }
                values[index] = next
                return .array(values)
            }
        }
        guard case .object(let object) = try replace(.object(root), 0) else { throw FlexibleEditError.invalidOperation }
        root = object
    }
    public func flexibleContainerValue(_ location: FlexibleLocation) -> LosslessJSON? {
        guard let path = try? path(location) else { return nil }
        return value(at: path)
    }
    /// Explicit repair/inheritance only. The original value remains in document undo history.
    public mutating func resetFlexibleContainer(_ location: FlexibleLocation, inherit: Bool) throws {
        guard supportsFlexibleEditing else { throw FlexibleEditError.unsupported }
        let replacement: LosslessJSON
        switch location {
        case .pageStyle, .blockStyle, .layout, .targets:
            replacement = inherit ? .null : .object([:])
        case .canvas:
            guard !inherit else { throw FlexibleEditError.invalidOperation }
            replacement = .object(["content": .object(["shapes": .array([])])])
        case .content:
            guard !inherit else { throw FlexibleEditError.invalidOperation }
            replacement = .object(["shapes": .array([])])
        default: throw FlexibleEditError.invalidOperation
        }
        try put(replacement, at: path(location))
    }
    public func flexibleValue(_ location: FlexibleLocation, key: String) -> LosslessJSON? {
        guard let path = try? path(location) else { return nil }
        return value(at: path + [.key(key)])
    }
    public func flexibleShapes(blockID: String) -> [LosslessJSON] {
        if case .array(let shapes) = flexibleValue(.content(blockID), key: "shapes") { shapes } else { [] }
    }
    public mutating func setFlexibleValue(_ location: FlexibleLocation, key: String, value: LosslessJSON?) throws {
        guard supportsFlexibleEditing else { throw FlexibleEditError.unsupported }
        let allowed: [String]
        switch location {
        case .pageStyle, .blockStyle: allowed = ["font", "size", "color", "background", "align", "case", "overflow", "height"]
        case .layout: allowed = ["kind", "valign", "gap"]
        case .targets: allowed = ["technology", "boards"]
        case .block(let id):
            guard flexibleBlocks.first(where: { $0.id == id })?.isKnown == true else { throw FlexibleEditError.unsupported }
            allowed = ["text", "priority", "if"]
        case .canvas: allowed = ["source"]
        case .content: allowed = ["size", "background"]
        case .shape(let id, let index):
            let shapes = flexibleShapes(blockID: id)
            guard shapes.indices.contains(index), case .object(let shape) = shapes[index] else { throw FlexibleEditError.invalidOperation }
            switch shape["type"] {
            case .string("text"): allowed = ["x", "y", "text", "color", "font"]
            case .string("rect"): allowed = ["x", "y", "w", "h", "fill", "stroke"]
            case .string("line"): allowed = ["x1", "y1", "x2", "y2", "stroke", "width"]
            default: throw FlexibleEditError.unsupported
            }
        }
        guard allowed.contains(key) else { throw FlexibleEditError.invalidOperation }
        try put(value, at: path(location) + [.key(key)])
    }
    public mutating func insertFlexibleBlock(kind: String, id: String, at index: Int) throws {
        guard supportsFlexibleEditing, ["text", "canvas", "spacer"].contains(kind), Self.validID(id) else { throw FlexibleEditError.invalidOperation }
        var blocks: [LosslessJSON]
        if case .array(let current) = root["blocks"] { blocks = current }
        else if root["blocks"] == nil || root["blocks"] == .null { blocks = [] }
        else { throw FlexibleEditError.invalidOperation }
        guard blocks.count < 32, (0...blocks.count).contains(index), !flexibleBlocks.contains(where: { $0.id == id }) else { throw FlexibleEditError.invalidOperation }
        var block: LosslessJSONObject = ["id": .string(id), "kind": .string(kind)]
        if kind == "text" { block["text"] = .string("") }
        if kind == "canvas" { block["canvas"] = .object(["content": .object(["size": .array([.number("32"), .number("16")]), "shapes": .array([])])]) }
        blocks.insert(.object(block), at: index); root["blocks"] = .array(blocks)
    }
    public mutating func removeFlexibleBlock(id: String) throws {
        let index = try blockIndex(id)
        guard case .array(var blocks) = root["blocks"] else { throw FlexibleEditError.invalidOperation }
        blocks.remove(at: index); root["blocks"] = .array(blocks)
    }
    public mutating func moveFlexibleBlock(id: String, to destination: Int) throws {
        let index = try blockIndex(id)
        guard case .array(var blocks) = root["blocks"], blocks.indices.contains(destination) else { throw FlexibleEditError.invalidOperation }
        blocks.insert(blocks.remove(at: index), at: destination); root["blocks"] = .array(blocks)
    }
    public mutating func insertFlexibleText(blockID: String, source: String, selection: NSRange) throws {
        guard case .string(let text) = flexibleValue(.block(blockID), key: "text"), let range = Range(selection, in: text) else { throw FlexibleEditError.invalidOperation }
        try setFlexibleValue(.block(blockID), key: "text", value: .string(text.replacingCharacters(in: range, with: source)))
    }
    public mutating func insertFlexibleShape(blockID: String, kind: String) throws {
        guard supportsFlexibleEditing, flexibleBlocks.first(where: { $0.id == blockID })?.kind == "canvas" else { throw FlexibleEditError.unsupported }
        var shapes = flexibleShapes(blockID: blockID)
        guard shapes.count < 256 else { throw FlexibleEditError.invalidOperation }
        var shape: LosslessJSONObject = ["type": .string(kind)]
        switch kind {
        case "text": shape["x"] = .number("0"); shape["y"] = .number("0"); shape["text"] = .string("Text"); shape["color"] = .string("white"); shape["font"] = .string("5x7")
        case "rect": shape["x"] = .number("0"); shape["y"] = .number("0"); shape["w"] = .number("8"); shape["h"] = .number("8"); shape["fill"] = .string("white")
        case "line": shape["x1"] = .number("0"); shape["y1"] = .number("0"); shape["x2"] = .number("8"); shape["y2"] = .number("8"); shape["stroke"] = .string("white"); shape["width"] = .number("1")
        default: throw FlexibleEditError.invalidOperation
        }
        shapes.append(.object(shape))
        try put(.array(shapes), at: path(.content(blockID)) + [.key("shapes")])
    }
    public mutating func removeFlexibleShape(blockID: String, at index: Int) throws {
        guard supportsFlexibleEditing else { throw FlexibleEditError.unsupported }
        var shapes = flexibleShapes(blockID: blockID)
        guard shapes.indices.contains(index) else { throw FlexibleEditError.invalidOperation }
        shapes.remove(at: index); try put(.array(shapes), at: path(.content(blockID)) + [.key("shapes")])
    }
    public mutating func moveFlexibleShape(blockID: String, from source: Int, to destination: Int) throws {
        guard supportsFlexibleEditing else { throw FlexibleEditError.unsupported }
        var shapes = flexibleShapes(blockID: blockID)
        guard shapes.indices.contains(source), shapes.indices.contains(destination) else { throw FlexibleEditError.invalidOperation }
        shapes.insert(shapes.remove(at: source), at: destination)
        try put(.array(shapes), at: path(.content(blockID)) + [.key("shapes")])
    }
    public mutating func setFlexibleContentSize(blockID: String, axis: Int, text: String) throws {
        guard (0...1).contains(axis) else { throw FlexibleEditError.invalidOperation }
        var size: [LosslessJSON] = [.number("32"), .number("16")]
        if case .array(let current) = flexibleValue(.content(blockID), key: "size"), current.count == 2 { size = current }
        size[axis] = FlexibleNumber.draft(text)
        try setFlexibleValue(.content(blockID), key: "size", value: .array(size))
    }
    private static func validID(_ id: String) -> Bool { id.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil }

    /// Validate every retained known field, including hidden/unsupported inspectors.
    /// Opaque extension values are never interpreted or converted.
    public var flexibleIssues: [FlexibleIssue] {
        var issues: [FlexibleIssue] = []
        func issue(_ location: FlexibleLocation, _ key: String, _ message: String) {
            let block: String?; let shape: Int?
            switch location {
            case .block(let id), .blockStyle(let id), .canvas(let id), .content(let id): block = id; shape = nil
            case .shape(let id, let index): block = id; shape = index
            default: block = nil; shape = nil
            }
            issues.append(FlexibleIssue(blockID: block, shapeIndex: shape, key: key, message: message, location: location))
        }
        func number(_ value: LosslessJSON?, _ range: ClosedRange<Double>, integer: Bool = false, expression: Bool = false) -> Bool {
            if expression, case .string(let text) = value, Self.expression(text) { return true }
            guard case .number(let lexeme) = value, let value = Double(lexeme), value.isFinite, range.contains(value) else { return false }
            return !integer || (!lexeme.contains(".") && !lexeme.lowercased().contains("e"))
        }
        func optionalString(_ object: LosslessJSONObject, _ key: String, _ location: FlexibleLocation) {
            if let value = object[key], value != .null, case .string = value {} else if object[key] != nil && object[key] != .null { issue(location, key, "\(key) must be text.") }
        }
        func enumField(_ object: LosslessJSONObject, _ key: String, _ allowed: [String], _ location: FlexibleLocation) {
            guard let value = object[key], value != .null else { return }
            if case .string(let text) = value, allowed.contains(text) { return }
            issue(location, key, "Choose \(allowed.joined(separator: ", ")) for \(key).")
        }
        func style(_ value: LosslessJSON?, _ location: FlexibleLocation) {
            guard let value, value != .null else { return }
            guard case .object(let object) = value else { issue(location, "style", "Style must be an object or inherited."); return }
            for key in ["font", "color", "background"] { optionalString(object, key, location) }
            enumField(object, "align", ["left", "center", "right"], location)
            enumField(object, "case", ["as-is", "upper", "lower"], location)
            enumField(object, "overflow", ["wrap", "shrink", "ellipsis", "scroll"], location)
            if let size = object["size"], size != .null {
                if case .string(let text) = size, ["small", "medium", "large", "xlarge", "fit"].contains(text) {} else if !number(size, 1...256, integer: true) { issue(location, "size", "Size needs a named size or whole pixels from 1 to 256.") }
            }
            if let height = object["height"], height != .null {
                if case .string(let text) = height, ["auto", "fill"].contains(text) {} else if !number(height, -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude) { issue(location, "height", "Height needs auto, fill, or a finite number.") }
            }
            for key in ["color", "background"] where object[key] != nil && object[key] != .null {
                if case .string(let text) = object[key], Self.styleColor(text, transparent: key == "background") {} else { issue(location, key, "Use a board color, #rrggbb, tile 63–71, or expression.") }
            }
        }
        guard supportsFlexibleEditing else { issue(.layout, "protocol", "This document protocol is read-only."); return issues }
        if let name = name, (1...100).contains(name.unicodeScalars.count) {} else { issue(.layout, "name", "Page name needs 1 to 100 characters.") }
        for key in Self.flexibleGridFields where root[key] != nil { issue(.layout, key, "Flexible pages cannot contain \(key).") }
        guard case .array(let blocks) = root["blocks"], !blocks.isEmpty, blocks.count <= 32 else { issue(.layout, "blocks", "Add between 1 and 32 blocks."); return issues }
        style(root["style"], .pageStyle)
        if let layout = root["layout"], layout != .null {
            if case .object(let object) = layout {
                if let kind = object["kind"], case .string = kind {} else if object["kind"] != nil { issue(.layout, "kind", "Layout kind must be text.") }
                enumField(object, "valign", ["top", "middle", "bottom", "spread"], .layout)
                if object["valign"] == .null { issue(.layout, "valign", "Vertical alignment cannot be null.") }
                if let gap = object["gap"] {
                    if case .string(let text) = gap, ["none", "small", "medium", "large"].contains(text) {} else if !number(gap, -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude, integer: true) { issue(.layout, "gap", "Gap needs a named spacing or whole number.") }
                }
            } else { issue(.layout, "layout", "Layout must be an object or inherited.") }
        }
        if let targets = root["targets"], targets != .null {
            if case .object(let object) = targets {
                for key in ["boards", "technology"] where object[key] != nil && object[key] != .null {
                    if case .array(let list) = object[key], list.allSatisfy({ if case .string = $0 { true } else { false } }) {} else { issue(.targets, key, "Target restrictions must be lists of text.") }
                }
            } else { issue(.targets, "targets", "Targets must be an object or unrestricted.") }
        }
        var ids: Set<String> = []
        for (index, block) in blocks.enumerated() {
            guard case .object(let object) = block else { issue(.layout, "blocks", "Block \(index + 1) needs an object."); continue }
            let id = FlexibleNumber.display(object["id"]); let loc = FlexibleLocation.block(id)
            if case .string = object["id"], Self.validID(id), ids.insert(id).inserted {} else { issue(loc, "id", "Block IDs must be unique text using letters, digits, _ or -, up to 32 characters.") }
            guard case .string(let kind) = object["kind"] else { issue(loc, "kind", "Block kind must be text."); continue }
            style(object["style"], .blockStyle(id)); optionalString(object, "if", loc)
            optionalString(object, "text", loc)
            if let priority = object["priority"], priority != .null, !number(priority, 0...1000, integer: true) { issue(loc, "priority", "Priority needs a whole number from 0 to 1000.") }
            if kind == "text", case .string = object["text"] {} else if kind == "text" { issue(loc, "text", "Text block needs text.") }
            guard let canvas = object["canvas"], canvas != .null else { if kind == "canvas" { issue(.canvas(id), "canvas", "Canvas needs drawing content or a source expression.") }; continue }
            guard case .object(let body) = canvas else { issue(.canvas(id), "canvas", "Canvas must be an object."); continue }
            optionalString(body, "source", .canvas(id))
            if kind == "canvas", (body["source"] == nil || body["source"] == .null), (body["content"] == nil || body["content"] == .null) { issue(.canvas(id), "source", "Add drawing content or a source expression.") }
            guard let content = body["content"], content != .null else { continue }
            guard case .object(let drawing) = content else { issue(.content(id), "content", "Drawing content must be an object."); continue }
            if let size = drawing["size"], size != .null {
                if case .array(let values) = size, values.count == 2, values.allSatisfy({ number($0, 1...128, integer: true) }) {} else { issue(.content(id), "size", "Canvas width and height need whole numbers from 1 to 128.") }
            }
            var palette: LosslessJSONObject = [:]
            if let value = drawing["palette"] {
                if case .object(let entries) = value {
                    palette = entries
                    if entries.count > 62 { issue(.content(id), "palette", "Palette supports up to 62 keys.") }
                    for (key, value) in entries {
                        if key.range(of: #"^[A-Za-z0-9]$"#, options: .regularExpression) == nil || (value == .null || !Self.canvasColor(value, palette: [:], expressions: false)) { issue(.content(id), "palette", "Palette needs single letter/digit keys and literal colors.") }
                    }
                } else { issue(.content(id), "palette", "Palette must be an object.") }
            }
            if let background = drawing["background"], !Self.canvasColor(background, palette: palette) { issue(.content(id), "background", "Drawing background needs a valid color.") }
            if let pixels = drawing["pixels"] {
                if case .array(let rows) = pixels, rows.count <= 128, rows.allSatisfy({ if case .string(let row) = $0 { row.unicodeScalars.count <= 128 && row.allSatisfy { $0 == "." || palette[String($0)] != nil } } else { false } }) {} else { issue(.content(id), "pixels", "Retained pixel rows need valid palette keys and dimensions up to 128.") }
            }
            guard let shapes = drawing["shapes"] else { continue }
            guard case .array(let list) = shapes, list.count <= 256 else { issue(.content(id), "shapes", "Canvas supports at most 256 shapes."); continue }
            for (shapeIndex, shape) in list.enumerated() {
                let location = FlexibleLocation.shape(id, shapeIndex)
                guard case .object(let shape) = shape, case .string(let type) = shape["type"] else { issue(location, "type", "Shape needs a supported type."); continue }
                let fields: [String]
                switch type {
                case "text": fields = ["x", "y"]
                case "rect": fields = ["x", "y", "w", "h"]
                case "line": fields = ["x1", "y1", "x2", "y2"]
                case "circle": fields = ["cx", "cy", "r"]
                case "ellipse": fields = ["cx", "cy", "rx", "ry"]
                case "gradient": fields = []
                case "polygon": fields = []
                default: issue(location, "type", "Unknown shape ‘\(type)’ is preserved locally. Server replacement is unavailable."); continue
                }
                for key in fields where !number(shape[key], -1024...1024, expression: true) { issue(location, key, "\(key) needs a number from -1024 to 1024 or {{expression}}.") }
                if type == "line", let width = shape["width"], !number(width, 1...16, expression: true) { issue(location, "width", "Line width needs 1 to 16 or an expression.") }
                if type == "gradient" {
                    for key in ["x", "y", "w", "h", "angle"] where shape[key] != nil && (key == "angle" || shape[key] != .null) && !number(shape[key], -1024...1024, expression: true) { issue(location, key, "\(key) needs a bounded number or expression.") }
                }
                if type == "polygon" {
                    if case .string(let text) = shape["points"], Self.expression(text) {} else if case .array(let points) = shape["points"], (3...256).contains(points.count), points.allSatisfy({ if case .array(let pair) = $0 { pair.count == 2 && pair.allSatisfy { number($0, -1024...1024, expression: true) } } else { false } }) {} else { issue(location, "points", "Polygon points need 3 to 256 coordinate pairs or an expression.") }
                }
                if type == "text" {
                    if case .string(let text) = shape["text"], text.unicodeScalars.count <= 256 {} else { issue(location, "text", "Shape text supports up to 256 characters.") }
                    enumField(shape, "font", ["3x5", "5x7"], location)
                    if shape["font"] == .null { issue(location, "font", "Text font cannot be null.") }
                }
                let colorKeys: [String]
                switch type { case "text": colorKeys = ["color"]; case "line": colorKeys = ["stroke"]; case "gradient": colorKeys = ["from", "to"]; default: colorKeys = ["fill", "stroke"] }
                for key in colorKeys {
                    if let color = shape[key] {
                        if (["text", "line", "gradient"].contains(type) && color == .null) || !Self.canvasColor(color, palette: palette) { issue(location, key, "\(key) needs a color, palette key or expression.") }
                    }
                    else if ["text", "line", "gradient"].contains(type) { issue(location, key, "\(key) is required.") }
                }
                if let condition = shape["if"], condition != .null {
                    if case .bool = condition {} else if case .string(let text) = condition, Self.expression(text) {} else { issue(location, "if", "Shape condition needs true, false or an expression.") }
                }
                if let each = shape["foreach"], each != .null {
                    if case .string(let text) = each, Self.expression(text) {} else { issue(location, "foreach", "Shape repetition needs an expression.") }
                }
                if let alias = shape["as"], alias != .null {
                    if case .string(let text) = alias, text.range(of: #"^[A-Za-z_][A-Za-z0-9_]{0,31}$"#, options: .regularExpression) != nil, shape["foreach"] != nil && shape["foreach"] != .null {} else { issue(location, "as", "Repetition alias needs a valid name and foreach expression.") }
                }
            }
        }
        return issues
    }
    private static func expression(_ text: String) -> Bool { text.contains("{{") && text.contains("}}") }
    private static let colors = ["red", "orange", "yellow", "green", "blue", "violet", "white", "black"]
    private static func styleColor(_ text: String, transparent: Bool) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return colors.contains(text.lowercased()) || (transparent && text.lowercased() == "transparent") || text.range(of: #"^(#[0-9a-fA-F]{6}|\{?(6[3-9]|7[01])\}?|\{\{(?:(?!\{\{|\}\}).)*\}\})$"#, options: [.regularExpression]) != nil
    }
    private static func canvasColor(_ value: LosslessJSON, palette: LosslessJSONObject, expressions: Bool = true) -> Bool {
        if value == .null { return true }
        guard case .string(let text) = value else { return false }
        if expressions && expression(text) { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return colors.contains(trimmed.lowercased()) || ["none", "transparent", "."].contains(trimmed.lowercased()) || palette[trimmed] != nil || trimmed.range(of: #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"#, options: .regularExpression) != nil
    }
    public static let flexibleGridFields = ["device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols", "display_type", "rows", "template", "line_metadata", "canvases"]
    public func flexibleEvaluationData(boardID: String) throws -> Data {
        guard supportsFlexibleEditing, flexibleIssues.isEmpty, !boardID.isEmpty else { throw FlexibleEditError.invalidDocument }
        let excluded = Set(Self.flexibleGridFields + ["id", "created_at", "updated_at", "revision", "expected_revision", "edit_protocol", "document_protocol", "demo_plugin_id"])
        return try LosslessJSON.object(["page": .object(root.filter { !excluded.contains($0.key) }), "board_id": .string(boardID)]).serializedData()
    }
}
