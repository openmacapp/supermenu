import Foundation

public struct BadgeRequest: Codable {
    public let client: String
    public let paths: [String]
    public let touch: Bool
    public init(client: String, paths: [String], touch: Bool) {
        self.client = client
        self.paths = paths
        self.touch = touch
    }
    public var isValid: Bool {
        UUID(uuidString: client) != nil && paths.count <= 128
            && paths.reduce(0, { $0 + $1.utf8.count }) <= 16 * 1024
            && paths.allSatisfy { $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= 4096 }
    }
}

public struct BadgeReply: Codable {
    public let session: String
    public let generation: UInt64
    public let expires: TimeInterval
    public let states: [String: String]
    public init(session: String, generation: UInt64, expires: TimeInterval, states: [String: String]) {
        self.session = session
        self.generation = generation
        self.expires = expires
        self.states = states
    }
}

/// Main-thread confined Finder projection. Metadata/responses have separate
/// headroom within the 1 MiB per-instance allocation budget.
public final class BadgeProjection {
    private final class Value {
        var state: String?
        var expires: TimeInterval = 0
        var displayed: String?
    }
    private let cache = BadgeLRU<String, Value>(byteLimit: 512 * 1024, countLimit: 2_000)
    private var session = ""
    private var generation: UInt64 = 0
    public var paths: [String] { cache.keys }
    public var cost: Int { cache.totalCost }
    public init() {}
    @discardableResult public func track(_ path: String, now: TimeInterval) -> [String] {
        guard path.utf8.count <= 4096 else { return [] }
        if cache.value(for: path, now: now) != nil { return [] }
        return cache.insert(Value(), for: path, cost: 512 + path.utf8.count * 4, now: now)
    }
    public func state(for path: String, now: TimeInterval) -> String? {
        guard let value = cache.peek(path), now < value.expires else { return nil }
        return value.state
    }
    @discardableResult public func apply(_ reply: BadgeReply, requested: [String], now: TimeInterval) -> Bool
    {
        guard reply.expires.isFinite, reply.expires > now, reply.expires <= now + 31,
            reply.states.count <= 128,
            reply.states.values.allSatisfy({ ["modified", "untracked", "conflict"].contains($0) })
        else { return false }
        if session == reply.session && reply.generation < generation { return false }
        if session != reply.session || generation != reply.generation { clearStates() }
        session = reply.session
        generation = reply.generation
        for path in requested {
            // A reply must not resurrect an item evicted while IPC was in flight.
            guard let value = cache.peek(path) else { continue }
            value.state = reply.states[path]
            value.expires = reply.expires
        }
        return true
    }
    public struct Update {
        public let path: String
        public let identifier: String
    }
    public func markDisplayed(_ path: String, identifier: String) { cache.peek(path)?.displayed = identifier }
    public func updates(now: TimeInterval) -> [Update] {
        var updates: [Update] = []
        for path in cache.keys {
            guard let value = cache.peek(path) else { continue }
            let identifier = now < value.expires ? (value.state ?? "") : ""
            if value.displayed != identifier {
                value.displayed = identifier
                updates.append(Update(path: path, identifier: identifier))
            }
        }
        return updates
    }
    public func clearStates() {
        for path in cache.keys {
            cache.peek(path)?.state = nil
            cache.peek(path)?.expires = 0
        }
    }
    public func remove(_ path: String) { _ = cache.remove(path) }
    public func removeAll() -> [String] { cache.trim(to: 0) }
    public func expireIdle(before time: TimeInterval) -> [String] { cache.expire(before: time) }
}
