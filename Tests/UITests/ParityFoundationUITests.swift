import XCTest
import UIKit

@MainActor final class ParityFoundationUITests: XCTestCase {
    private struct Export: Decodable {
        struct Node: Decodable { let id: String; let label: String?; let frame: CGRect }
        let nodes: [Node]
    }

    func testRegistryAndGlassOnActualScreen() throws {
        continueAfterFailure = false
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cx-i2-\(UUID().uuidString).json")
        let app = XCUIApplication()
        app.launchArguments = ["-fiestaboard.parityFixture", "glass", "-fiestaboard.figmaProbeOut", probeURL.path]
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let expected = pad ? CGSize(width: 1180, height: 820) : CGSize(width: 402, height: 874)
        let scale: CGFloat = pad ? 2 : 3
        XCUIDevice.shared.orientation = pad ? .landscapeLeft : .portrait
        app.launch()
        defer { app.terminate(); try? FileManager.default.removeItem(at: probeURL) }
        // Keep actual-screen evidence even if layout or glass assertions fail.
        defer {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "i2-glass-\(pad ? "ipad" : "iphone")"
            shot.lifetime = .keepAlways
            add(shot)
            if let data = try? Data(contentsOf: probeURL) {
                let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                json.name = "i2-registry"
                json.lifetime = .keepAlways
                add(json)
            }
        }
        let panel = app.descendants(matching: .any).matching(identifier: "figma:parity:glass").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let ready = NSPredicate { _, _ in
            guard abs(app.frame.width - expected.width) <= 1,
                  abs(app.frame.height - expected.height) <= 1,
                  let data = try? Data(contentsOf: probeURL),
                  let export = try? JSONDecoder().decode(Export.self, from: data) else { return false }
            // x/y stay fixed during rotation; width/height and both nodes must settle too.
            return ["parity:glass", "parity:title"].allSatisfy { id in
                guard let node = export.nodes.first(where: { $0.id == id }) else { return false }
                let element = app.descendants(matching: .any).matching(identifier: "figma:\(id)").firstMatch
                guard element.exists else { return false }
                let frame = element.frame
                return abs(frame.minX - node.frame.minX) <= 1 && abs(frame.minY - node.frame.minY) <= 1
                    && abs(frame.width - node.frame.width) <= 1 && abs(frame.height - node.frame.height) <= 1
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10), .completed)
        let exported = try JSONDecoder().decode(Export.self, from: Data(contentsOf: probeURL))
        for id in ["parity:glass", "parity:title"] {
            let node = try XCTUnwrap(exported.nodes.first { $0.id == id })
            let element = app.descendants(matching: .any).matching(identifier: "figma:\(id)").firstMatch
            let actual = element.frame
            XCTAssertEqual(actual.minX, node.frame.minX, accuracy: 1)
            XCTAssertEqual(actual.minY, node.frame.minY, accuracy: 1)
            XCTAssertEqual(actual.width, node.frame.width, accuracy: 1)
            XCTAssertEqual(actual.height, node.frame.height, accuracy: 1)
            XCTAssertEqual(element.label, node.label)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let screenshot = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(screenshot.image.cgImage)
        XCTAssertEqual(app.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(app.frame.height, expected.height, accuracy: 1)
        XCTAssertEqual(image.width, Int(expected.width * scale))
        XCTAssertEqual(image.height, Int(expected.height * scale))
        let measurement = try XCTUnwrap(GlassProbe.measure(image, scale: scale, panel: panel.frame))
        XCTAssertTrue(measurement.isTranslucentGlass, "\(measurement.dictionary)")
    }
}
