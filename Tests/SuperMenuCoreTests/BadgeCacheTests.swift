import XCTest

@testable import SuperMenuCore

final class BadgeCacheTests: XCTestCase {
    func testReadsPromoteButBackgroundPeeksDoNotAndCostsAreBounded() {
        let cache = BadgeLRU<String, Int>(byteLimit: 30, countLimit: 3)
        XCTAssertEqual(cache.insert(1, for: "a", cost: 10, now: 0), [])
        _ = cache.insert(2, for: "b", cost: 10, now: 1)
        _ = cache.insert(3, for: "c", cost: 10, now: 2)
        XCTAssertEqual(cache.value(for: "a", now: 3), 1)
        XCTAssertEqual(cache.peek("b"), 2)
        XCTAssertEqual(cache.insert(4, for: "d", cost: 10, now: 4), ["b"])
        XCTAssertEqual(cache.totalCost, 30)
        XCTAssertTrue(cache.isConsistent)
        XCTAssertEqual(cache.insert(5, for: "a", cost: 31, now: 5), ["a"])
        XCTAssertNil(cache.peek("a"))
        XCTAssertLessThanOrEqual(cache.totalCost, 30)
    }

    func testBackgroundReplacementPreservesLRUAndProjectionNeverExceedsBudget() {
        let cache = BadgeLRU<String, Int>(byteLimit: 30, countLimit: 3)
        for (index, key) in ["a", "b", "c"].enumerated() {
            _ = cache.insert(index, for: key, cost: 10, now: Double(index))
        }
        _ = cache.replace(99, for: "a", cost: 10)
        XCTAssertEqual(cache.insert(4, for: "d", cost: 10, now: 4), ["a"])
        let view = BadgeProjection()
        for index in 0..<3000 { view.track("/tmp/item-\(index)", now: Double(index)) }
        XCTAssertLessThanOrEqual(view.paths.count, 2000)
        XCTAssertLessThanOrEqual(view.cost, 512 * 1024)
        XCTAssertNil(view.state(for: "/tmp/item-0", now: 3001))
    }

    func testIdleExpiryAndPressureReleaseAllEntries() {
        let cache = BadgeLRU<String, Int>(byteLimit: 100, countLimit: 2)
        _ = cache.insert(1, for: "a", cost: 40, now: 0)
        _ = cache.insert(2, for: "b", cost: 40, now: 10)
        XCTAssertEqual(cache.expire(before: 5), ["a"])
        XCTAssertEqual(cache.trim(to: 0), ["b"])
        XCTAssertEqual(cache.totalCost, 0)
        XCTAssertEqual(cache.count, 0)
        XCTAssertTrue(cache.isConsistent)
    }

    func testProjectionRejectsOldGenerationsAndExpiredReplies() {
        let view = BadgeProjection()
        view.track("/tmp/a", now: 0)
        XCTAssertTrue(
            view.apply(
                BadgeReply(session: "host", generation: 2, expires: 30, states: ["/tmp/a": "modified"]),
                requested: ["/tmp/a"], now: 1))
        XCTAssertEqual(view.state(for: "/tmp/a", now: 2), "modified")
        XCTAssertFalse(
            view.apply(
                BadgeReply(session: "host", generation: 1, expires: 30, states: ["/tmp/a": "conflict"]),
                requested: ["/tmp/a"], now: 3))
        XCTAssertEqual(view.state(for: "/tmp/a", now: 4), "modified")
        XCTAssertNil(view.state(for: "/tmp/a", now: 31))
        XCTAssertFalse(
            view.apply(
                BadgeReply(session: "host", generation: 3, expires: 5, states: [:]), requested: [], now: 10))
    }

    func testFinderUpdatesOnlyChangedOrExpiredBadges() {
        let view = BadgeProjection()
        view.track("/tmp/file", now: 0)
        _ = view.updates(now: 0)
        XCTAssertTrue(
            view.apply(
                BadgeReply(session: "host", generation: 1, expires: 20, states: ["/tmp/file": "modified"]),
                requested: ["/tmp/file"], now: 1))
        XCTAssertEqual(view.updates(now: 2).map(\.identifier), ["modified"])
        XCTAssertTrue(view.updates(now: 3).isEmpty)
        XCTAssertEqual(view.updates(now: 21).map(\.identifier), [""])
        XCTAssertTrue(view.updates(now: 22).isEmpty)
    }

    func testCachedLookupLatencyWithBoundedProjection() {
        let view = BadgeProjection()
        for index in 0..<2000 { view.track("/tmp/file-\(index)", now: 0) }
        let paths = Array(view.paths.prefix(128))
        let states = Dictionary(uniqueKeysWithValues: paths.map { ($0, "modified") })
        XCTAssertTrue(
            view.apply(
                BadgeReply(session: "host", generation: 1, expires: 30, states: states), requested: paths,
                now: 1))
        var samples: [Double] = []
        for index in 0..<10_000 {
            let start = ContinuousClock.now
            XCTAssertEqual(view.state(for: paths[index % paths.count], now: 2), "modified")
            let duration = start.duration(to: .now).components
            samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
        samples.sort()
        print("BADGE LOOKUP p95=\(samples[9500])ms entries=\(view.paths.count) cost=\(view.cost)")
    }

    func testFiveFailuresPauseThenPermitRecovery() {
        var retry = BadgeRetry()
        for (time, delay) in [(0.0, 1.0), (1, 2), (3, 4), (7, 8), (15, 300)] {
            retry.failed(at: time, jitter: 1)
            XCTAssertFalse(retry.canAttempt(at: time + delay - 0.1))
            XCTAssertTrue(retry.canAttempt(at: time + delay))
        }
        retry.succeeded()
        XCTAssertTrue(retry.canAttempt(at: 0))
        retry.failed(at: 0, jitter: 1.2)
        XCTAssertFalse(retry.canAttempt(at: 1))
        XCTAssertTrue(retry.canAttempt(at: 1.2))
    }
}
