#if DEBUG
import Foundation

struct ComposeCaptureProbeRect: Codable, Equatable, Sendable {
    let x: Double, y: Double, width: Double, height: Double
    var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

/// Raw capability metadata only. No native-presentation match or latency value.
struct ComposeCaptureProbeFrame: Codable, Equatable, Sendable {
    let outputType: String
    let status: Int
    let displayTicks: UInt64?
    let receivedTicks: UInt64
    let timebaseNumer: UInt32
    let timebaseDenom: UInt32
    let width: Int
    let height: Int
    let pixelFormat: UInt32
    let videoOrientation: Int?
    let contentRect: ComposeCaptureProbeRect?
    let contentScale: Double?
    let scaleFactor: Double?
    let screenRect: ComposeCaptureProbeRect?
    let filterContentRect: ComposeCaptureProbeRect?
    let filterPointPixelScale: Double?
    var valid: Bool {
        guard let displayTicks, displayTicks > 0, displayTicks <= receivedTicks,
              timebaseNumer > 0, timebaseDenom > 0,
              (1...16_384).contains(width), (1...16_384).contains(height),
              width * height <= 16_777_216, pixelFormat != 0,
              let videoOrientation, (1...8).contains(videoOrientation),
              contentRect?.valid == true, screenRect?.valid == true, filterContentRect?.valid == true,
              let contentScale, contentScale.isFinite, contentScale > 0,
              let scaleFactor, scaleFactor.isFinite, scaleFactor > 0,
              let filterPointPixelScale, filterPointPixelScale.isFinite, filterPointPixelScale > 0 else { return false }
        return true
    }
}

struct ComposeCaptureProbeReport: Codable, Equatable, Sendable {
    let status: String
    let reason: String?
    let frame: ComposeCaptureProbeFrame?
    let errorDomain: String?
    let errorCode: Int?
    let cleanupCompleted: Bool
}

/// One attempt, independently testable without ScreenCaptureKit or permission.
struct ComposeCaptureProbeLifecycle {
    enum Phase: String { case idle, awaitingConsent, starting, capturing, stopping, finished }
    private(set) var phase: Phase = .idle
    private(set) var report: ComposeCaptureProbeReport?
    private(set) var streamOwned = false
    var cleanupRequested: Bool { phase == .stopping }
    private let enabled: Bool
    private let namespace: String?
    private let osMajor: Int
    private var pending: ComposeCaptureProbeReport?
    init(enabled: Bool, namespace: String?, osMajor: Int) {
        self.enabled = enabled; self.namespace = namespace; self.osMajor = osMajor
    }
    mutating func requestStart(isAvailable: Bool) -> Bool {
        guard phase == .idle else { return false }
        let reason: String?
        if !enabled { reason = "disabled" }
        else if namespace?.isEmpty != false { reason = "missing_namespace" }
        else if UUID(uuidString: namespace!) == nil { reason = "invalid_namespace" }
        else if osMajor < 27 { reason = "unsupported_os" }
        else if !isAvailable { reason = "unavailable" }
        else { reason = nil }
        if let reason {
            phase = .finished
            report = .init(status: "failed", reason: reason, frame: nil, errorDomain: nil, errorCode: nil, cleanupCompleted: true)
            return false
        }
        phase = .awaitingConsent
        return true
    }
    mutating func selectedCurrentApplication() -> Bool {
        guard phase == .awaitingConsent else { return false }
        phase = .starting; return true
    }
    mutating func streamConstructed() { if phase == .starting { streamOwned = true } }
    mutating func streamStarted() { if phase == .starting, streamOwned { phase = .capturing } }
    mutating func requestCleanupRetry() -> Bool {
        guard phase == .finished, streamOwned, let report, !report.cleanupCompleted else { return false }
        pending = report; phase = .stopping; return true
    }
    mutating func receivedFrame(_ frame: ComposeCaptureProbeFrame) {
        guard phase == .capturing, frame.outputType == "screen", frame.status == 0 else { return }
        guard frame.valid else { stop(reason: "invalid_metadata"); return }
        pending = .init(status: "metadata_captured", reason: nil, frame: frame, errorDomain: nil, errorCode: nil, cleanupCompleted: false)
        phase = .stopping
    }
    mutating func pickerCancelled() { stop(reason: "cancelled") }
    mutating func failed(domain: String, code: Int) { stop(reason: "stream_error", domain: domain, code: code) }
    mutating func sceneBecameInactive() { stop(reason: "scene_inactive") }
    mutating func stopRequested() { stop(reason: "stopped") }
    mutating func deadlineExpired() { stop(reason: "timeout") }
    private mutating func stop(reason: String, domain: String? = nil, code: Int? = nil) {
        guard phase != .idle, phase != .finished, phase != .stopping else { return }
        pending = .init(status: "failed", reason: reason, frame: nil, errorDomain: domain, errorCode: code, cleanupCompleted: false)
        phase = .stopping
    }
    mutating func cleanupFailed(domain: String, code: Int) {
        guard phase == .stopping else { return }
        let failure = ComposeCaptureProbeReport(status: "failed", reason: "cleanup_failed", frame: nil, errorDomain: domain, errorCode: code, cleanupCompleted: false)
        pending = failure; report = failure; phase = .finished
    }
    mutating func cleanedUp() {
        guard phase == .stopping, let pending else { return }
        streamOwned = false
        report = .init(status: pending.status, reason: pending.reason, frame: pending.frame,
            errorDomain: pending.errorDomain, errorCode: pending.errorCode, cleanupCompleted: true)
        phase = .finished
    }
}
#endif
