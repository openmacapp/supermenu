import AppKit
import FinderSync
import OSLog

/// Finder's main thread only touches this small projection. All Mach waits run
/// on one utility queue, with one request in flight and no queued snapshots.
final class FinderBadges {
    private let logger = Logger(subsystem: "com.supermenu.badges", category: "finder")
    private var lastDiagnostic: TimeInterval = 0
    private var requests = 0
    private let projection = BadgeProjection()
    private let worker = DispatchQueue(label: "SuperMenu.BadgeClient", qos: .utility)
    private let client = UUID().uuidString
    private var timer: Timer?
    private var pressure: DispatchSourceMemoryPressure?
    private var wakeObserver: NSObjectProtocol?
    private var inFlight = false
    private var cursor = 0
    private var touch = false
    private var epoch: UInt64 = 0
    private var retry = BadgeRetry()
    private var observed = Set<URL>()
    private var lastRequest: TimeInterval = 0
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init() {
        let l10n = L10n(language: ConfigStore.load(from: ConfigStore.defaultURL()).language)
        var registered = 0
        for (state, symbol, color) in [
            ("modified", "pencil.circle.fill", NSColor.systemOrange),
            ("untracked", "plus.circle.fill", .systemBlue),
            ("conflict", "exclamationmark.circle.fill", .systemRed),
        ] {
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, color])
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            {
                FIFinderSyncController.default().setBadgeImage(
                    image, label: l10n.text("badges." + state), forBadgeIdentifier: state)
                registered += 1
            }
        }
        logger.info("Registered badge images: \(registered)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            self?.clear()
            self?.epoch &+= 1
        }
        self.pressure = pressure
        pressure.resume()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.projection.clearStates()
            self?.retry.succeeded()
            self?.epoch &+= 1
        }
    }
    func begin(_ url: URL) {
        guard !observed.contains(url), url.path.utf8.count <= 4096 else { return }
        let retainedCost = observed.reduce(0) { $0 + 512 + $1.path.utf8.count * 4 }
        let addedCost = 512 + url.path.utf8.count * 4
        if observed.count < 64 && retainedCost + addedCost <= 64 * 1024 {
            observed.insert(url)
        }
    }
    func end(_ url: URL) {
        observed.remove(url)
        for path in projection.paths
        where !observed.contains(where: {
            PathCommands.relativePath(from: $0, to: URL(fileURLWithPath: path)) != nil
        }) {
            projection.remove(path)
            set(nil, path: path)
        }
        epoch &+= 1
        cursor = 0
    }
    func request(_ url: URL) {
        requests = min(requests + 1, Int.max - 1)
        let path = url.standardizedFileURL.path
        let now = Self.now
        for evicted in projection.track(path, now: now) { set(nil, path: evicted) }
        touch = true
        lastRequest = now
        let identifier = projection.state(for: path, now: now) ?? ""
        set(identifier, path: path)
        projection.markDisplayed(path, identifier: identifier)
    }
    private func set(_ state: String?, path: String) {
        FIFinderSyncController.default().setBadgeIdentifier(state ?? "", for: URL(fileURLWithPath: path))
    }
    private func clear() {
        for path in projection.removeAll() { set(nil, path: path) }
    }
    private func poll() {
        let now = Self.now
        if now - lastDiagnostic >= 30 {
            lastDiagnostic = now
            logger.info(
                "Badge health: requests=\(self.requests) observed=\(self.observed.count) entries=\(self.projection.paths.count) failures=\(self.retry.failures)"
            )
        }
        // Expiry is checked even during timeout/backoff; old badges never depend
        // on a successful host reply to disappear.
        for update in projection.updates(now: now) { set(update.identifier, path: update.path) }
        if observed.isEmpty && now - lastRequest > 30 { clear() }
        guard !inFlight, retry.canAttempt(at: now) else { return }
        let paths = projection.paths.sorted()
        guard !paths.isEmpty else { return }
        if cursor >= paths.count { cursor = 0 }
        var batch: [String] = []
        var bytes = 0
        for path in paths[cursor...] {
            guard batch.count < 128, bytes + path.utf8.count <= 16 * 1024 else { break }
            batch.append(path)
            bytes += path.utf8.count
        }
        guard !batch.isEmpty else { return }
        cursor += batch.count
        let request = BadgeRequest(client: client, paths: batch, touch: touch)
        touch = false
        guard let data = try? JSONEncoder().encode(request), data.count <= 24 * 1024 else { return }
        inFlight = true
        let version = epoch
        worker.async { [weak self] in
            let reply = try? BadgeTransport.request(data)
            let decoded = reply.flatMap {
                $0.count <= 24 * 1024 ? try? JSONDecoder().decode(BadgeReply.self, from: $0) : nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard self.epoch == version else { return }
                if let decoded, self.projection.apply(decoded, requested: batch, now: Self.now) {
                    self.retry.succeeded()
                } else {
                    self.projection.clearStates()
                    self.retry.failed(at: Self.now)
                }
                for update in self.projection.updates(now: Self.now) {
                    self.set(update.identifier, path: update.path)
                }
            }
        }
    }
    deinit {
        timer?.invalidate()
        pressure?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
