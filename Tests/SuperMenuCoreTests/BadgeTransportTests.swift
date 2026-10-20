import XCTest

@testable import SuperMenuCore

final class BadgeTransportTests: XCTestCase {
    func testTwoClientsExchangeBoundedMessagesAndServerCanRestart() throws {
        let name = "org.example.badges." + UUID().uuidString
        var server: BadgePortServer? = try BadgePortServer(name: name) { data, pid in
            XCTAssertEqual(pid, getpid())
            return data
        }
        for value in ["first", "second"] {
            let data = Data(value.utf8)
            XCTAssertEqual(try BadgeTransport.request(data, name: name), data)
        }
        server?.stop()
        server = nil
        XCTAssertThrowsError(try BadgeTransport.request(Data(), name: name, timeout: 0.05))
        server = try BadgePortServer(name: name) { _, _ in Data("new session".utf8) }
        XCTAssertEqual(try BadgeTransport.request(Data(), name: name), Data("new session".utf8))
        server?.stop()
    }

    func testOversizedMessagesAndMissingServiceAreRejected() throws {
        XCTAssertThrowsError(
            try BadgeTransport.request(Data(repeating: 0, count: 128 * 1024), name: "org.example.absent"))
        XCTAssertThrowsError(
            try BadgeTransport.request(Data(), name: "org.example." + UUID().uuidString, timeout: 0.01))
    }

    func testOversizedReplyDoesNotBreakNextRequest() throws {
        let server = try BadgePortServer(name: "org.example." + UUID().uuidString) { data, _ in
            data.isEmpty ? Data(repeating: 0, count: 128 * 1024) : data
        }
        defer { server.stop() }
        XCTAssertThrowsError(try BadgeTransport.request(Data(), name: server.name, timeout: 0.03))
        let data = Data("recovered".utf8)
        XCTAssertEqual(try BadgeTransport.request(data, name: server.name), data)
    }

    func testSlowServerTimesOutWithoutWaitingForHandler() throws {
        let server = try BadgePortServer(name: "org.example." + UUID().uuidString) { _, _ in
            Thread.sleep(forTimeInterval: 0.3)
            return Data()
        }
        defer { server.stop() }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try BadgeTransport.request(Data(), name: server.name, timeout: 0.03))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.25)
    }
}
