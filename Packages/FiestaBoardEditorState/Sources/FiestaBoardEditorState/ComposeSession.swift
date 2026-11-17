import Foundation
import Combine
import FiestaBoardKit
import FiestaBoardDocuments

/// Verified persistent identity and the current connection are separate authorities.
public struct ComposeScope: Equatable, Sendable {
    public let identity: ComposeBufferIdentity
    public let connectionID: UUID
    public let target: BoardTarget
    public let rows: Int
    public let cols: Int
    public init(identity: ComposeBufferIdentity, connectionID: UUID, target: BoardTarget, rows: Int, cols: Int) {
        self.identity = identity; self.connectionID = connectionID; self.target = target
        self.rows = rows; self.cols = cols
    }
    fileprivate var valid: Bool {
        identity.deploymentID == target.deployment.description
            && !identity.installationID.isEmpty && !identity.principalID.isEmpty
            && rows > 0 && cols > 0
    }
}
public enum ComposeSilenceChoice: String, Equatable, Sendable { case hold, override }

/// Exact authoring source. In particular, tokens and LED letter case are never projected
/// back from a preview or replaced with a plausible offline value.
public struct ComposeInput: Equatable, Sendable {
    public let text: String
    public let lineMetadata: [ComposeBufferLine]
    public let selection: ComposeBufferSelection
    public let duration: ComposeBufferDuration
    public let silence: ComposeSilenceChoice
    public init(text: String = "", lineMetadata: [ComposeBufferLine] = [],
                selection: ComposeBufferSelection = .init(lowerUTF16: 0, upperUTF16: 0),
                duration: ComposeBufferDuration = .minutes(60), silence: ComposeSilenceChoice = .hold) {
        self.text = text
        self.lineMetadata = lineMetadata.isEmpty ? text.components(separatedBy: "\n").map { _ in .init() } : lineMetadata
        self.selection = selection; self.duration = duration; self.silence = silence
    }
    fileprivate var valid: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 65536,
              lineMetadata.count == text.components(separatedBy: "\n").count,
              lineMetadata.allSatisfy({ ["left", "center", "right"].contains($0.alignment) }),
              selection.lowerUTF16 >= 0, selection.upperUTF16 >= selection.lowerUTF16,
              selection.upperUTF16 <= text.utf16.count else { return false }
        switch duration {
        case .minutes(let value): return (1...480).contains(value)
        case .until(let date): return date.timeIntervalSince1970.isFinite
        case .untilCancel: return true
        }
    }
    fileprivate func durationValid(at now: Date) -> Bool {
        guard now.timeIntervalSince1970.isFinite else { return false }
        if case .until(let end) = duration {
            let remaining = end.timeIntervalSince(now)
            return remaining > 0 && remaining <= 28800
        }
        return true
    }
}
public struct ComposePreviewInput: Sendable {
    public let scope: ComposeScope
    public let input: ComposeInput
    public let revision: UInt64
}
public struct PreparedComposeIntent: Sendable {
    public let id: UUID
    public let scope: ComposeScope
    public let input: ComposeInput
    public let revision: UInt64
    public let preparedAt: Date
}

/// Compose-only ownership. The retained editor pipeline has different stale-frame
/// semantics and remains unchanged. The injected renderer is a read, never a send.
@MainActor public final class ComposeSession: ObservableObject {
    public typealias Sleeper = @MainActor (Duration) async throws -> Void
    public typealias Renderer = @MainActor (ComposePreviewInput) async throws -> TemplatePreviewResult
    @Published public private(set) var scope: ComposeScope
    @Published public private(set) var input: ComposeInput
    @Published public private(set) var preview: TemplatePreviewResult?
    @Published public private(set) var previewIsStale = true
    @Published public private(set) var previewIsUpdating = false
    @Published public private(set) var previewFailure: String?
    @Published public private(set) var online: Bool
    public private(set) var inputToPreviewSeconds: TimeInterval?
    public private(set) var postDebouncePreviewSeconds: TimeInterval?
    private let sleep: Sleeper
    private let render: Renderer
    private let monotonicNow: @MainActor () -> TimeInterval
    private var revision: UInt64 = 0
    private var epoch: UInt64 = 0
    private var closed = false
    private var preparedID: UUID?
    private var debounceTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var readyRevision: UInt64?
    private var lastInputAt: TimeInterval?
    private var readyAt: TimeInterval?

