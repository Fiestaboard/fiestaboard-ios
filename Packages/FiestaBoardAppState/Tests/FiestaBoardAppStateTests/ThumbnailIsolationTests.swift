import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class ThumbnailIsolationTests: XCTestCase {
    func testSamePageAndRevisionCannotReuseAnotherHubsPreview() async throws {
        let page = try makePage()
        var hub = "https://a.test"
        var reader: any PagePreviewReading = PreviewReply(marker: "A")
        let thumbnails = PageThumbnails(reader: { reader }, scope: { hub })
        thumbnails.request(page, boardID: "kitchen")
        await waitFor("A", page: page, in: thumbnails)
        hub = "https://b.test"
        XCTAssertNil(thumbnails.preview(for: page, boardID: "kitchen"))
        reader = PreviewReply(marker: "B")
        thumbnails.request(page, boardID: "kitchen")
        await waitFor("B", page: page, in: thumbnails)
    }
    func testLatePreviewCannotReplaceNewHubOrSurviveConnectionInvalidation() async throws {
        let page = try makePage()
        let gate = PreviewReplyGate()
        var hub = "https://a.test"
        var reader: any PagePreviewReading = PreviewReply(marker: "A", gate: gate)
        let thumbnails = PageThumbnails(reader: { reader }, scope: { hub })
        thumbnails.request(page, boardID: "kitchen")
        await gate.waitUntilStarted()
        hub = "https://b.test"
        thumbnails.invalidate()
        reader = PreviewReply(marker: "B")
        thumbnails.request(page, boardID: "kitchen")
        await waitFor("B", page: page, in: thumbnails)
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(thumbnails.preview(for: page, boardID: "kitchen")?.lines, ["B"])
        thumbnails.invalidate()
        XCTAssertNil(thumbnails.preview(for: page, boardID: "kitchen"), "Same-hub reconnect also invalidates old-session content")
    }
    func testLiveStoreReconnectSynchronouslyInvalidatesThumbnailOwner() async throws {
        let store = BoardStore()
        await store.connect(try FixtureFiestaBoardService()).value
        let page = try makePage()
        let thumbnails = PageThumbnails(store: store, reader: { PreviewReply(marker: "A") })
        thumbnails.request(page, boardID: "kitchen")
        await waitFor("A", page: page, in: thumbnails)
        await store.connect(try FixtureFiestaBoardService()).value
        XCTAssertNil(thumbnails.preview(for: page, boardID: "kitchen"))
    }
    private func makePage() throws -> Page {
        try JSONDecoder().decode(Page.self, from: Data(#"{"id":"same-page","name":"Page","type":"template","device_type":"flagship","template":["HI"],"revision":"same-revision"}"#.utf8))
    }
    private func waitFor(_ marker: String, page: Page, in thumbnails: PageThumbnails) async {
        for _ in 0..<200 {
            if thumbnails.preview(for: page, boardID: "kitchen")?.lines == [marker] { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected current hub preview \(marker)")
    }
}
private struct PreviewReply: PagePreviewReading {
    let marker: String
    var gate: PreviewReplyGate? = nil
    func previewBatch(pageIDs: [String], boardID: String?) async throws -> [String: PagePreview] {
        if let gate { await gate.wait() }
        return Dictionary(uniqueKeysWithValues: pageIDs.map { ($0, PagePreview(pageID: $0, available: true, lines: [marker], displayType: "flagship", cellsJSON: nil, layers: [], error: nil)) })
    }
}
private actor PreviewReplyGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var reply: CheckedContinuation<Void, Never>?
    func wait() async { started = true; startWaiter?.resume(); startWaiter = nil; await withCheckedContinuation { reply = $0 } }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { startWaiter = $0 } } }
    func release() { reply?.resume(); reply = nil }
}
