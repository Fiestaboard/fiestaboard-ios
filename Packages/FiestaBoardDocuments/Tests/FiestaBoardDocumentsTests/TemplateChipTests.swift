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
}
