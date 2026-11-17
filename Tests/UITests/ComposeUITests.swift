import XCTest
import CryptoKit

/// Native navigation/interaction checks use synthetic scenario glue around the
/// vendored authenticated Compose corpus. They are not physical-output proof.
@MainActor final class ComposeUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func missingCaptureEvidence(_ app: XCUIApplication, system: XCUIApplication, stage: String,
                                        expectedIdentifier: String, elementObserved: Bool, valueObserved: Bool = false,
                                        reason: String = "required_app_report_not_observed") {
        shot("i8-capture-harness-failure-" + stage)
        let hierarchy = XCTAttachment(string: app.debugDescription + "\n\nSPRINGBOARD\n" + system.debugDescription)
        hierarchy.name = "i8-capture-harness-observed-hierarchy-" + stage
        hierarchy.lifetime = .keepAlways; add(hierarchy)
        let payload: [String: Any] = ["origin": "xctest_harness", "status": "failed", "stage": stage,
            "reason": reason, "expectedIdentifier": expectedIdentifier,
            "appReportElementObserved": elementObserved, "appReportValueObserved": valueObserved,
            "measurementEmitted": false]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        metadata.name = "i8-capture-harness-failure-" + stage; metadata.lifetime = .keepAlways; add(metadata)
    }

    private func tapReady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: element)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Compose control must be ready: \(element.debugDescription)", file: file, line: line)
            return
        }
        element.tap()
    }

    func testComposeSheetShowsExplicitDurationSilenceAndRetainsCanceledDraft() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        XCTAssertTrue(app.buttons["composeShowNow"].exists)
        XCTAssertTrue(app.buttons["composeDisplayPicker"].exists)
        XCTAssertTrue(app.buttons["composeDuration"].exists)
        app.buttons["composeSilence"].tap()
        XCTAssertTrue(app.buttons["Hold until silence ends"].waitForExistence(timeout: 3))
        app.buttons["Hold until silence ends"].tap()
        shot("i8-compose-typing-native-sheet")
        app.buttons["composeCancel"].tap()
        XCTAssertTrue(app.buttons["homeCompose"].waitForExistence(timeout: 5))
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }

    func testLEDToolbarDoesNotOfferUnadvertisedIconAndWarnsAboutActualClipping() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        app.buttons["composeDisplayPicker"].tap()
        app.buttons["Entry clock"].tap()
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("ABCDEFGHIJKLMNOPQRS")
        XCTAssertTrue(app.staticTexts["composeClippingWarning"].waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "ABCDEFGHIJKLMNOPQRS")
        app.buttons["composeIcons"].tap()
        XCTAssertTrue(app.buttons["sun"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["cake"].exists)
        shot("i8-compose-led-capability-menu")
    }

    func testUnconfirmedSendKeepsSourceAndBlocksRetargetAndReplay() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose-unknown")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Keep this draft")
        tapReady(app.buttons["composeShowNow"])
        XCTAssertTrue(app.staticTexts["composeOutcome"].waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeDisplayPicker"].isEnabled)
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
        shot("i8-compose-unconfirmed-source-retained")
        app.buttons["composeCancel"].tap()
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "Keep this draft")
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
    }

    func testAmbiguousSendKeepsExactUUIDOutcomeActionAcrossReopen() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose-ambiguous")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Keep ambiguous draft")
        tapReady(app.buttons["composeShowNow"])
        XCTAssertTrue(app.buttons["composeCheckOutcome"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["composeCheckOutcome"].label, "Check message outcome")
        app.buttons["composeCancel"].tap()
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        tapReady(app.buttons["composeCheckOutcome"])
        XCTAssertEqual(source.value as? String, "Keep ambiguous draft")
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
        XCTAssertFalse(app.buttons["composeDisplayPicker"].isEnabled)
    }

    func testAcknowledgedHeldDraftRetainsReachableOutcomeActionUntilReleased() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose-held")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Deferred draft")
        tapReady(app.buttons["composeShowNow"])
        XCTAssertTrue(app.buttons["composeCheckOutcome"].waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Deferred draft")
        tapReady(app.buttons["composeCheckOutcome"])
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 8), .completed)
    }

    func testSaveAsPageKeepsTheUnsentComposeSource() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        app.buttons["composeMore"].tap()
        app.buttons["Save as Page"].tap()
        XCTAssertTrue(app.textFields["composePageName"].waitForExistence(timeout: 5))
        shot("i8-save-as-page-native-sheet")
        app.buttons["composeSavePage"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.textFields["composePageName"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Dinner at seven")
    }

    func testUnsentDraftSurvivesColdOfflineRelaunch() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose", remember: true)
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Keep offline exactly")
        app.buttons["composeCancel"].tap()
        XCTAssertTrue(app.buttons["homeCompose"].waitForExistence(timeout: 5))
        app.terminate()
        FixtureHTTPServer.shared.setDropped(true)
        defer { FixtureHTTPServer.shared.setDropped(false); app.terminate() }
        app.launch()
        XCTAssertTrue(app.buttons["homeCompose"].waitForExistence(timeout: 15))
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertEqual(source.value as? String, "Keep offline exactly")
        XCTAssertTrue(app.otherElements["composeOfflineNotice"].exists)
        XCTAssertFalse(app.buttons["composeShowNow"].isEnabled)
        shot("i8-compose-cold-offline-draft-retained")
    }

    func testAcceptedReadbackClearsTheSentDraft() {
        let app = isolatedApplication()
        launchFixture(app, scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap(); source.typeText("Dinner at seven")
        tapReady(app.buttons["composeShowNow"])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: source)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        tapReady(app.buttons["homeCompose"])
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, "")
    }

    /// Required diagnostic journey: unsupported/denied/timeout is an explicit
    /// failure artifact, never a skip or a presentation-performance estimate.
    func testExplicitCurrentAppCaptureCapabilityRecordsNativeMetadataOrFailure() throws {
        let app = isolatedApplication()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("i8-capability-" + UUID().uuidString)
        launchFixture(app, arguments: ["-fiestaboard.captureComposeCapability", "YES",
            "-fiestaboard.captureComposeCapabilityOut", output.path], scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start = app.buttons["composeCaptureProbeStart"]
        if !start.waitForExistence(timeout: 3) {
            shot("i8-capture-capability-unsupported-original-screen")
            let unsupported = app.staticTexts["composeCaptureProbeReport"]
            let raw = unsupported.exists ? unsupported.value as? String : nil
            if let raw {
                let artifact = XCTAttachment(data: Data(raw.utf8), uniformTypeIdentifier: "public.json")
                artifact.name = "i8-capture-capability-unsupported-app-report"; artifact.lifetime = .keepAlways; add(artifact)
            }
            missingCaptureEvidence(app, system: system, stage: "unsupported_startup",
                expectedIdentifier: "composeCaptureProbeStart", elementObserved: unsupported.exists,
                valueObserved: raw != nil, reason: "required_probe_control_unavailable")
            let hierarchy = XCTAttachment(string: app.debugDescription + "\n\nSPRINGBOARD\n" + system.debugDescription)
            hierarchy.name = "i8-capture-capability-unsupported-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail("Required capability probe cannot start; failed metadata and original screen attached")
            return
        }
        XCTAssertEqual(app.staticTexts["composeCaptureProbePhase"].label, "idle")
        tapReady(start)
        shot("i8-capture-capability-original-native-picker")
        // This is explicit native consent after the diagnostic button. No
        // permission is bypassed. The selector is pending actual runtime proof;
        // an unrecognized picker ends as timeout with its original screenshot.
        let systemStart = system.buttons["Start Recording"]
        if systemStart.waitForExistence(timeout: 3) { tapReady(systemStart) }
        else if app.buttons["Start Recording"].exists { tapReady(app.buttons["Start Recording"]) }
        else {
            let hierarchy = XCTAttachment(string: app.debugDescription + "\n\nSPRINGBOARD\n" + system.debugDescription)
            hierarchy.name = "i8-capture-capability-unverified-picker-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        let report = app.staticTexts["composeCaptureProbeReport"]
        guard report.waitForExistence(timeout: 16) else {
            missingCaptureEvidence(app, system: system, stage: "awaiting_app_report_timeout",
                expectedIdentifier: "composeCaptureProbeReport", elementObserved: false)
            XCTFail("Required app capability report missing; observed UI and harness failure metadata attached")
            return
        }
        shot("i8-capture-capability-original-native-result")
        guard let raw = report.value as? String, !raw.isEmpty else {
            missingCaptureEvidence(app, system: system, stage: "app_report_value_missing",
                expectedIdentifier: "composeCaptureProbeReport", elementObserved: true)
            XCTFail("Required app capability report value missing; no app capture or cleanup result inferred")
            return
        }
        let data = Data(raw.utf8)
        let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        metadata.name = "i8-capture-capability-actual-report"; metadata.lifetime = .keepAlways; add(metadata)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if result["status"] as? String == "metadata_captured" {
            guard let planes = result["rawPlanes"] as? [[String: Any]], !planes.isEmpty else {
                missingCaptureEvidence(app, system: system, stage: "raw_plane_manifest_missing",
                    expectedIdentifier: "rawPlanes", elementObserved: true, valueObserved: true,
                    reason: "required_raw_plane_manifest_not_observed")
                XCTFail("App metadata report has no raw-plane manifest; capture proof is incomplete")
                return
            }
            for plane in planes {
                guard let file = plane["file"] as? String, !file.isEmpty, (file as NSString).lastPathComponent == file,
                      let bytes = try? Data(contentsOf: output.appendingPathComponent(file)) else {
                    missingCaptureEvidence(app, system: system, stage: "raw_plane_export_missing",
                        expectedIdentifier: plane["file"] as? String ?? "raw_sample_plane", elementObserved: true,
                        valueObserved: true, reason: "required_raw_plane_artifact_not_observed")
                    XCTFail("Raw capture plane is unavailable; no complete capture evidence inferred")
                    return
                }
                let original = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.data")
                original.name = file; original.lifetime = .keepAlways; add(original)
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard plane["bytes"] as? Int == bytes.count, plane["sha256"] as? String == digest else {
                    missingCaptureEvidence(app, system: system, stage: "raw_plane_integrity_mismatch",
                        expectedIdentifier: file, elementObserved: true, valueObserved: true,
                        reason: "raw_plane_artifact_does_not_match_app_manifest")
                    XCTFail("Actual attached raw plane differs from the app manifest")
                    return
                }
            }
        }
        XCTAssertEqual(result["measurementEmitted"] as? Bool, false)
        XCTAssertEqual(result["status"] as? String, "metadata_captured", "Required capture capability unavailable: \(raw)")
        XCTAssertEqual(result["cleanupCompleted"] as? Bool, true)
    }

    func testComposeControlsRemainAccessibleInDarkAX3() {
        let app = isolatedApplication()
        launchFixture(app, arguments: ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraLarge.rawValue], scenario: "i8-compose")
        tapReady(app.buttons["homeCompose"])
        let source = app.textViews["composeSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.label, "Message text")
        XCTAssertEqual(app.buttons["composeShowNow"].label, "Show now")
        XCTAssertTrue(app.buttons["composeCancel"].isHittable)
        source.tap(); source.typeText("Dinner at seven")
        shot("i8-compose-dark-ax3-native-sheet")
    }
}
