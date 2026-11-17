import XCTest
import SwiftUI
import FiestaBoardAppState
import FiestaBoardKit
import FiestaBoardRender
@testable import FiestaBoard

@MainActor final class ComposePresentationTests: XCTestCase {
    func testActualPreviewEvidenceLightDarkAX3AndReduceMotion() throws {
        let preview = try TemplatePreviewResult(rawData: Data(#"{"rendered":"DINNER AT SEVEN","lines":["DINNER AT SEVEN"],"line_count":1,"charset":"vestaboard_v1","charset_issues":[],"canvas_issues":[],"diagnostics":{"lines":[{"line":1,"widest":15,"cut":false,"rows_wanted":1,"rows_shown":1}]}}"#.utf8))
        let projection = try ComposePreviewProjection(preview: preview,
            summary: .init(deviceType: "flagship", rows: 6, cols: 22, charset: "vestaboard_v1"), drawing: nil)
        for appearance in [ColorScheme.light, .dark] {
            for type in [DynamicTypeSize.large, .accessibility3] {
                let image = IOSSnapshot.image(ComposePreviewPanel(projection: projection,
                    notice: .init(diagnosticsData: preview.rawData, stale: false, online: true),
                    displayName: "Kitchen board", updating: false, retry: {}).padding(),
                    appearance: appearance, dynamicType: type)
                let device = IOSSnapshot.Device.current
                XCTAssertEqual(image.size, device.size); XCTAssertEqual(image.scale, device.scale)
                IOSSnapshot.assertMatches(image, named: "i8-preview-\(appearance)-\(type == .large ? "default" : "ax3")", device: device)
            }
        }
    }
}
