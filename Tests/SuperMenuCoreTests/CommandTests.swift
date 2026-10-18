import XCTest
@testable import SuperMenuCore

final class CommandTests: XCTestCase {
    func testBuiltinTokensRoundTrip() {
        for command in BuiltinCommand.allCases {
            let token = MenuCommand.builtin(command).token
            XCTAssertEqual(MenuCommand.parse(token), .builtin(command))
        }
    }

    func testOpenAndSendTokensRoundTrip() {
        let open = MenuCommand.openApp(bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"])
        XCTAssertEqual(MenuCommand.parse(open.token), open)
        XCTAssertEqual(MenuCommand.parse("new:swift"), .newFile(templateID: "swift"))
        XCTAssertEqual(MenuCommand.parse("send-copy:desktop"), .sendCopy(targetID: "desktop"))
        XCTAssertEqual(MenuCommand.parse("send-move:downloads"), .sendMove(targetID: "downloads"))
        XCTAssertNil(MenuCommand.parse("nope"))
        XCTAssertNil(MenuCommand.parse("builtin:missing"))
    }
}
