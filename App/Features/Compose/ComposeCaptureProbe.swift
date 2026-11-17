#if DEBUG && canImport(ScreenCaptureKit)
import SwiftUI
import UIKit
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin

private struct ComposeCaptureRawPlane: Codable, Sendable {
    let width: Int, height: Int, bytesPerRow: Int
    let bytes: Data
}
private struct ComposeCaptureRawSample: Sendable {
    let metadata: ComposeCaptureProbeFrame
    let planes: [ComposeCaptureRawPlane]
}
private final class ComposeCaptureSampleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    private var filterRect: ComposeCaptureProbeRect?
    private var filterScale: Double?
    func configure(rect: ComposeCaptureProbeRect, scale: Double) {
        lock.lock(); defer { lock.unlock() }; filterRect = rect; filterScale = scale
    }
    func claim() -> (ComposeCaptureProbeRect, Double)? {
        lock.lock(); defer { lock.unlock() }
        guard !claimed, let filterRect, let filterScale else { return nil }
        claimed = true; return (filterRect, filterScale)
    }
}
/// An immutable SDK filter is transferred once to the MainActor owner.
@available(iOS 27.0, *)
private final class ComposeCaptureFilterTransfer: @unchecked Sendable {
    let value: SCContentFilter
    init(_ value: SCContentFilter) { self.value = value }
}

