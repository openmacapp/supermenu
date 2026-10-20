import Foundation
import SuperMenuGit

/// All mutable state is confined to queue. IPC returns cached data immediately;
/// at most one asynchronous discovery/status scan runs across all repositories.
final class GitBadgeService: @unchecked Sendable {
    static let shared = GitBadgeService()
    private final class Repository: @unchecked Sendable {
        let root: URL
        var identity: GitBadgeIdentity?
        var watcher: GitBadgeWatcher?
        var snapshot: GitBadgeSnapshot?
        var generation: UInt64 = 0
        var refreshed: TimeInterval = 0
        var demanded: TimeInterval = 0
        var dirtySince: TimeInterval = 0
        var readyAt: TimeInterval = 0
        var retry = BadgeRetry()
        init(root: URL) { self.root = root }
        var cost: Int { 4096 + root.path.utf8.count * 8 + (snapshot?.cost ?? 0) }
    }
    private struct Discovery {
        let root: URL?
        let expires: TimeInterval
    }
    private struct Client {
        let pid: pid_t
        var seen: TimeInterval
    }
    private let queue = DispatchQueue(label: "SuperMenu.GitBadges", qos: .utility)
    private let repositories = BadgeLRU<String, Repository>(byteLimit: 23 * 1024 * 1024, countLimit: 16)
    private let discovery = BadgeLRU<String, Discovery>(byteLimit: 256 * 1024, countLimit: 256)
    private var clients: [String: Client] = [:]
    private var server: BadgePortServer?
    private var timer: DispatchSourceTimer?
    private var pressure: DispatchSourceMemoryPressure?
    private var scan: Task<Void, Never>?
    private var scanningRoot: String?
    private var enabled = true
    private var mutationCount = 0
    private var bound = false
    private var pressureUntil: TimeInterval = 0
    private var severePressure = false
    private var retainedBudget = 23 * 1024 * 1024
    private var lastHealthCheck: TimeInterval = 0
    private var session = UUID().uuidString
    private var generation: UInt64 = 0
    private var scans = 0
    private var failures = 0
    private var stopped = false
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    struct Diagnostics {
        let repositories: Int
        let bytes: Int
        let failures: Int
        let scans: Int
        let clients: Int
        let running: Bool
    }
    func diagnostics() -> Diagnostics {
        queue.sync {
            Diagnostics(
                repositories: repositories.count, bytes: repositories.totalCost + discovery.totalCost,
                failures: failures, scans: scans, clients: clients.count, running: bound)
        }
    }
    func start(name: String = BadgeTransport.serviceName, enabled: Bool = true) throws {
        self.enabled = enabled
        server = try BadgePortServer(name: name) { [weak self] data, pid in
            guard let self, data.count <= 24 * 1024,
                let request = try? JSONDecoder().decode(BadgeRequest.self, from: data), request.isValid
            else { return nil }
            // Filesystem discovery can stall on an unavailable volume. Keep it
            // off the state queue so expiry, disable and foreground actions work.
            let active = self.queue.sync { self.enabled && !self.stopped && !self.severePressure }
            var roots: [String: URL] = [:]
            if active {
                for path in request.paths {
                    let url = URL(fileURLWithPath: path).standardizedFileURL
                    roots[path] = self.rootFor(url, now: Self.now)
                }
            }
            return self.queue.sync {
                let reply = self.answer(request, roots: roots, pid: pid)
                guard let data = try? JSONEncoder().encode(reply), data.count <= 24 * 1024 else { return nil }
                return data
            }
        }
        queue.sync { bound = true }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: queue)
        pressure.setEventHandler { [weak self, weak pressure] in
            guard let self, let pressure else { return }
            self.applyMemoryPressure(
                critical: pressure.data.contains(.critical), normal: pressure.data.contains(.normal))
        }
        self.pressure = pressure
        pressure.resume()
    }
    func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            if !value { self.reset() }
        }
    }
    func invalidateAll() { queue.async { self.reset() } }
    func beginMutation() async {
        let pending: Task<Void, Never>? = await withCheckedContinuation { continuation in
            queue.async {
                self.mutationCount += 1
                self.reset()
                continuation.resume(returning: self.scan)
            }
        }
        await pending?.value
    }
    func endMutation() {
        queue.async {
            self.mutationCount = max(0, self.mutationCount - 1)
            self.reset()
        }
    }
    func stop() {
        // Stop accepting requests before draining state; never wait on queue while
        // a handler might need it to finish.
        server?.stop()
        server = nil
        queue.sync {
            stopped = true
            bound = false
            timer?.cancel()
            timer = nil
            pressure?.cancel()
            pressure = nil
            reset()
        }
    }
    private func reset() {
        generation &+= 1
        scan?.cancel()
        for key in repositories.keys { repositories.peek(key)?.watcher?.stop() }
        _ = repositories.trim(to: 0)
        _ = discovery.trim(to: 0)
        clients.removeAll()
    }
    private func answer(_ request: BadgeRequest, roots: [String: URL], pid: pid_t) -> BadgeReply {
        let now = Self.now
        clients = clients.filter { now - $0.value.seen < 30 }
        let key = "\(pid):" + request.client
        if request.paths.isEmpty { clients.removeValue(forKey: key) }
        guard !stopped, enabled, mutationCount == 0, !severePressure,
            clients[key] != nil || clients.count < 8
        else { return reply([:], now: now) }
        if !request.paths.isEmpty { clients[key] = Client(pid: pid, seen: now) }
        for raw in request.paths {
            guard let root = roots[raw] else { continue }
            let key = root.path
            let repository: Repository
            if let existing = repositories.peek(key) {
                repository = existing
                if request.touch { _ = repositories.value(for: key, now: now) }
            } else {
                repository = Repository(root: root)
                var evicted = repositories.trim(to: retainedBudget - repository.cost)
                evicted += repositories.insert(repository, for: key, cost: repository.cost, now: now)
                if !evicted.isEmpty { generation &+= 1 }
                if let scanningRoot, evicted.contains(scanningRoot) { scan?.cancel() }
            }
            repository.demanded = now
            if now - repository.refreshed >= 30, repository.snapshot != nil { invalidate(repository) }
        }
        // Admission may evict an earlier repository from this batch. Build the
        // reply only from the final retained set, with its current generation.
        var states: [String: String] = [:]
        var expires = now + 30
        for raw in request.paths {
            guard let root = roots[raw], let repository = repositories.peek(root.path) else { continue }
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            if let snapshot = repository.snapshot,
                let relative = PathCommands.relativePath(from: root, to: url),
                let state = snapshot.states[relative]
            {
                states[raw] = state
                expires = min(expires, repository.refreshed + 30)
            }
        }
        schedule()
        return BadgeReply(session: session, generation: generation, expires: expires, states: states)
    }
    private func reply(_ states: [String: String], now: TimeInterval) -> BadgeReply {
        BadgeReply(session: session, generation: generation, expires: now + 30, states: states)
    }
    private func rootFor(_ url: URL, now: TimeInterval) -> URL? {
        // Cache per containing directory; a directory may itself be a nested repo.
        let attributes = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let directory =
            attributes?.isDirectory == true && attributes?.isSymbolicLink != true
            ? url : url.deletingLastPathComponent()
        if let hit = queue.sync(execute: { discovery.value(for: directory.path, now: now) }),
            now < hit.expires
        {
            return hit.root
        }
        let version = queue.sync { generation }
        let root = PathCommands.gitRoot(containing: directory)?.standardizedFileURL.resolvingSymlinksInPath()
        queue.sync {
            // Discovery may complete after disable, pressure, or invalidation.
            guard enabled, !stopped, !severePressure, mutationCount == 0, generation == version else {
                return
            }
            _ = discovery.insert(
                Discovery(root: root, expires: now + 30), for: directory.path,
                cost: 512 + directory.path.utf8.count * 8 + (root?.path.utf8.count ?? 0) * 4, now: now)
        }
        return root
    }
    private func invalidate(_ repository: Repository) {
        let now = Self.now
        repository.generation &+= 1
        generation &+= 1
        repository.snapshot = nil
        repository.refreshed = 0
        if repository.retry.failures > 0 { repository.retry.succeeded() }
        if repository.dirtySince == 0 { repository.dirtySince = now }
        repository.readyAt = min(now + 0.3, repository.dirtySince + 2)
        _ = discovery.trim(to: 0)
        // Invalidated data releases its accounting immediately.
        _ = repositories.replace(repository, for: repository.root.path, cost: repository.cost)
        if scanningRoot == repository.root.path { scan?.cancel() }
    }
    private func schedule() {
        let now = Self.now
        guard !stopped, enabled, mutationCount == 0, !severePressure, scan == nil else { return }
        guard
            let key = repositories.keys.filter({ key in
                guard let repository = repositories.peek(key) else { return false }
                return repository.snapshot == nil && now - repository.demanded < 30
                    && repository.readyAt <= now && repository.retry.canAttempt(at: now)
            }).max(by: { (repositories.peek($0)?.demanded ?? 0) < (repositories.peek($1)?.demanded ?? 0) }),
            let repository = repositories.peek(key)
        else { return }
        let version = repository.generation
        scanningRoot = key
        scans = min(scans + 1, Int.max - 1)
        scan = Task { [weak self, repository] in
            // Keep this one admitted repository alive until completion always
            // clears the in-flight slot, even if it was evicted before starting.
            guard let self else { return }
            let result: Result<(GitBadgeIdentity, GitBadgeSnapshot), Error>
            do {
                let identity = try await GitBadgeStatus.discover(at: repository.root)
                // Install the stream before scanning, to invalidate events racing the read.
                try self.queue.sync {
                    guard self.repositories.peek(key) === repository, repository.generation == version else {
                        throw CancellationError()
                    }
                    if repository.identity != identity {
                        repository.watcher?.stop()
                        repository.watcher = try GitBadgeWatcher(
                            paths: Array(
                                Set([
                                    identity.root.path, identity.gitDirectory.path,
                                    identity.commonDirectory.path,
                                ])), queue: self.queue
                        ) { [weak self, weak repository] in
                            guard let self, let repository, self.repositories.peek(key) === repository else {
                                return
                            }
                            self.invalidate(repository)
                        }
                        repository.identity = identity
                    }
                }
                result = .success((identity, try await GitBadgeStatus.read(identity)))
            } catch { result = .failure(error) }
            self.queue.async {
                self.scan = nil
                self.scanningRoot = nil
                guard self.repositories.peek(key) === repository, repository.generation == version else {
                    self.schedule()
                    return
                }
                switch result {
                case .success((_, let snapshot)):
                    repository.snapshot = snapshot
                    repository.refreshed = Self.now
                    repository.dirtySince = 0
                    repository.retry.succeeded()
                    var evicted = self.repositories.replace(repository, for: key, cost: repository.cost)
                    evicted += self.repositories.trim(to: self.retainedBudget)
                    // Replacing this repository is not an invalidation of other data.
                    if evicted.contains(where: { $0 != key }) { self.generation &+= 1 }
                case .failure(let error):
                    if !(error is CancellationError) {
                        self.failures = min(self.failures + 1, Int.max - 1)
                        repository.retry.failed(at: Self.now)
                        if let failure = error as? GitBadgeFailure,
                            failure == .overBudget || failure == .malformed
                        {
                            repository.readyAt = Self.now + 300
                        }
                    }
                }
                self.schedule()
            }
        }
    }
    private func tick() {
        let now = Self.now
        for key in repositories.keys {
            guard let repository = repositories.peek(key) else { continue }
            if now - repository.demanded > 300 {
                repository.watcher?.stop()
                _ = repositories.remove(key)
                generation &+= 1
            } else if repository.snapshot != nil && now - repository.refreshed >= 30 {
                invalidate(repository)
            }
        }
        _ = discovery.expire(before: now - 30)
        clients = clients.filter { now - $0.value.seen < 30 }
        if pressureUntil > 0 && now >= pressureUntil {
            pressureUntil = 0
            retainedBudget = 23 * 1024 * 1024
        }
        if now - lastHealthCheck >= 30 {
            lastHealthCheck = now
            if !repositories.isConsistent || !discovery.isConsistent { reset() }
        }
        schedule()
    }
    func applyMemoryPressure(critical: Bool, normal: Bool) {
        queue.async {
            if normal {
                self.severePressure = false
                self.pressureUntil = Self.now + 30
                return
            }
            self.severePressure = critical
            self.pressureUntil = 0
            self.retainedBudget = 23 * 1024 * 1024 / 2
            self.scan?.cancel()
            self.generation &+= 1
            if critical {
                self.reset()
            } else {
                _ = self.repositories.trim(to: self.retainedBudget)
                _ = self.discovery.trim(to: 0)
            }
            // Critical pressure remains paused until an actual normal event.
        }
    }
}
