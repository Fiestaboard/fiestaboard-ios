import XCTest
@testable import FiestaBoardDocuments

/// PLAN B13/B31: kind → chip style, labels and spoken labels (the drawing is `TemplateChipFactoryTests`).
final class TemplateChipTests: XCTestCase {
    private func chip(_ source: String, _ catalog: VariableCatalog? = nil) -> TemplateChip? {
        TemplateSyntax.fragments(source).compactMap { TemplateChip(fragment: $0, variables: catalog) }.first
    }

    func testBarRowTwoKinds() {
        let row = #"TEMP {{weather.temperature|pad:3}} {{= IF(weather.temperature>70,"HI","") }} {{blue}}"#
        let chips = TemplateSyntax.fragments(row).compactMap { TemplateChip(fragment: $0) }
        XCTAssertEqual(chips.map(\.style), [.variable, .formula, .tile(color: "blue")])
        XCTAssertEqual(chips[0].title, "weather.temperature")
        XCTAssertEqual(chips[0].filters, ["pad:3"])
        XCTAssertEqual(chips[1].title, #"IF(weather.temperatu…"#)
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(chip("{{weather.temperature|pad:3}}")?.accessibilityLabel, "variable weather.temperature, filter pad 3")
        XCTAssertEqual(chip("{{red}}")?.accessibilityLabel, "red tile")
        XCTAssertEqual(chip("{{purple}}")?.accessibilityLabel, "violet tile")
        XCTAssertEqual(chip(#"{{= IF(1>0,"A","B") }}"#)?.accessibilityLabel, #"formula, IF(1>0,"A","B")"#)
        XCTAssertEqual(chip("{{fill_space}}")?.accessibilityLabel, "fill space")
        XCTAssertEqual(chip("{{red:HOT}}")?.style, .span(color: "red"))
        XCTAssertEqual(chip("{{red:HOT}}")?.title, "HOT")
        XCTAssertEqual(chip("{{icon:sun}}")?.style, .icon)
        XCTAssertEqual(chip("{{icon:sun}}")?.title, "sun")
        XCTAssertEqual(chip("{{=}}")?.title, "new formula")
    }

    func testUnknownVariablesWarnOnlyAgainstAnAuthoritativeCatalog() {
        let strict = VariableCatalog.sample(authoritative: true)
        XCTAssertEqual(chip("{{weather.temperature}}", strict)?.style, .variable)
        XCTAssertEqual(chip("{{WEATHER.Temperature}}", strict)?.style, .variable)
        guard case .unknownVariable(let reason)? = chip("{{bogus.thing}}", strict)?.style else { return XCTFail("bogus must warn") }
        XCTAssertTrue(reason.contains("???"))
        XCTAssertTrue(reason.contains("bogus"))
        guard case .unknownVariable(let field)? = chip("{{weather.nope|pad:2}}", strict)?.style else { return XCTFail("field must warn") }
        XCTAssertTrue(field.contains("Weather has no “nope”"))
        XCTAssertTrue(chip("{{bogus.thing}}", strict)!.accessibilityLabel.contains("warning"))
        XCTAssertEqual(chip("{{bogus.thing}}", .sample(authoritative: false))?.style, .variable)
        XCTAssertEqual(chip("{{bogus.thing}}")?.style, .variable)
    }

    func testInsertionsParseBackToTheirChips() {
        for color in TemplateInsertion.colors {
            XCTAssertEqual(chip(TemplateInsertion.color(color))?.style, .tile(color: color))
        }
        for entry in TemplateInsertion.formatting { XCTAssertEqual(chip(entry.source)?.style, .fill) }
        XCTAssertEqual(chip(TemplateInsertion.variable("weather", "condition"))?.title, "weather.condition")
        XCTAssertEqual(chip(TemplateInsertion.formula(" IF(1>0,\"A\",\"B\") ")!)?.style, .formula)
        XCTAssertNil(TemplateInsertion.formula("  "))
        XCTAssertNil(TemplateInsertion.formula("a}}b"))
    }

    func testSampleValuesReadLikeABoard() {
        let catalog = VariableCatalog.sample(authoritative: true)
        let rows = SampleValues.resolve([
            "TEMP {{weather.temperature|pad:3}}° {{weather.condition}}",
            #"{{= IF(weather.temperature > 70, "WARM", "COOL") }} {{red}}"#,
            "{{bogus.thing}} {{= BOGUS(1) }}",
            "{{= UPPER(date_time.day_of_week) }}",
        ], catalog: catalog)
        // Re-recorded (P1): `pad:3` is the server's `ljust(3)[:3]` ("72 "), not a right-justify.
        XCTAssertEqual(rows, ["TEMP 72 ° SUNNY", "WARM {{red}}", "??? ???", "SUNDAY"])
    }

    /// The server's filters (`src/templates/engine.py`): pad = ljust(N)[:N], truncate cuts,
    /// zeropad left-pads with zeros and keeps a leading minus.
    func testSampleFiltersMatchTheServer() {
        let catalog = VariableCatalog.sample(authoritative: true)
        func value(_ inner: String) -> String { SampleValues.variable(inner, catalog) }
        XCTAssertEqual(value("weather.temperature|pad:4"), "72  ")
        XCTAssertEqual(value("weather.condition|pad:3"), "SUN")
        XCTAssertEqual(value("weather.condition|truncate:2"), "SU")
        XCTAssertEqual(value("weather.temperature|zeropad:4"), "0072")
        XCTAssertEqual(value("weather.condition|lower"), "sunny")
    }

    /// P1 compact chips: the label is the field, the plugin a source mark, filters tiny badges,
    /// and the token's board width is known when a filter or a sample value fixes it.
    func testCompactLabelsAndBoardWidth() throws {
        let padded = try XCTUnwrap(chip("{{weather.temperature|pad:3}}"))
        XCTAssertEqual(padded.plugin, "weather")
        XCTAssertEqual(padded.shortTitle, "temperature")
        XCTAssertEqual(padded.compactFilters, ["3"])
        XCTAssertEqual(padded.sourceMark, "W")
        XCTAssertEqual(padded.boardWidth(), 3)
        XCTAssertEqual(padded.title, "weather.temperature", "the identifier is kept whole")
        let bare = try XCTUnwrap(chip("{{weather.temperature}}"))
        XCTAssertNil(bare.boardWidth(), "unknown until rendered")
        XCTAssertEqual(bare.boardWidth(sampleLength: 2), 2)
        XCTAssertEqual(chip("{{weather.condition|truncate:3}}")?.boardWidth(sampleLength: 5), 3)
        XCTAssertEqual(chip("{{date_time.day|zeropad:2}}")?.boardWidth(sampleLength: 1), 2)
        XCTAssertEqual(chip("{{weather.condition|truncate:3}}")?.compactFilters, ["≤3"])
        XCTAssertEqual(chip("{{stocks.AAPL.price}}")?.shortTitle, "AAPL.price")
        XCTAssertEqual(chip("{{baywheels.stations.0.name}}")?.shortTitle, "name", "indexes dropped; over 12 → last segment")
        XCTAssertEqual(chip("{{stocks.items.0.price}}")?.shortTitle, "items.price")
        XCTAssertEqual(chip("{{weather.temperature|zeropad:2|upper|lower|wrap|pad}}")?.compactFilters, ["02", "AB", "ab", "↵", "pad"])
        XCTAssertEqual(chip(#"{{= IF(weather.temperature>70,"HI","") }}"#)?.shortTitle, "IF(weathe…")
        XCTAssertEqual(chip(#"{{= NOW() }}"#)?.shortTitle, "NOW()")
        XCTAssertEqual(chip("{{date_time.time}}")?.sourceMark, "D")
        XCTAssertEqual(chip("{{bogus.thing}}", .sample(authoritative: true))?.sourceMark, "!")
        XCTAssertEqual(TemplateChip.detail(source: "{{weather.temperature|pad:3}}", chip: chip("{{weather.temperature|pad:3}}")), "weather.temperature | pad:3")
        XCTAssertTrue(TemplateChip.detail(source: "{{bogus.thing}}", chip: chip("{{bogus.thing}}", .sample(authoritative: true))).contains("???"))
        XCTAssertNil(chip("{{nodot}}")?.plugin)
        XCTAssertEqual(chip("{{nodot}}")?.shortTitle, "nodot")
        XCTAssertEqual(chip("{{red}}")?.boardWidth(), 1)
        XCTAssertNil(chip(#"{{= IF(1>0,"A","B") }}"#)?.boardWidth())
        XCTAssertEqual(chip("{{fill_space}}")?.shortTitle, "fill")
        XCTAssertEqual(chip("{{fill_space_repeat:-}}")?.shortTitle, "fill -")
        XCTAssertEqual(chip("{{bogus.thing}}", .sample(authoritative: true))?.boardWidth(), 3, "??? is three cells")
        XCTAssertEqual(VariableCatalog.sample(authoritative: false).preview(of: "WEATHER.temperature"), "72")
    }
}