    public init(scope: ComposeScope, input: ComposeInput = .init(), online: Bool = true,
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
                monotonicNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                render: @escaping Renderer) {
        self.scope = scope; self.input = input; self.online = online
        self.sleep = sleep; self.monotonicNow = monotonicNow; self.render = render
    }
    public func update(_ input: ComposeInput) {
        guard !closed else { return }
        preparedID = nil; revision &+= 1; self.input = input
        lastInputAt = monotonicNow(); inputToPreviewSeconds = nil; postDebouncePreviewSeconds = nil
        previewIsStale = true; previewFailure = nil
        schedulePreview()
    }
    public func changeScope(_ scope: ComposeScope) {
        guard !closed, scope != self.scope else { return }
        let identityChanged = scope.identity != self.scope.identity
        invalidateRequests()
        if identityChanged { revision &+= 1; input = .init() }
        // Clear before publishing the new scope: a former display's frame must
        // never be presented under the new display or authenticated identity.
        preview = nil; self.scope = scope
        lastInputAt = monotonicNow()
        schedulePreview()
    }
    public func setOnline(_ online: Bool) {
        guard !closed, self.online != online else { return }
        invalidateRequests(); self.online = online
        // No automatic replay on reconnect. Input, formatting and last-known
        // evidence remain available; retry or new input may request a fresh read.
    }
    public func close() {
        guard !closed else { return }
        invalidateRequests(); closed = true
        renderTask?.cancel()
    }
    public func retryPreview() {
        guard !closed, online, scope.valid, input.valid, previewIsStale || previewFailure != nil else { return }
        debounceTask?.cancel(); debounceTask = nil
        lastInputAt = monotonicNow(); readyAt = lastInputAt; readyRevision = revision
        previewFailure = nil
        requestReadyPreview()
    }
    public func prepare(now: Date = Date()) -> PreparedComposeIntent? {
        guard !closed, online, scope.valid, input.valid, input.durationValid(at: now) else { return nil }
        let id = UUID(); preparedID = id
        return PreparedComposeIntent(id: id, scope: scope, input: input, revision: revision, preparedAt: now)
    }
    public func consume(_ action: PreparedComposeIntent, now: Date = Date()) -> PreparedComposeIntent? {
        guard !closed, online, action.id == preparedID, action.scope == scope,
              action.revision == revision, input.valid, action.input.durationValid(at: now) else { return nil }
        preparedID = nil
        return action
    }
    private func invalidateRequests() {
        preparedID = nil; epoch &+= 1; readyRevision = nil; readyAt = nil
        debounceTask?.cancel(); debounceTask = nil
        previewIsStale = true; previewFailure = nil
        inputToPreviewSeconds = nil; postDebouncePreviewSeconds = nil
    }
    private func schedulePreview() {
        debounceTask?.cancel(); debounceTask = nil; readyRevision = nil; readyAt = nil
        guard !closed, online, scope.valid, input.valid else { return }
        let capturedRevision = revision, capturedEpoch = epoch, sleep = self.sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(.milliseconds(250)) } catch { return }
            guard !Task.isCancelled, let self, !closed, online,
                  capturedRevision == revision, capturedEpoch == epoch else { return }
            debounceTask = nil; readyRevision = capturedRevision; readyAt = monotonicNow()
            requestReadyPreview()
        }
    }
    private func requestReadyPreview() {
        guard renderTask == nil, readyRevision == revision, !closed, online, scope.valid, input.valid else { return }
        readyRevision = nil
        let captured = ComposePreviewInput(scope: scope, input: input, revision: revision)
        let capturedEpoch = epoch, inputAt = lastInputAt, debounceAt = readyAt, render = self.render
        previewIsUpdating = true
        renderTask = Task { [weak self] in
            let outcome: Result<TemplatePreviewResult, any Error>
            do { outcome = .success(try await render(captured)) } catch { outcome = .failure(error) }
            guard let self else { return }
            renderTask = nil
            if !closed, online, capturedEpoch == epoch, captured.revision == revision, captured.scope == scope {
                switch outcome {
                case .success(let result):
                    preview = result; previewIsStale = false; previewFailure = nil
                    let end = monotonicNow()
                    inputToPreviewSeconds = inputAt.map { max(0, end - $0) }
                    postDebouncePreviewSeconds = debounceAt.map { max(0, end - $0) }
                case .failure(let error):
                    if !(error is CancellationError) { previewFailure = "Preview unavailable" }
                    previewIsStale = true
                }
            }
            // A newer idle burst replaces the pending burst, never the in-flight
            // request. Its full250ms idle period must have elapsed before dispatch.
            requestReadyPreview()
            if renderTask == nil { previewIsUpdating = false }
        }
    }
}
