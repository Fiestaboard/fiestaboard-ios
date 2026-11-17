import XCTest
@testable import FiestaBoardRender

final class TokenBridgeTests: XCTestCase {
    func testEveryStructuralBoardCodeUsesGeneratedPigment() throws {
        let names = ["red", "orange", "yellow", "green", "blue", "violet", "white", "black", "black"]
        for (offset, name) in names.enumerated() {
            let color = try XCTUnwrap(BoardColor(code: offset + 63))
            XCTAssertEqual(color.rawValue, name)
            XCTAssertEqual(color.token, FiestaTokenValues.Board.all[name])
            XCTAssertEqual(color.hex, FiestaTokenValues.Board.all[name]?.hex)
            XCTAssertEqual(BoardTables.cell(forCode: offset + 63, code62: .degree), .color(color))
        }
        XCTAssertNil(BoardColor(code: 62))
        XCTAssertNil(BoardColor(code: 72))
    }

    func testOpaqueBoardBlackAndFixedTouchTargets() {
        XCTAssertEqual(BoardColor.black.hex, "#1a1a1a")
        XCTAssertEqual(BoardColor.black.token.alpha, 1)
        XCTAssertEqual(PlatformIOSValues.Touch.buttonHeight, 44)
        XCTAssertEqual(PlatformIOSValues.Touch.iconButtonSize, 44)
        XCTAssertEqual(PlatformIOSValues.Touch.minTarget, 44)
        XCTAssertEqual(PlatformIOSValues.Light.all.count, 20)
        XCTAssertEqual(PlatformIOSValues.Dark.all.count, 20)
    }
}
