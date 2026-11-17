import Combine
import Foundation
import FiestaBoardKit
import FiestaBoardRender

/// A page's own character grid, from its stored geometry (nil for pages with no
/// fixed grid, e.g. flexible documents).
public struct PageGeometry: Sendable, Equatable {
    public let deviceType: String
    public let rows: Int
    public let cols: Int

    public init?(_ page: Page) {
        switch page.deviceType {
        case "flagship"?: (deviceType, rows, cols) = ("flagship", 6, 22)
        case "note"?: (deviceType, rows, cols) = ("note", 3, 15)
        case "note_array"?:
            deviceType = "note_array"
            rows = 3 * max(1, min(8, page.notesTall ?? 1)); cols = 15 * max(1, min(8, page.notesWide ?? 1))
        case "panel"?:
            guard let r = page.gridRows, let c = page.gridCols, r > 0, c > 0 else { return nil }
            (deviceType, rows, cols) = ("panel", min(r, BoardFrame.maxDimension), min(c, BoardFrame.maxDimension))
        default:
            // single / composite pages without a stored type render as the Flagship default.
            guard page.type == "single" || page.type == "composite" else { return nil }
            (deviceType, rows, cols) = ("flagship", 6, 22)
        }
    }

    /// "Flagship" / "Note" / "Note Array" / "Panel" (web words).
    public var label: String {
        switch deviceType {
        case "note": "Note"
        case "note_array": "Note Array"
        case "panel": "Panel"
        default: "Flagship"
        }
    }

    /// Whether a page of this grid shows on `model` as authored.
    public func fits(_ model: DisplayModel) -> Bool { model.rows == rows && model.cols == cols }
}

/// Cache key: a thumbnail is valid until the page changes (its `revision`, which
/// the server bumps on every save; a content digest when a server reports none)
/// or the display it is drawn for changes.
public struct ThumbnailKey: Hashable, Sendable {
    public let pageID: String
    public let version: String
    public let boardID: String?

    public init(page: Page, boardID: String?) {
        pageID = page.id
        if let revision = page.revision, !revision.isEmpty {
            version = "r:" + revision
        } else {
            var hasher = Hasher()  // per-process; fine for an in-memory cache
            hasher.combine(page.name); hasher.combine(page.type); hasher.combine(page.deviceType)
            hasher.combine(page.template); hasher.combine(page.gridRows); hasher.combine(page.gridCols)
            version = "h:\(hasher.finalize())"
        }
        self.boardID = boardID
    }
}

/// In-memory thumbnail cache (pure; the loader below owns the I/O).
public struct ThumbnailCache: Sendable {
    private var entries: [ThumbnailKey: PagePreview] = [:]
    public init() {}
    public func preview(for key: ThumbnailKey) -> PagePreview? { entries[key] }
    public mutating func store(_ preview: PagePreview, for key: ThumbnailKey) {
        // One entry per page and display: a newer revision replaces the old one.
        entries = entries.filter { $0.key.pageID != key.pageID || $0.key.boardID != key.boardID }
        entries[key] = preview
    }
    public func missing(_ keys: [ThumbnailKey]) -> [ThumbnailKey] { keys.filter { entries[$0] == nil } }
    public var count: Int { entries.count }
}

/// Lazily loads page thumbnails with `POST /pages/preview/batch` for the
/// selected display: rows ask for their page as they appear, requests are
/// coalesced into batches of up to 20, and results are kept until the page's
/// revision or the display changes. Static: nothing here animates.
@MainActor public final class PageThumbnails: ObservableObject {
    @Published public private(set) var cache = ThumbnailCache()
    public static let batchSize = 20
    private let reader: @MainActor () -> (any PagePreviewReading)?
    private let scope: @MainActor () -> String
    private var cacheScope: String
    private var epoch = UUID()
    private var observers = Set<AnyCancellable>()
    private var pending: [String: ThumbnailKey] = [:]
    private var inFlight: Set<ThumbnailKey> = []
    private var failed: Set<ThumbnailKey> = []
    private var flushTask: Task<Void, Never>?

    public init(reader: @escaping @MainActor () -> (any PagePreviewReading)?, scope: @escaping @MainActor () -> String) {
        self.reader = reader; self.scope = scope; cacheScope = scope()
    }
    public convenience init(store: BoardStore, reader: @escaping @MainActor () -> (any PagePreviewReading)?) {
        self.init(reader: reader, scope: { store.connectionLabel })
        store.$connectionLabel.dropFirst().sink { [weak self] _ in self?.invalidate() }.store(in: &observers)
        store.$connecting.dropFirst().filter { $0 }.sink { [weak self] _ in self?.invalidate() }.store(in: &observers)
    }
    /// Called synchronously when the connection/session changes, even at the same URL.
    public func invalidate() {
        epoch = UUID(); flushTask?.cancel(); flushTask = nil
        pending = [:]; inFlight = []; failed = []; cache = ThumbnailCache(); cacheScope = scope()
    }

    public func preview(for page: Page, boardID: String?) -> PagePreview? {
        guard cacheScope == scope() else { return nil }
        return cache.preview(for: ThumbnailKey(page: page, boardID: boardID))
    }

    /// A row appeared: queue its page unless it is cached, loading or failed.
    public func request(_ page: Page, boardID: String?) {
        if cacheScope != scope() { invalidate() }
        let key = ThumbnailKey(page: page, boardID: boardID)
        guard cache.preview(for: key) == nil, !inFlight.contains(key), !failed.contains(key) else { return }
        pending[page.id] = key
        guard flushTask == nil else { return }
        let token = epoch
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled, let self, token == self.epoch, self.scope() == self.cacheScope else { return }
            self.flush()
        }
    }

    /// Forget failures (pull to refresh / reload library).
    public func retryFailures() { failed.removeAll() }

    private func flush() {
        flushTask = nil
        guard cacheScope == scope(), let reader = reader(), !pending.isEmpty else { pending.removeAll(); return }
        let token = epoch
        let keys = Array(pending.values); pending.removeAll()
        let groups = Dictionary(grouping: keys, by: \.boardID)
        for (boardID, group) in groups {
            for start in stride(from: 0, to: group.count, by: Self.batchSize) {
                let chunk = Array(group[start..<min(group.count, start + Self.batchSize)])
                chunk.forEach { inFlight.insert($0) }
                Task { [weak self] in
                    let result = try? await reader.previewBatch(pageIDs: chunk.map(\.pageID), boardID: boardID)
                    guard let self, token == self.epoch, self.scope() == self.cacheScope else { return }
                    for key in chunk {
                        self.inFlight.remove(key)
                        if let preview = result?[key.pageID] { self.cache.store(preview, for: key) }
                        else { self.failed.insert(key) }
                    }
                }
            }
        }
    }
}