@available(iOS 27.0, *)
@MainActor private final class ComposeCaptureProbeController: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    @Published private(set) var phase = "idle"
    @Published private(set) var reportJSON = ""
    private var lifecycle: ComposeCaptureProbeLifecycle
    private let namespace: String
    private let gate = ComposeCaptureSampleGate()
    private let sampleQueue = DispatchQueue(label: "FiestaBoard.composeCapabilitySample")
    private var stream: SCStream?
    private var streamID: ObjectIdentifier?
    private var startInFlight = false
    private var cleanupInFlight = false
    private var observing = false
    private var oldConfiguration: SCContentSharingPickerConfiguration?
    private var oldPickerActive = false
    private var deadline: Task<Void, Never>?
    private var cleanupDeadline: Task<Void, Never>?
    private var rawSample: ComposeCaptureRawSample?
    private var pendingSample: ComposeCaptureRawSample?
    private let outputURL: URL
    init(namespace: String) {
        self.namespace = namespace
        lifecycle = .init(enabled: true, namespace: namespace, osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        outputURL = UserDefaults.standard.string(forKey: "fiestaboard.captureComposeCapabilityOut").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ComposeCaptureProbe/" + namespace)
        super.init()
    }
    func request() {
        let picker = SCContentSharingPicker.shared
        guard lifecycle.requestStart(isAvailable: picker.isAvailable) else { publish(); return }
        oldConfiguration = picker.defaultConfiguration; oldPickerActive = picker.isActive
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false; configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self); observing = true; picker.isActive = true
        publish()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self else { return }; lifecycle.deadlineExpired(); publish(); cleanUp()
        }
        // Explicit current-app picker; no enumeration, automatic consent or wider filter.
        picker.presentPickerForCurrentApplication()
    }
    func stop(inactive: Bool = false) {
        if inactive { lifecycle.sceneBecameInactive() } else { lifecycle.stopRequested() }
        publish(); cleanUp()
    }
    private func selected(_ filter: SCContentFilter) {
        guard lifecycle.selectedCurrentApplication() else { return }
        guard !filter.isMicrophoneEnabled, !filter.isCameraEnabled else {
            lifecycle.failed(domain: "ComposeCaptureProbe.unexpectedMedia", code: 1); publish(); cleanUp(); return
        }
        let rect = filter.contentRect
        gate.configure(rect: .init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height), scale: Double(filter.pointPixelScale))
        let configuration = SCStreamConfiguration(); configuration.capturesAudio = false
        let owned = SCStream(filter: filter, configuration: configuration, delegate: self)
        stream = owned; streamID = ObjectIdentifier(owned); startInFlight = true
        do { try owned.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue) }
        catch { startInFlight = false; failed(error); return }
        publish()
        Task { [weak self, owned] in
            do {
                try await owned.startCapture()
                guard let self else { try? await owned.stopCapture(); return }
                startInFlight = false; lifecycle.streamStarted(); publish()
                if let pendingSample { self.pendingSample = nil; received(pendingSample) }
                cleanUp()
            } catch {
                guard let self else { return }; startInFlight = false; failed(error)
            }
        }
    }
    private func failed(_ error: any Error) {
        let error = error as NSError
        lifecycle.failed(domain: error.domain, code: error.code); publish(); cleanUp()
    }
    private func received(_ sample: ComposeCaptureRawSample) {
        if lifecycle.phase == .starting { pendingSample = sample; return }
        guard lifecycle.phase == .capturing else { return }
        lifecycle.receivedFrame(sample.metadata)
        if lifecycle.cleanupRequested { rawSample = sample; publish(); cleanUp() }
    }
    private func cleanUp() {
        guard (lifecycle.cleanupRequested || (lifecycle.phase == .finished && stream != nil)), !cleanupInFlight else { return }
        deadline?.cancel(); deadline = nil
        if observing {
            let picker = SCContentSharingPicker.shared
            picker.remove(self); observing = false
            if let oldConfiguration { picker.defaultConfiguration = oldConfiguration }
            picker.isActive = oldPickerActive
        }
        if cleanupDeadline == nil {
            cleanupDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                lifecycle.cleanupFailed(domain: "ComposeCaptureProbe.cleanupTimeout", code: 1); publish()
            }
        }
        // A late start completion must stop its own stream, even after timeout.
        guard !startInFlight else { return }
        cleanupInFlight = true
        guard let owned = stream else { finishCleanup(); return }
        Task { [weak self, owned] in
            guard let self else { try? await owned.stopCapture(); return }
            do {
                if owned.isCapturing { try await owned.stopCapture() }
                try owned.removeStreamOutput(self, type: .screen)
                finishCleanup()
            } catch {
                let error = error as NSError
                lifecycle.cleanupFailed(domain: error.domain, code: error.code); publish()
            }
        }
    }
    private func finishCleanup() {
        cleanupDeadline?.cancel(); cleanupDeadline = nil
        stream = nil; streamID = nil; pendingSample = nil
        lifecycle.cleanedUp(); publish()
    }
    private func publish() {
        phase = lifecycle.phase.rawValue
        guard let report = lifecycle.report else { return }
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            var envelope = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
            envelope["os"] = ProcessInfo.processInfo.operatingSystemVersionString
            envelope["sdk"] = Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "unknown"
            envelope["namespace"] = namespace
            envelope["measurementEmitted"] = false
            if report.status == "metadata_captured", let rawSample {
                var planes: [[String: Any]] = []
                for (index, plane) in rawSample.planes.enumerated() {
                    let name = "sample-plane-\(index).bin"
                    try plane.bytes.write(to: outputURL.appendingPathComponent(name), options: .atomic)
                    planes.append(["file": name, "width": plane.width, "height": plane.height, "bytesPerRow": plane.bytesPerRow,
                        "bytes": plane.bytes.count, "sha256": SHA256.hash(data: plane.bytes).map { String(format: "%02x", $0) }.joined()])
                }
                envelope["rawPlanes"] = planes
            }
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: outputURL.appendingPathComponent("capability.json"), options: .atomic)
            reportJSON = String(decoding: data, as: UTF8.self)
        } catch {
            reportJSON = #"{"status":"failed","reason":"artifact_write_failed","measurementEmitted":false}"#
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor [weak self] in guard let self else { return }; lifecycle.pickerCancelled(); publish(); cleanUp() }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        let transferred = ComposeCaptureFilterTransfer(filter)
        Task { @MainActor [weak self] in self?.selected(transferred.value) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let error = error as NSError, domain = error.domain, code = error.code
        Task { @MainActor [weak self] in guard let self else { return }; lifecycle.failed(domain: domain, code: code); publish(); cleanUp() }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let id = ObjectIdentifier(stream), error = error as NSError, domain = error.domain, code = error.code
        Task { @MainActor [weak self] in
            guard let self, streamID == id else { return }
            lifecycle.failed(domain: domain, code: code); publish(); cleanUp()
        }
    }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first, (info[.status] as? NSNumber)?.intValue == SCFrameStatus.complete.rawValue,
              let (filterRect, filterScale) = gate.claim() else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            Task { @MainActor [weak self] in self?.failed(NSError(domain: "ComposeCaptureProbe.missingImage", code: 1)) }; return
        }
        func rect(_ raw: Any?) -> ComposeCaptureProbeRect? {
            if let value = raw as? NSValue {
                let r = value.cgRectValue; return .init(x: r.minX, y: r.minY, width: r.width, height: r.height)
            }
            guard let d = raw as? [String: Any], let x = d["X"] as? NSNumber, let y = d["Y"] as? NSNumber,
                  let w = d["Width"] as? NSNumber, let h = d["Height"] as? NSNumber else { return nil }
            return .init(x: x.doubleValue, y: y.doubleValue, width: w.doubleValue, height: h.doubleValue)
        }
        var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
        let frame = ComposeCaptureProbeFrame(outputType: "screen", status: SCFrameStatus.complete.rawValue,
            displayTicks: (info[.displayTime] as? NSNumber)?.uint64Value, receivedTicks: mach_absolute_time(),
            timebaseNumer: timebase.numer, timebaseDenom: timebase.denom,
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), pixelFormat: CVPixelBufferGetPixelFormatType(buffer),
            videoOrientation: (info[.videoOrientation] as? NSNumber)?.intValue, contentRect: rect(info[.contentRect]),
            contentScale: (info[.contentScale] as? NSNumber)?.doubleValue, scaleFactor: (info[.scaleFactor] as? NSNumber)?.doubleValue,
            screenRect: rect(info[.screenRect]), filterContentRect: filterRect, filterPointPixelScale: filterScale)
        var planes: [ComposeCaptureRawPlane] = []
        if frame.valid, CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess {
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let count = CVPixelBufferGetPlaneCount(buffer)
            var total = 0
            for index in 0..<max(1, count) {
                let width = count == 0 ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetWidthOfPlane(buffer, index)
                let height = count == 0 ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetHeightOfPlane(buffer, index)
                let row = count == 0 ? CVPixelBufferGetBytesPerRow(buffer) : CVPixelBufferGetBytesPerRowOfPlane(buffer, index)
                let (size, overflow) = row.multipliedReportingOverflow(by: height)
                let address = count == 0 ? CVPixelBufferGetBaseAddress(buffer) : CVPixelBufferGetBaseAddressOfPlane(buffer, index)
                guard !overflow, size > 0, size <= 67_108_864 - total, let address else { planes = []; break }
                total += size
                planes.append(.init(width: width, height: height, bytesPerRow: row, bytes: Data(bytes: address, count: size)))
            }
        }
        guard !frame.valid || !planes.isEmpty else {
            Task { @MainActor [weak self] in self?.failed(NSError(domain: "ComposeCaptureProbe.unreadableImage", code: 1)) }; return
        }
        let sample = ComposeCaptureRawSample(metadata: frame, planes: planes)
        Task { @MainActor [weak self] in self?.received(sample) }
    }
}

