import Foundation

/// Caller-confined, cost-bounded LRU. Costs include keys and container overhead.
/// Explicit eviction results let Finder remove badges belonging to evicted data.
public final class BadgeLRU<Key: Hashable, Value> {
    private final class Entry {
        let key: Key
        var value: Value
        var cost: Int
        var accessed: TimeInterval
        weak var previous: Entry?
        var next: Entry?
        init(_ key: Key, _ value: Value, _ cost: Int, _ now: TimeInterval) {
            self.key = key
            self.value = value
            self.cost = cost
            accessed = now
        }
    }
    public let byteLimit: Int
    public let countLimit: Int
    public private(set) var totalCost = 0
    public var count: Int { entries.count }
    public var keys: [Key] { Array(entries.keys) }
    private var entries: [Key: Entry] = [:]
    private var oldest: Entry?
    private var newest: Entry?

    public init(byteLimit: Int, countLimit: Int) {
        precondition(byteLimit >= 0 && countLimit >= 0)
        self.byteLimit = byteLimit
        self.countLimit = countLimit
    }
    public func peek(_ key: Key) -> Value? { entries[key]?.value }
    public func value(for key: Key, now: TimeInterval) -> Value? {
        guard let entry = entries[key] else { return nil }
        unlink(entry)
        append(entry)
        entry.accessed = now
        return entry.value
    }
    @discardableResult public func insert(_ value: Value, for key: Key, cost: Int, now: TimeInterval) -> [Key]
    {
        var evicted: [Key] = []
        if remove(key) != nil { evicted.append(key) }
        guard cost > 0, cost <= byteLimit, countLimit > 0 else { return evicted }
        while totalCost > byteLimit - cost || entries.count >= countLimit {
            guard let key = oldest?.key else { break }
            _ = remove(key)
            evicted.append(key)
        }
        let entry = Entry(key, value, cost, now)
        entries[key] = entry
        append(entry)
        totalCost += cost
        return evicted
    }
    /// Replace a background snapshot without promoting its recency.
    @discardableResult public func replace(_ value: Value, for key: Key, cost: Int) -> [Key] {
        guard let entry = entries[key] else { return [] }
        guard cost > 0, cost <= byteLimit else {
            _ = remove(key)
            return [key]
        }
        totalCost -= entry.cost
        entry.value = value
        entry.cost = cost
        totalCost += cost
        return trim(to: byteLimit)
    }
    @discardableResult public func remove(_ key: Key) -> Value? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        unlink(entry)
        totalCost -= entry.cost
        return entry.value
    }
    public func expire(before time: TimeInterval) -> [Key] {
        var removed: [Key] = []
        while let entry = oldest, entry.accessed < time {
            removed.append(entry.key)
            _ = remove(entry.key)
        }
        return removed
    }
    public func trim(to cost: Int) -> [Key] {
        var removed: [Key] = []
        while totalCost > max(0, cost), let key = oldest?.key {
            removed.append(key)
            _ = remove(key)
        }
        return removed
    }
    /// Full invariant audit for tests and infrequent diagnostics, not every lookup.
    public var isConsistent: Bool {
        var seen = Set<Key>()
        var cost = 0
        var node = oldest
        var previous: Entry?
        while let current = node {
            guard seen.insert(current.key).inserted, entries[current.key] === current,
                current.previous === previous
            else { return false }
            cost += current.cost
            previous = current
            node = current.next
        }
        return seen.count == entries.count && cost == totalCost && totalCost <= byteLimit
            && entries.count <= countLimit && previous === newest
    }
    private func unlink(_ entry: Entry) {
        if let previous = entry.previous { previous.next = entry.next } else { oldest = entry.next }
        if let next = entry.next { next.previous = entry.previous } else { newest = entry.previous }
        entry.previous = nil
        entry.next = nil
    }
    private func append(_ entry: Entry) {
        entry.previous = newest
        newest?.next = entry
        if oldest == nil { oldest = entry }
        newest = entry
    }
}

public struct BadgeRetry {
    public private(set) var failures = 0
    public private(set) var nextAttempt: TimeInterval = 0
    public init() {}
    public func canAttempt(at now: TimeInterval) -> Bool { now >= nextAttempt }
    public mutating func failed(at now: TimeInterval, jitter: Double = Double.random(in: 1...1.2)) {
        failures = min(failures + 1, 5)
        let delay = failures == 5 ? 300 : pow(2, Double(failures - 1)) * min(1.2, max(1, jitter))
        nextAttempt = now + delay
    }
    public mutating func succeeded() {
        failures = 0
        nextAttempt = 0
    }
}
