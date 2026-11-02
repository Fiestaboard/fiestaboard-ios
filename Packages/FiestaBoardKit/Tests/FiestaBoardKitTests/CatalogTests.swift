import XCTest
@testable import FiestaBoardKit
import FiestaBoardDocuments

/// `GET /v1/variables` as 10.3.2 shapes it (`src/v1/models.py` `VariableCatalog`), with the mock
/// fixture's plugins (PLAN §4.4): weather (grouped), date_time, stocks, baywheels (array).
private let variablesJSON = #"""
{
  "variables": {
    "weather": ["temperature", "condition", "feels_like", "humidity"],
    "date_time": ["time", "date", "day_of_week"],
    "stocks": ["AAPL.price"],
    "baywheels": ["station_count", "stations.*.name", "stations.*.bikes", "stations.0.name", "stations.0.bikes", "stations.1.name", "stations.1.bikes"],
    "trains": ["departures.*.line"]
  },
  "max_lengths": {"weather.temperature": 3},
  "variable_metadata": {
    "weather": {
      "temperature": {"description": "Current temperature", "preview": "72", "group": "now"},
      "condition": {"preview": "SUNNY", "group": "now"},
      "feels_like": {"preview": 70, "group": "now"},
      "humidity": {"preview": "40"}
    },
    "date_time": {"time": {"preview": "08:15"}, "day_of_week": {"preview": "SUNDAY WITH A LONG NAME"}},
    "baywheels": {"stations.0.name": {"preview": "MARKET ST"}, "stations.1.name": {"preview": "FERRY BLDG"}, "stations.0.bikes": {"preview": "7"}}
  },
  "variable_groups": {"weather": {"now": {"label": "Right now"}}},
  "colors": {"red": 63, "orange": 64, "yellow": 65, "green": 66, "blue": 67, "violet": 68, "white": 69, "black": 70},
  "symbols": ["sun"],
  "filters": ["pad:N"],
  "formatting": {
    "fill_space_repeat": {"syntax": "{{fill_space_repeat:pattern}}", "description": "Fills remaining space"},
    "fill_space": {"syntax": "{{fill_space}}", "description": "Expands to fill remaining space"}
  },
  "syntax_examples": {},
  "plugin_system_enabled": true
}
"""#

final class VariableCatalogTests: XCTestCase {
    private func catalog(manifests: [String: TemplateCatalog.Manifest] = [:]) throws -> TemplateCatalog {
        try TemplateCatalog(variablesData: Data(variablesJSON.utf8), manifests: manifests)
    }

    func testPluginsHaveReadableNamesIconsAndGroups() throws {
        let manifest = try TemplateCatalog.Manifest(data: Data(#"{"name":"Bay Wheels","icon":"bike","variables":{"arrays":{"stations":{"label_field":"name","item_fields":["name","bikes","docks"]}}}}"#.utf8))
        let catalog = try catalog(manifests: ["baywheels": manifest])
        XCTAssertEqual(catalog.plugins.map(\.name), ["Bay Wheels", "Date Time", "Stocks", "Trains", "Weather"],
                       "Manifest name, else the id in Title Case; sorted by name")
        XCTAssertEqual(catalog.plugins.first?.icon, "bike")
        let weather = try XCTUnwrap(catalog.plugins.first { $0.id == "weather" })
        XCTAssertEqual(weather.groups.map(\.label), ["Right now", "General"], "Declared groups first, ungrouped last as General")
        XCTAssertEqual(weather.groups[0].fields.map(\.name), ["temperature", "condition", "feels_like"])
        XCTAssertEqual(weather.groups[0].fields[2].preview, "70", "Numeric previews read as text")
        XCTAssertEqual(weather.groups[0].fields[0].summary, "Current temperature")
        let dateTime = try XCTUnwrap(catalog.plugins.first { $0.id == "date_time" })
        XCTAssertEqual(dateTime.groups.map(\.label), [""], "No declared groups: one unlabeled group")
        XCTAssertEqual(dateTime.groups[0].fields.last?.shortPreview, "SUNDAY WITH …", "12-character faded preview")
        XCTAssertEqual(TemplateCatalog.titleCase("home-assistant"), "Home Assistant")
    }

    func testArraysBecomeIndexedItemsWithAnEmptyArrayHint() throws {
        let catalog = try catalog()
        let bay = try XCTUnwrap(catalog.plugins.first { $0.id == "baywheels" })
        XCTAssertEqual(bay.groups.flatMap(\.fields).map(\.name), ["station_count"], "Array paths are not simple fields")
        let stations = try XCTUnwrap(bay.arrays.first)
        XCTAssertEqual(stations.name, "stations")
        XCTAssertEqual(stations.items.map(\.index), [0, 1])
        XCTAssertEqual(stations.items.map(\.label), ["MARKET ST", "FERRY BLDG"])
        XCTAssertEqual(stations.items[0].fields.map(\.path), ["baywheels.stations.0.name", "baywheels.stations.0.bikes"])
        XCTAssertEqual(stations.itemFields, ["name", "bikes"])
        let trains = try XCTUnwrap(catalog.plugins.first { $0.id == "trains" })
        XCTAssertEqual(trains.arrays.first?.items, [], "Declared by pattern but not configured: the picker shows the hint")
        XCTAssertTrue(catalog.hasVariables)
    }

    func testColorsAndFormattingFollowTheServer() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.colors, TemplateCatalog.colorOrder)
        XCTAssertEqual(catalog.formatting.map(\.key), ["fill_space", "fill_space_repeat"])
        XCTAssertEqual(catalog.formatting.map(\.title), ["Fill space", "Fill space repeat"])
        XCTAssertTrue(catalog.formatting[1].takesPattern)
        // B32: no plugins → no variables; colours and formatting only when listed.
        let empty = try TemplateCatalog(variablesData: Data(#"{"variables":{},"colors":{},"formatting":{},"plugin_system_enabled":true}"#.utf8))
        XCTAssertFalse(empty.hasVariables)
        XCTAssertEqual(empty.colors, [])
        XCTAssertEqual(empty.formatting, [])
        XCTAssertThrowsError(try TemplateCatalog(variablesData: Data(#"{"detail":"Not Found"}"#.utf8)))
    }

    func testSearchSplitsWordsOnDotsUnderscoresAndDashes() throws {
        let catalog = try catalog()
        func paths(_ query: String) -> [String] {
            catalog.filtered(query).flatMap { $0.groups.flatMap(\.fields).map(\.path) + $0.arrays.flatMap { $0.items.flatMap(\.fields).map(\.path) } }
        }
        XCTAssertEqual(paths("temp"), ["weather.temperature"])
        XCTAssertEqual(paths("feels"), ["weather.feels_like"])
        XCTAssertEqual(paths("like"), ["weather.feels_like"], "Words split on _")
        XCTAssertEqual(paths("feels like"), ["weather.feels_like"], "Several words, in any separator")
        XCTAssertEqual(paths("weather.cond"), ["weather.condition"], "Dotted path")
        XCTAssertEqual(paths("day"), ["date_time.day_of_week"])
        XCTAssertEqual(paths("price"), ["stocks.AAPL.price"], "Words split on .")
        XCTAssertEqual(paths("bikes"), ["baywheels.stations.0.bikes", "baywheels.stations.1.bikes"])
        XCTAssertEqual(paths("ferry"), ["baywheels.stations.1.name", "baywheels.stations.1.bikes"], "An item's label finds its fields")
        XCTAssertEqual(Set(paths("weather")), ["weather.temperature", "weather.condition", "weather.feels_like", "weather.humidity"],
                       "A plugin's name keeps all of its fields")
        XCTAssertEqual(paths("date time").first, "date_time.time")
        XCTAssertEqual(paths("zzz"), [])
        XCTAssertEqual(catalog.filtered("  ").count, catalog.plugins.count)
    }

    func testChipCatalogIsAuthoritativeOnlyForTheServersList() throws {
        let chips = try catalog().variableCatalog
        XCTAssertTrue(chips.isAuthoritative)
        XCTAssertEqual(chips.status(of: "weather.temperature"), .known)
        XCTAssertEqual(chips.status(of: "baywheels.stations.0.name"), .known, "Array paths are known by their array name")
        XCTAssertNotEqual(chips.status(of: "weather.bogus"), .known)
        XCTAssertEqual(chips.preview(of: "weather.temperature"), "72")
        XCTAssertFalse(TemplateCatalog.sample(authoritative: false).variableCatalog.isAuthoritative)
        XCTAssertEqual(TemplateCatalog.sample(authoritative: true).plugins.map(\.id).sorted(), ["date_time", "home_assistant", "stocks", "weather"])
    }
}

final class FunctionCatalogTests: XCTestCase {
    func testDictionaryKeyedByNameGroupsInTheWebOrderWithUnknownCategoriesAppended() throws {
        let data = Data(#"""
        {"functions": {
          "UPPER": {"category": "text", "signature": "UPPER(text)", "summary": "Upper case"},
          "IF": {"category": "logic", "signature": "IF(cond, a, b)", "summary": "Choose"},
          "AND": {"category": "logic", "signature": "AND(a, b)", "summary": "Both"},
          "ROUND": {"category": "math", "signature": "ROUND(n, d)", "summary": "Round"},
          "HEX": {"category": "color", "signature": "HEX(c)", "summary": "Hex"},
          "ZIP": {"category": "zeta", "signature": "ZIP(a)", "summary": "?"},
          "WOBBLE": {"category": "experimental", "signature": "WOBBLE()", "summary": "Mock-only"},
          "COUNT": {"category": "array", "signature": "COUNT(xs)", "summary": "Count"},
          "NOW": {"category": "date", "signature": "NOW()", "summary": "Now"},
          "TEXT": {"category": "convert", "signature": "TEXT(v)", "summary": "Text"}
        }}
        """#.utf8)
        let catalog = try FunctionCatalog(data: data)
        XCTAssertEqual(catalog.categories.map(\.name), ["logic", "array", "date", "math", "text", "convert", "color", "experimental", "zeta"])
        XCTAssertEqual(catalog.categories.first?.functions.map(\.name), ["AND", "IF"], "Sorted by name within a category")
        XCTAssertEqual(catalog.categories.first?.functions.last?.signature, "IF(cond, a, b)")
        XCTAssertTrue(catalog.names.contains("WOBBLE"))
        XCTAssertEqual(FunctionCatalog.title("convert"), "Conversion")
        XCTAssertEqual(FunctionCatalog.title("experimental"), "Experimental")
        XCTAssertThrowsError(try FunctionCatalog(data: Data(#"{"functions": ["IF"]}"#.utf8)))
        XCTAssertEqual(FunctionCatalog.builtIn.categories.map(\.name), FunctionCatalog.categoryOrder)
    }
}

final class FormulaHighlighterTests: XCTestCase {
    private func kinds(_ expression: String) -> [String] {
        let text = expression as NSString
        return FormulaHighlighter.tokens(expression).map { "\($0.kind.rawValue):\(text.substring(with: $0.range))" }
    }

    func testFunctionsStringsNumbersAndVariablesAreColouredLikeTheWeb() {
        XCTAssertEqual(kinds(#"IF(weather.temperature > 70, "WARM", "COOL")"#), [
            "function:IF", "punctuation:(", "variable:weather.temperature", "operator:>", "number:70", "punctuation:,",
            #"string:"WARM""#, "punctuation:,", #"string:"COOL""#, "punctuation:)",
        ])
        XCTAssertEqual(kinds("ROUND(stocks.price*1.5, 2) != 3"), [
            "function:ROUND", "punctuation:(", "variable:stocks.price", "operator:*", "number:1.5", "punctuation:,",
            "number:2", "punctuation:)", "operator:!=", "number:3",
        ])
        XCTAssertEqual(kinds(#"UPPER("abc"#), ["function:UPPER", "punctuation:(", #"string:"abc"#], "An unclosed string runs to the end")
        XCTAssertEqual(kinds("a >= b"), ["variable:a", "operator:>=", "variable:b"])
        XCTAssertEqual(kinds("baywheels.stations.0.name"), ["variable:baywheels.stations.0.name"])
    }

    func testPrettyPrintAndFlattenRoundTrip() {
        let flat = #"IF(weather.temperature > 70, "A, B", UPPER(x))"#
        let pretty = FormulaHighlighter.pretty(flat)
        XCTAssertEqual(pretty, "IF(\n  weather.temperature > 70,\n  \"A, B\",\n  UPPER(\n    x\n  )\n)")
        XCTAssertEqual(FormulaHighlighter.flatten(pretty), #"IF(weather.temperature > 70,"A, B",UPPER(x))"#,
                       "Flatten collapses lines and indentation (spaces after commas are not restored, as on the web)")
        let scaffold = FormulaHighlighter.scaffold("IF")
        XCTAssertEqual(scaffold.text, "IF(\n  \n)")
        XCTAssertEqual(scaffold.caret, 6, "The caret sits inside the parentheses")
    }
}

@MainActor final class FormulaValidationStateTests: XCTestCase {
    func testIdleValidatingValidInvalidAndPrefixStripping() async {
        var asked: [String] = []
        let validator = FormulaValidator(delay: .zero) { expression in
            asked.append(expression)
            if expression.contains("BOGUS") {
                return FormulaCheck(TemplateValidationResultFactory.invalid("Formula #NAME?: Unknown function: BOGUS"))
            }
            return FormulaCheck(valid: true, messages: [])
        }
        XCTAssertEqual(validator.status, .idle)
        validator.update(#"IF(1>0,"A","B")"#)
        XCTAssertEqual(validator.status, .validating)
        XCTAssertFalse(validator.canConfirm(#"IF(1>0,"A","B")"#), "Not while validating")
        await validator.pending?.value
        XCTAssertEqual(validator.status, .valid)
        XCTAssertTrue(validator.canConfirm(#" IF(1>0,"A","B") "#), "Trimmed expression equals the last valid one")
        validator.update("BOGUS(1)")
        await validator.pending?.value
        XCTAssertEqual(validator.status, .invalid(["#NAME?: Unknown function: BOGUS"]), "The leading \"Formula \" is stripped")
        XCTAssertFalse(validator.canConfirm("BOGUS(1)"))
        XCTAssertFalse(validator.canConfirm(#"IF(1>0,"A","B")"#), "A valid verdict for another expression doesn't count")
        validator.update("   ")
        XCTAssertEqual(validator.status, .idle)
        XCTAssertEqual(asked, [#"IF(1>0,"A","B")"#, "BOGUS(1)"])
        XCTAssertEqual(FormulaValidator.displayMessage("Unknown filter: x"), "Unknown filter: x")
    }

    func testNetworkFailureReturnsToIdleAndStaleAnswersAreDropped() async {
        var fail = true
        let validator = FormulaValidator(delay: .zero) { _ in
            if fail { throw FiestaBoardError.networkUnavailable }
            return FormulaCheck(valid: true, messages: [])
        }
        validator.update("NOW()")
        await validator.pending?.value
        XCTAssertEqual(validator.status, .idle, "A failed round trip gives no verdict and is not retried")
        fail = false
        // Typing again starts a new round; the older one's task is cancelled before it answers.
        let slow = FormulaValidator(delay: .milliseconds(200)) { _ in FormulaCheck(valid: true, messages: []) }
        slow.update("A(")
        slow.update("NOW()")
        await slow.pending?.value
        XCTAssertEqual(slow.status, .valid)
        XCTAssertTrue(slow.canConfirm("NOW()"))
        XCTAssertFalse(slow.canConfirm("A("))
    }

    func testLocalCheckMatchesTheFixtureRule() {
        let names: Set<String> = ["IF", "UPPER"]
        XCTAssertTrue(FormulaValidator.localCheck(#"IF(1>0,"A(","B")"#, functions: names).valid, "Parentheses inside strings don't count")
        XCTAssertEqual(FormulaValidator.localCheck("BOGUS(1)", functions: names).messages, ["#NAME?: Unknown function: BOGUS"])
        XCTAssertEqual(FormulaValidator.localCheck("IF(1", functions: names).messages, ["#ERROR!: Mismatched parentheses"])
        XCTAssertTrue(FormulaValidator.localCheck("weather.temperature + 1", functions: names).valid)
    }
}

enum TemplateValidationResultFactory {
    static func invalid(_ message: String) -> TemplateValidationResult {
        try! TemplateValidationResult(rawData: Data(#"{"valid":false,"errors":[{"line":1,"column":1,"message":"\#(message)"}]}"#.utf8))
    }
}
