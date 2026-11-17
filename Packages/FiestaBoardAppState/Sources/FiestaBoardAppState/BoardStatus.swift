import Combine
import Foundation
import FiestaBoardKit
import FiestaBoardRender

public extension BoardSummaryFields {
    init(_ summary: BoardSummary) {
        self.init(deviceType: summary.deviceType, rows: summary.rows, cols: summary.cols,
                  deviceModel: summary.deviceModel, charset: summary.charset, output: summary.output)
    }
}

public extension BoardFrame {
    /// The frame `/v1/boards/{id}` reports (`characters`, else `text`, plus `layers`).
    init(_ detail: BoardDetail, expected: Bool = false) {
        let codes = expected ? detail.expectedCharacters : detail.characters
        let layers = (detail.layers ?? []).compactMap { layer -> PixelLayer? in
            guard let data = Data(base64Encoded: layer.rgba) else { return nil }
            return PixelLayer(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: data)
        }
        self.init(rows: detail.summary.rows, cols: detail.summary.cols, codes: codes,
                  message: codes == nil ? detail.text : nil, layers: layers)
    }
}

/// The row of facts above the Home board, in web order
/// (`active-page-display.tsx:650-784`, design/board-display-visuals.md §3.1).
public struct NowShowing: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case manual, schedule
        case override(remainingSeconds: Double)
        public var label: String {
            switch self {
            case .manual: "Manual Mode"
            case .schedule: "Schedule Mode"
            case .override(let seconds):
                seconds < 60 ? "Override: <1m remaining" : "Override: \(Int(seconds / 60))m remaining"
            }
        }
    }
    /// Page or "Collection › Member" name; or the gap / none sentence.
    public var name: String
    /// The page the name links to (the editor), when there is one.
    public var pageID: String?
    public var mode: Mode
    public var collection: Bool
    public var silence: Bool
    public var paused: Bool
    public var scheduleGap: Bool

    public static let scheduleGapText = "Schedule gap (no default page set)"
    public static let noPageText = "No page selected"
    public static let deviceSelectingText = "Device selecting…"
}

/// Pure derivation of `NowShowing` from the polled facts. Never shows raw ids,
/// a `source:` label or a cache disclaimer.
public enum NowShowingModel {
    public static let collectionPrefix = "collection:"

    public static func make(board: BoardSummary, detail: BoardDetail?, schedule: ActivePageStatus?,
                            manual: ActivePageStatus?, silence: SilenceStatus?,
                            pageNames: [String: String], collectionNames: [String: String]) -> NowShowing {
        let scheduleMode = schedule?.scheduleEnabled ?? board.scheduleEnabled
        let override = schedule?.temporaryOverride?.active == true ? schedule?.temporaryOverride : nil
        let mode: NowShowing.Mode = override.map { .override(remainingSeconds: $0.remainingSeconds ?? 0) }
            ?? (scheduleMode ? .schedule : .manual)
        let status = scheduleMode || override != nil ? schedule : manual
        let activeID: String? = override?.pageID
            ?? status?.pageID
            ?? (scheduleMode ? detail?.scheduledPageID : detail?.activePageID)
        let resolvedID = override != nil ? override?.pageID : (status?.resolvedPageID ?? detail?.resolvedPageID)
        let silenceActive = silence?.active == true
        func pageName(_ id: String) -> String { pageNames[id] ?? "Untitled page" }

        var result = NowShowing(name: NowShowing.noPageText, pageID: nil, mode: mode, collection: false,
                                silence: silenceActive, paused: board.paused, scheduleGap: false)
        if silenceActive, silence?.mode == "page", let id = silence?.pageID {
            result.name = pageName(id); result.pageID = id
        } else if let activeID, activeID.hasPrefix(collectionPrefix) {
            let uuid = String(activeID.dropFirst(collectionPrefix.count))
            let collection = collectionNames[uuid] ?? collectionNames[activeID] ?? "Collection"
            result.collection = true
            if let resolvedID {
                result.name = collection + " › " + pageName(resolvedID); result.pageID = resolvedID
            } else {
                result.name = collection + " › " + NowShowing.deviceSelectingText
            }
        } else if let activeID {
            result.name = pageName(activeID); result.pageID = activeID
        } else if scheduleMode {
            result.name = NowShowing.scheduleGapText; result.scheduleGap = true
        }
        return result
    }
}