@available(iOS 27.0, *)
private struct ComposeCaptureProbePanel: View {
    @StateObject private var controller: ComposeCaptureProbeController
    @Environment(\.scenePhase) private var scenePhase
    init(namespace: String) { _controller = StateObject(wrappedValue: ComposeCaptureProbeController(namespace: namespace)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Run capture capability probe") { controller.request() }
                .disabled(controller.phase != "idle").accessibilityIdentifier("composeCaptureProbeStart")
            Text(controller.phase).accessibilityIdentifier("composeCaptureProbePhase")
            if !controller.reportJSON.isEmpty {
                Text("Capture capability report").accessibilityIdentifier("composeCaptureProbeReport")
                    .accessibilityValue(controller.reportJSON)
            }
            if controller.phase != "idle", controller.phase != "finished" {
                Button("Stop capability probe") { controller.stop() }.accessibilityIdentifier("composeCaptureProbeStop")
            }
        }.font(.caption)
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stop(inactive: true) } }
        .onDisappear { controller.stop() }
    }
}

struct ComposeCaptureProbeControls: View {
    var body: some View {
        if UserDefaults.standard.bool(forKey: "fiestaboard.captureComposeCapability"),
           let namespace = ProcessInfo.processInfo.environment["FIESTABOARD_TEST_NAMESPACE"], UUID(uuidString: namespace) != nil {
            if #available(iOS 27.0, *) { ComposeCaptureProbePanel(namespace: namespace) }
            else {
                Text("Capture capability report").accessibilityIdentifier("composeCaptureProbeReport")
                    .accessibilityValue(#"{"status":"failed","reason":"unsupported_os","measurementEmitted":false}"#)
            }
        }
    }
}
#endif
