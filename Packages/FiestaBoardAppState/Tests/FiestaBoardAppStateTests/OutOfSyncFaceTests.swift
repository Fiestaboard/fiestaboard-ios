import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

/// B9: the three faces of the out-of-sync banner, from `/board/current-message`.
final class OutOfSyncFaceTests: XCTestCase {
    private func message(_ json: String) throws -> CurrentBoardMessage {
        try JSONDecoder().decode(CurrentBoardMessage.self, from: Data(json.utf8))
    }

    func testOutOfSyncWhenTheBoardShowsSomethingElse() throws {
        let face = try XCTUnwrap(OutOfSync.make(try message(#"{"characters":[[8,9]],"expected_characters":[[1,2]]}"#), silenceActive: false))
        XCTAssertEqual(face.face, .outOfSync)
        XCTAssertEqual(face.grid, [[8, 9]], "Save keeps what the board shows")
        XCTAssertEqual([face.offersRestore, face.offersSave, face.offersDismiss], [true, true, false])
        XCTAssertEqual(face.title(time: ""), "Another app changed this board")
    }

    func testOverwrittenOffersRestoreOnly() throws {
        let face = try XCTUnwrap(OutOfSync.make(try message(#"{"characters":[[1]],"expected_characters":[[1]],"overwritten_at":"2026-10-31T09:12:00+00:00"}"#), silenceActive: false))
        XCTAssertEqual(face.face, .overwritten)
        XCTAssertEqual([face.offersRestore, face.offersSave, face.offersDismiss], [true, false, false])
        XCTAssertEqual(OutOfSync.displayTime(face.detectedAt, timeZone: TimeZone(identifier: "UTC")!), "9:12 AM")
        XCTAssertTrue(face.detail(time: "9:12 AM").hasPrefix("Detected: 9:12 AM. FiestaBoard can't see"))
    }

    func testKeptOffersSaveAndDismiss() throws {
        let face = try XCTUnwrap(OutOfSync.make(try message(#"{"characters":[[1]],"expected_characters":[[1]],"external_characters":[[5,63]],"external_detected_at":"2026-10-31T09:12:00Z"}"#), silenceActive: false))
        XCTAssertEqual(face.face, .kept)
        XCTAssertEqual(face.grid, [[5, 63]])
        XCTAssertEqual([face.offersRestore, face.offersSave, face.offersDismiss], [false, true, true])
        XCTAssertEqual(face.title(time: "9:12 AM"), "Another app wrote to this board at 9:12 AM")
    }

    func testInSyncSilenceAndLiveFacesWin() throws {
        XCTAssertNil(OutOfSync.make(try message(#"{"characters":[[1]],"expected_characters":[[1]]}"#), silenceActive: false))
        XCTAssertNil(OutOfSync.make(try message(#"{"characters":[[2]],"expected_characters":[[1]]}"#), silenceActive: true), "hidden during silence")
        let both = try message(#"{"characters":[[2]],"expected_characters":[[1]],"external_characters":[[3]]}"#)
        XCTAssertEqual(OutOfSync.make(both, silenceActive: false)?.face, .outOfSync)
        XCTAssertNil(OutOfSync.make(try message(#"{"characters":[[1]],"expected_characters":[[1]],"external_characters":[[1]]}"#), silenceActive: false),
                     "a held frame equal to the page is nothing to offer")
    }

    func testTemplateFromFrame() {
        XCTAssertEqual(BoardTemplate.rows([[8, 9, 0, 63, 62, 0, 0]]), ["HI {{red}}°"])
        XCTAssertEqual(BoardTemplate.rows([[0, 0]]), [""])
    }
}
