import CoreServices
import Foundation

/// One stream per retained repository, including linked-worktree metadata.
/// Any event invalidates the whole bounded snapshot; dropped events therefore
/// follow the same full-refresh path and cannot leave partial aggregates behind.
final class GitBadgeWatcher {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void
    init(paths: [String], queue: DispatchQueue, changed: @escaping () -> Void) throws {
        self.changed = changed
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    Unmanaged<GitBadgeWatcher>.fromOpaque(info).takeUnretainedValue().changed()
                }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
            )
        else {
            throw BadgeTransportError.unavailable
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stop()
            throw BadgeTransportError.unavailable
        }
    }
    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
    deinit { stop() }
}
