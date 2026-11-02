import SwiftUI
import FiestaBoardKit
import FiestaBoardDocuments

/// Words the catalog pickers, formula editor and draw mode add (iOS-F1). The shared names
/// ("Variables", "Colors", "Insert formula", "Draw on board"…) stay in `EditorStrings`.
enum CatalogStrings {
    static let searchVariables = "Search variables"
    static let noVariables = "No template variables available. Configure plugins in Settings."
    static func noMatches(_ query: String) -> String { "No variables match “\(query)”." }
    static let sampleNote = "Showing common variables: this server's list couldn't be loaded."
    static func arrayHint(_ name: String) -> String { "Configure \(name) in Settings to see indexed variables here." }
    static let general = "General"
    static let degree = "° Degree"
    static let heart = "♥ Heart"
    static let fillPattern = "Fill the rest of the row with"
    static let customCharacter = "Character"
    static let functions = "Functions"
    static let editFormula = "Edit formula"
    static let done = "Done"
    static let formulaValid = "Formula is valid"
    static let formulaChecking = "Checking…"
    static let formulaHint = "Pick a function or a variable, or type an expression."
    static let drawHint = "Drawing mode is on — drag on the preview to paint tiles"
    static let eraser = "Eraser"
    static let stamp = "Stamp a character"
    static let doneDrawing = "Done drawing"
}

/// The editor's catalogs for one deployment (PLAN B21/B22/B32): the server's variables (with
/// manifests) and functions, read once per deployment and shared by every editor; validation of
/// one formula. The demo (and a server whose lists can't be read) falls back to the built-in
/// sample, which is authoritative only in the demo, whose variables it is.
@MainActor final class EditorCatalogStore: ObservableObject {
    @Published private(set) var catalog: TemplateCatalog = .sample(authoritative: false)
    @Published private(set) var functions: FunctionCatalog = .builtIn
    /// The server's list arrived (or the demo's sample is in place).
    @Published private(set) var isLoaded = false
    /// The server's variables couldn't be read; the pickers show the built-in sample.
    @Published private(set) var usesSample = false
    private var reader: (any TemplateCatalogReading)?
    private var simulated = false

    private static var cache: [String: (TemplateCatalog, FunctionCatalog)] = [:]

    var variables: VariableCatalog { catalog.variableCatalog }
    /// B32: Variables is disabled only when the server says there are none.
    var variablesAvailable: Bool { !isLoaded || usesSample || catalog.hasVariables }
    var colorsAvailable: Bool { !catalog.colors.isEmpty }
    var formattingAvailable: Bool { !catalog.formatting.isEmpty }

    func load(deploymentID: String, isSimulated: Bool) async {
        simulated = isSimulated
        if isSimulated {
            catalog = .sample(authoritative: true); functions = .builtIn; isLoaded = true; usesSample = false
            return
        }
        reader = StatusReaderRegistry.shared.reader(for: deploymentID) as? any TemplateCatalogReading
        if let cached = Self.cache[deploymentID] {
            catalog = cached.0; functions = cached.1; isLoaded = true; usesSample = !cached.0.isServerCatalog
            return
        }
        guard let reader else { usesSample = true; isLoaded = true; return }
        async let variables = try? reader.templateCatalog()
        async let functionList = try? reader.formulaFunctions()
        let (loadedCatalog, loadedFunctions) = await (variables, functionList)
        if let loadedCatalog { catalog = loadedCatalog } else { usesSample = true }
        if let loadedFunctions { functions = loadedFunctions }
        isLoaded = true
        if loadedCatalog != nil { Self.cache[deploymentID] = (catalog, functions) }
    }

    /// One formula's verdict: the server's `POST /templates/validate`, or (demo, no server) the
    /// fixture's rule over the known functions.
    func check(_ expression: String) async throws -> FormulaCheck {
        if !simulated, let reader { return try await reader.validateFormula(expression) }
        return FormulaValidator.localCheck(expression, functions: functions.names)
    }

    /// SF Symbol for a plugin: its manifest's Lucide icon when known, else a guess from its id.
    static func symbol(for plugin: TemplateCatalog.Plugin) -> String {
        let lucide: [String: String] = [
            "cloud-sun": "cloud.sun.fill", "cloud": "cloud.fill", "sun": "sun.max.fill", "cloud-rain": "cloud.rain.fill",
            "thermometer": "thermometer.medium", "clock": "clock.fill", "calendar": "calendar", "calendar-clock": "calendar.badge.clock",
            "bike": "bicycle", "bicycle": "bicycle", "trending-up": "chart.line.uptrend.xyaxis", "chart-line": "chart.xyaxis.line",
            "dollar-sign": "dollarsign.circle.fill", "house": "house.fill", "home": "house.fill", "train": "tram.fill",
            "train-front": "tram.fill", "bus": "bus.fill", "plane": "airplane", "music": "music.note", "newspaper": "newspaper.fill",
            "trophy": "trophy.fill", "moon": "moon.fill", "star": "star.fill", "quote": "quote.opening", "mail": "envelope.fill",
            "wifi": "wifi", "zap": "bolt.fill", "leaf": "leaf.fill", "car": "car.fill", "globe": "globe",
        ]
        if let icon = plugin.icon, let symbol = lucide[icon.lowercased()] { return symbol }
        let id = plugin.id.lowercased()
        if id.contains("weather") { return "cloud.sun.fill" }
        if id.contains("date") || id.contains("time") || id.contains("clock") { return "clock.fill" }
        if id.contains("stock") || id.contains("crypto") { return "chart.line.uptrend.xyaxis" }
        if id.contains("wheel") || id.contains("bike") { return "bicycle" }
        if id.contains("home") || id.contains("house") { return "house.fill" }
        if id.contains("transit") || id.contains("train") || id.contains("muni") { return "tram.fill" }
        if id.contains("sport") || id.contains("score") { return "trophy.fill" }
        return "puzzlepiece.extension.fill"
    }
}

/// The three insert pickers, presented as sheets from the toolbar and the keyboard accessory.
enum InsertPickerKind: String, Identifiable {
    case variables, colors, formatting
    var id: String { rawValue }
}
