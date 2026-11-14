import Foundation
import Combine
import FiestaBoardKit
import FiestaBoardDocuments

/// What the stage should draw after a render request (PLAN §3.3).
public enum PreviewRender: Sendable {
    /// The server's render of the committed document.
    case server(TemplatePreviewResult)
    /// No request was made (empty document, no display chosen, no render route): the stage
    /// shows the local projection of the editor's rows.
    case local
}

/// Pinned-stage preview pipeline (PLAN §3.3). Input arrives from the editor surface on every
/// keystroke; after `debounce` of idle the typing is committed to the session and one render is
/// requested. While a render is in flight newer input coalesces into exactly one follow-up
/// request. The last good frame is held while stale; a failure keeps it and shows an error;
/// nothing is retried until the next input or an explicit `retry()`.
@MainActor
public final class PreviewPipeline: ObservableObject {
    public struct State: Equatable, Sendable {
        /// Last good server frame (rendered lines). `nil` → draw the local projection.
        public var lines: [String]?
        public var charsetIssues: [TemplateCharsetIssue] = []
        /// Input changed after the frame on screen was requested.
        public var isStale = false
        /// A render request is in flight.
        public var isUpdating = false
        /// The latest request failed; the frame above is held. Cleared by the next input.
        public var failure: String?
        /// Number of completed render requests whose result was adopted (for tests/diagnostics).
        public var adoptedRenders = 0
        #if DEBUG
        /// Monotonic last-input → current preview adoption, excluding test-process AX latency.
        public var inputToPreviewSeconds: TimeInterval?
        #endif
    }
    public typealias Sleeper = @MainActor @Sendable (Duration) async throws -> Void

    @Published public private(set) var state = State()
    public let debounce: Duration
    private let sleep: Sleeper
    private let commit: @MainActor () -> Void
    private let render: @MainActor () async throws -> PreviewRender
    private var debounceTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var pendingRender = false
    /// Advances on every input; a render records the value it started from.
    private var inputGeneration: UInt64 = 0
    #if DEBUG
    var diagnosticNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var lastInputAt: TimeInterval?
    #endif
    /// Advances when the target/geometry changes or the pipeline is cancelled; results requested
    /// under an older target are discarded.
    private var targetGeneration: UInt64 = 0

    public init(debounce: Duration = .milliseconds(250),
                sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
                commit: @escaping @MainActor () -> Void,
                render: @escaping @MainActor () async throws -> PreviewRender) {
        self.debounce = debounce; self.sleep = sleep; self.commit = commit; self.render = render
    }