/// Polling cadence (web `use-board.ts`, design/board-display-visuals.md §3.4).
public enum BoardPolling {
    public static let board: TimeInterval = 30
    public static let activePage: TimeInterval = 60
    public static let status: TimeInterval = 15
    public static let postSend: [TimeInterval] = [0.75, 3.5]
    public static let minimumCheck: TimeInterval = 2
    /// Active-page cadence: `resolved_next_check_seconds` (floored at 2 s) while
    /// a rotating collection is active, else 60 s.
    public static func activePageInterval(nextCheck: Double?) -> TimeInterval {
        guard let nextCheck, nextCheck.isFinite, nextCheck > 0 else { return activePage }
        return max(minimumCheck, min(activePage, nextCheck))
    }
}

/// Home's "what's happening" state for the selected board: display models for
/// every board, the now-showing row, and the polls. Reads only; writes stay in
/// `BoardStore.prepare → confirm`.
@MainActor public final class BoardStatus: ObservableObject {
    @Published public private(set) var models: [String: DisplayModel] = [:]
    @Published public private(set) var nowShowing: NowShowing?
    @Published public private(set) var display = BoardDisplaySettings()
    @Published public private(set) var runtime: [String: BoardRuntimeStatus] = [:]
    /// What every *other* board shows now (`/board/current-message`), for
    /// Home's "Other displays" thumbnails. Read on start and every 30 s.
    @Published public private(set) var frames: [String: BoardFrame] = [:]
    /// The selected board's out-of-sync face (B9), from `/board/current-message`.
    @Published public private(set) var outOfSync: OutOfSync?
    private var selectedMessage: CurrentBoardMessage?

    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    private let store: BoardStore
    private let reader: @MainActor () -> (any BoardStatusReading)?
    private let sleep: Sleeper
    private var stored: [String: [String: Any]] = [:]
    private var schedule: ActivePageStatus?
    private var manual: ActivePageStatus?
    private var silence: SilenceStatus?
    private var collectionNames: [String: String] = [:]
    private var tasks: [Task<Void, Never>] = []
    private var postSendTask: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []
    private var wasBusy = false
    private var epoch = UUID()
    private var running = false

    /// Replaces the production post-send action (tests).
    public var onPostSendRefresh: (@MainActor () -> Void)?