    /// The editor surface changed (keystroke, paste). Restarts the idle timer.
    public func edited() {
        #if DEBUG
        lastInputAt = diagnosticNow()
        state.inputToPreviewSeconds = nil
        #endif
        inputGeneration &+= 1
        state.isStale = true
        debounceTask?.cancel()
        let sleep = self.sleep, debounce = self.debounce
        debounceTask = Task { [weak self] in
            do { try await sleep(debounce) } catch { return }
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    /// Commit now and render (blur, toolbar action, undo/redo, scene background, close).
    public func flush() {
        debounceTask?.cancel(); debounceTask = nil
        fire()
    }

    /// The display or geometry changed: older replies no longer describe this stage.
    public func targetChanged() {
        #if DEBUG
        lastInputAt = nil
        state.inputToPreviewSeconds = nil
        #endif
        targetGeneration &+= 1
        inputGeneration &+= 1
        state.isStale = true
        state.charsetIssues = []
        flush()
    }

    /// Explicit user retry after a failure ("Preview unavailable · Retry").
    public func retry() {
        guard state.failure != nil else { return }
        requestRender()
    }

    /// Stop timers and discard any reply still in flight (editor closed).
    public func cancel() {
        debounceTask?.cancel(); debounceTask = nil
        targetGeneration &+= 1
        pendingRender = false
    }

    public var hasPendingCommit: Bool { debounceTask != nil }

    private func fire() {
        debounceTask = nil
        commit()
        requestRender()
    }

    private func requestRender() {
        if renderTask != nil { pendingRender = true; return }
        let startedInput = inputGeneration
        let startedTarget = targetGeneration
        state.isUpdating = true
        renderTask = Task { [weak self] in
            guard let self else { return }
            let outcome: Result<PreviewRender, any Error>
            do { outcome = .success(try await self.render()) } catch { outcome = .failure(error) }
            self.finish(outcome, startedInput: startedInput, startedTarget: startedTarget)
        }
    }

    private func finish(_ outcome: Result<PreviewRender, any Error>, startedInput: UInt64, startedTarget: UInt64) {
        renderTask = nil
        if startedTarget == targetGeneration {
            switch outcome {
            case .success(.server(let result)):
                state.lines = result.lines
                state.charsetIssues = result.charsetIssues
                state.failure = nil
                state.adoptedRenders += 1
            case .success(.local):
                state.lines = nil
                state.charsetIssues = []
                state.failure = nil
                state.adoptedRenders += 1
            case .failure(let error):
                if !(error is CancellationError) { state.failure = Self.describe(error) }
            }
            state.isStale = startedInput != inputGeneration
            #if DEBUG
            if case .success = outcome, !state.isStale, let lastInputAt {
                state.inputToPreviewSeconds = diagnosticNow() - lastInputAt
                self.lastInputAt = nil
            }
            #endif
        }
        if pendingRender {
            pendingRender = false
            requestRender()
        } else {
            state.isUpdating = false
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Interim local projection of the editor's rows onto the stage (PLAN §5 day-1 item 3): used
/// until a server render arrives and afterwards as the "no request" path (empty document, no
/// display chosen). Deliberately tiny, like the fixture's toy fallback (§4.4): uppercase on
/// split-flap, `{{color}}` → a colour tile, `{{fill_space…}}` → spaces, any other token → its
/// uppercased inner source; per-row alignment; cut at `cols`. No evaluation of any kind.
public enum LocalStageProjection {
    /// Returns markup lines (colour tiles as `{red}`), one per board row.
    public static func lines(rows: [String], alignment: (Int) -> String, boardRows: Int, cols: Int, uppercase: Bool) -> [String] {
        (0..<max(0, boardRows)).map { index in
            guard index < rows.count else { return "" }
            var cells: [String] = []
            for fragment in TemplateSyntax.fragments(rows[index]) {
                switch fragment.kind {
                case .text:
                    cells += fragment.source.map { uppercase ? String($0).uppercased() : String($0) }
                case .tile:
                    cells.append("{" + fragment.label.lowercased() + "}")
                case .fill:
                    cells.append(" ")
                case .expression, .formula, .span, .icon:
                    let inner = fragment.label.trimmingCharacters(in: .whitespaces)
                    cells += inner.map { uppercase ? String($0).uppercased() : String($0) }
                }
            }
            if cells.count > cols { cells = Array(cells.prefix(cols)) }
            let free = cols - cells.count
            switch alignment(index) {
            case "center": cells = Array(repeating: " ", count: free / 2) + cells
            case "right": cells = Array(repeating: " ", count: free) + cells
            default: break
            }
            return cells.joined()
        }
    }
}

/// Split-flap pages uppercase only what the user types or pastes (PLAN §2.2 lossless rule),
/// never inside a `{{…}}` token, so variable names and filters keep their case.
public enum FlapInputCase {
    /// `openBefore`: the caret sits inside an unclosed `{{` in its row.
    public static func uppercased(_ inserted: String, openBefore: Bool) -> String {
        var open = openBefore
        var result = ""
        let characters = Array(inserted)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "{" && next == "{" { open = true; result += "{{"; index += 2; continue }
            if character == "}" && next == "}" { open = false; result += "}}"; index += 2; continue }
            result += open ? String(character) : String(character).uppercased()
            index += 1
        }
        return result
    }
    /// Whether the text before the caret (within its row) leaves a `{{` unclosed.
    public static func isInsideToken(rowPrefix: String) -> Bool {
        guard let open = rowPrefix.range(of: "{{", options: .backwards) else { return false }
        guard let close = rowPrefix.range(of: "}}", options: .backwards) else { return true }
        return open.lowerBound > close.lowerBound
    }
}