    public init(store: BoardStore, reader: @escaping @MainActor () -> (any BoardStatusReading)?,
                sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.store = store; self.reader = reader; self.sleep = sleep
        // Published changes arrive synchronously, before a suspended old read can
        // resume on the main actor. Display IDs are only unique within one hub.
        store.$connectionLabel.dropFirst().sink { [weak self] _ in
            self?.connectionChanged()
        }.store(in: &observers)
        store.$connecting.dropFirst().filter { $0 }.sink { [weak self] _ in
            self?.connectionChanged()
        }.store(in: &observers)
        store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.storeChanged() }
        }.store(in: &observers)
    }

    public func model(for summary: BoardSummary) -> DisplayModel {
        models[summary.id] ?? DisplayModel(summary: BoardSummaryFields(summary), stored: stored[summary.id])
    }

    /// Start (or restart) the polls for the current connection and board.
    public func start() {
        stop()
        running = true
        let token = epoch
        schedule = nil; manual = nil; silence = nil
        rebuildModels(); recompute()
        tasks.append(Task { [weak self] in await self?.loadAppearance(token: token) })
        tasks.append(loop(every: { _ in BoardPolling.status }) { $0.pollStatus() })
        tasks.append(loop(every: { _ in BoardPolling.board }) { $0.pollOtherFrames() })
        tasks.append(loop(every: { _ in BoardPolling.board }) { $0.pollSelectedMessage() })
        tasks.append(loop(every: { $0.activeInterval }) { $0.pollActive() })
        tasks.append(loop(every: { _ in BoardPolling.board }, immediately: false) { status in
            // Never poll a paused board's frame; never while a command is in flight; and
            // never clear a readback barrier — after an unknown outcome only the user's
            // explicit refresh may do that.
            guard status.store.board?.summary.paused != true, status.canAutoRefresh else { return }
            status.store.refresh()
        })
    }

    public func stop() {
        epoch = UUID()
        running = false
        tasks.forEach { $0.cancel() }; tasks = []
        postSendTask?.cancel(); postSendTask = nil
    }

    private func connectionChanged() {
        stop()
        stored = [:]; models = [:]; runtime = [:]; frames = [:]
        schedule = nil; manual = nil; silence = nil; collectionNames = [:]
        selectedMessage = nil; outOfSync = nil; nowShowing = nil
        display = BoardDisplaySettings(); overrideClearFailed = false
        lastBoardID = nil; wasBusy = false
    }

    private func valid(_ token: UUID) -> Bool { token == epoch && !store.connecting }

    /// Re-read the board (+0.75 s and +3.5 s) and its status after a send, so
    /// the tiles flip into the new frame without a manual refresh.
    public func noteSend() {
        postSendTask?.cancel()
        let token = epoch
        postSendTask = Task { [weak self, sleep] in
            var elapsed: TimeInterval = 0
            for mark in BoardPolling.postSend {
                try? await sleep(mark - elapsed); elapsed = mark
                guard !Task.isCancelled, let self, self.valid(token) else { return }
                self.postSendRefresh()
            }
        }
    }

    private func postSendRefresh() {
        if let onPostSendRefresh { onPostSendRefresh(); return }
        if canAutoRefresh { store.refresh() }
        pollActive()
        pollSelectedMessage()
    }

    /// Automatic re-reads are reads only: they must not stand in for the explicit
    /// refresh that a readback barrier (unknown outcome, failed readback) requires.
    var canAutoRefresh: Bool { !store.commandBusy && !store.refreshing && !store.needsReadback }

    private var activeInterval: TimeInterval {
        BoardPolling.activePageInterval(nextCheck: schedule?.resolvedNextCheckSeconds ?? manual?.resolvedNextCheckSeconds)
    }

    private func loop(every interval: @escaping @MainActor (BoardStatus) -> TimeInterval, immediately: Bool = true,
                      _ body: @escaping @MainActor (BoardStatus) -> Void) -> Task<Void, Never> {
        let token = epoch
        return Task { [weak self, sleep] in
            guard !Task.isCancelled, self?.running == true, self?.valid(token) == true else { return }
            if immediately, let self { body(self) }
            while !Task.isCancelled {
                guard let wait = self.map({ interval($0) }) else { return }
                try? await sleep(wait)
                guard !Task.isCancelled, let self, self.running, self.valid(token) else { return }
                body(self)
            }
        }
    }

    private var lastBoardID: String?
    private func storeChanged() {
        guard running, !store.connecting, store.status != nil else { return }
        let busy = store.commandBusy
        if wasBusy && !busy { noteSend() }
        wasBusy = busy
        if store.selectedBoardID != lastBoardID {
            let changed = lastBoardID != nil
            lastBoardID = store.selectedBoardID
            if changed { pollOtherFrames() }
            selectedMessage = nil; outOfSync = nil
            if store.selectedBoardID != nil { pollSelectedMessage() }
            schedule = nil; manual = nil; silence = nil
            if store.selectedBoardID != nil { pollActive() }
        }
        rebuildModels()
        recompute()
    }

    private func rebuildModels() {
        var next: [String: DisplayModel] = [:]
        for board in store.boards { next[board.id] = DisplayModel(summary: BoardSummaryFields(board), stored: stored[board.id]) }
        if next != models { models = next }
    }

    private func recompute() {
        guard let id = store.selectedBoardID, let summary = store.boards.first(where: { $0.id == id }) else {
            if nowShowing != nil { nowShowing = nil }
            return
        }
        let detail = store.board?.summary.id == id ? store.board : nil
        let pageNames = Dictionary(store.pages.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let next = NowShowingModel.make(board: detail?.summary ?? summary, detail: detail, schedule: schedule, manual: manual,
                                        silence: silence, pageNames: pageNames, collectionNames: collectionNames)
        if next != nowShowing { nowShowing = next }
    }

    private func loadAppearance(token: UUID) async {
        guard valid(token), let reader = reader() else { return }
        if let entries = try? await reader.boardSettings() {
            guard valid(token) else { return }
            stored = Dictionary(entries.map { ($0.id, $0.dictionary()) }, uniquingKeysWith: { first, _ in first })
            rebuildModels()
        }
        guard valid(token) else { return }
        if let settings = try? await reader.displaySettings() {
            guard valid(token) else { return }
            display = settings
        }
        guard valid(token) else { return }
        if let names = try? await reader.collectionNames() {
            guard valid(token) else { return }
            collectionNames = names; recompute()
        }
    }

    private func pollStatus() {
        guard let reader = reader() else { return }
        let token = epoch
        Task { [weak self] in
            do {
                let report = try await reader.serviceStatus()
                guard let self, self.valid(token) else { return }
                self.runtime = report.boards
                self.store.recordHubResponse()
            } catch {
                guard let self, self.valid(token) else { return }
                self.store.recordHubReadFailure(error)
            }
        }
    }

    /// Re-read the selected board's current message (after Restore / Dismiss).
    public func pollSelectedMessage() {
        guard let reader = reader(), let id = store.selectedBoardID else { return }
        let token = epoch
        Task { [weak self] in
            guard let message = try? await reader.currentMessage(boardID: id) else { return }
            guard let self, self.valid(token), self.store.selectedBoardID == id else { return }
            self.selectedMessage = message
            self.recomputeOutOfSync()
        }
    }

    private func recomputeOutOfSync() {
        let next = OutOfSync.make(selectedMessage, silenceActive: silence?.active == true)
        if next != outOfSync { outOfSync = next }
    }

    /// Forget the held external frame (kept face → Dismiss). Hidden at once; the
    /// next read brings it back if the server still holds it.
    public func dismissExternalFrame() async {
        guard let id = store.selectedBoardID,
              let writer = reader() as? any ExternalFrameDismissing else { return }
        let token = epoch
        outOfSync = nil
        try? await writer.dismissExternalFrame(boardID: id)
        guard valid(token), store.selectedBoardID == id else { return }
        pollSelectedMessage()
    }

    /// Whether this connection can cancel an override at all (P5, B8).
    public var canClearOverride: Bool { reader() is any TemporaryOverrideClearing }
    /// The last cancel failed (shown beside the badge until the next try).
    @Published public private(set) var overrideClearFailed = false

    /// The ✕ on the override badge (B8): `DELETE /settings/temporary-override`, then the status
    /// and the board are re-read on the post-send schedule. Nothing retries on its own.
    public func clearTemporaryOverride() async {
        guard let writer = reader() as? any TemporaryOverrideClearing else { return }
        let token = epoch
        overrideClearFailed = false
        var failed = false
        do { try await writer.clearTemporaryOverride() } catch { failed = true }
        guard valid(token) else { return }
        overrideClearFailed = failed
        pollActive()
        noteSend()
    }

    private func pollOtherFrames() {
        guard let reader = reader() else { return }
        let token = epoch
        let others = store.boards.filter { $0.id != store.selectedBoardID }
        Task { [weak self] in
            var next: [String: BoardFrame] = [:]
            await withTaskGroup(of: (String, BoardFrame?).self) { group in
                for board in others {
                    group.addTask {
                        guard let message = try? await reader.currentMessage(boardID: board.id) else { return (board.id, nil) }
                        return (board.id, BoardFrame(message, rows: board.rows, cols: board.cols))
                    }
                }
                for await (id, frame) in group { if let frame { next[id] = frame } }
            }
            guard let self, self.valid(token) else { return }
            let merged = self.frames.merging(next) { _, new in new }
            if merged != self.frames { self.frames = merged }
        }
    }

    /// Page name the server says a board shows (`/v1/status` `active_page_id`).
    public func activePageName(for boardID: String) -> String? {
        guard let id = runtime[boardID]?.activePageID else { return nil }
        if id.hasPrefix(NowShowingModel.collectionPrefix) {
            let uuid = String(id.dropFirst(NowShowingModel.collectionPrefix.count))
            return collectionNames[uuid] ?? collectionNames[id] ?? "Collection"
        }
        return store.pages.first { $0.id == id }?.name
    }

    private func pollActive() {
        guard let reader = reader(), let id = store.selectedBoardID else { recompute(); return }
        let token = epoch
        Task { [weak self] in
            async let schedule = try? reader.activeSchedulePage(boardID: id)
            async let manual = try? reader.activePage(boardID: id)
            async let silence = try? reader.silenceStatus(boardID: id)
            let (s, m, q) = await (schedule, manual, silence)
            guard let self, self.valid(token), self.store.selectedBoardID == id else { return }
            self.schedule = s; self.manual = m; self.silence = q
            self.recompute(); self.recomputeOutOfSync()
        }
    }
}
