import Darwin
import Foundation
import GitKit

struct GitReadResult: Sendable {
    let data: Data
    let truncated: Bool
}

/// Inspection reads need cancellation, deadlines and output bounds that the
/// buffered GitKit runner does not expose. Mutation commands still use GitKit.
final class BoundedGitRead: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var stopped = false
    private var timedOut = false

    private func stop(timeout: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        timedOut = timeout
        if process.isRunning {
            let pid = process.processIdentifier
            // Foundation gives child processes their own process group on macOS.
            // Verify ownership before stopping read-only Git and its helpers;
            // SIGTERM alone can leave a helper holding stdout indefinitely.
            let target = getpgid(pid) == pid ? -pid : pid
            kill(target, SIGKILL)
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func checkDeadline() throws {
        lock.lock()
        defer { lock.unlock() }
        if timedOut { throw WorkspaceFailure("git.error.diffTimeout") }
    }

    private func start(root: URL, arguments: [String], output: Pipe) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else {
            if timedOut { throw WorkspaceFailure("git.error.diffTimeout") }
            throw CancellationError()
        }
        process.executableURL = URL(fileURLWithPath: GitRunner.defaultGitPath)
        process.currentDirectoryURL = root
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func read(root: URL, arguments: [String], byteLimit: Int,
                     lineLimit: Int = .max, timeout: TimeInterval = 10) async throws -> GitReadResult {
        let reader = BoundedGitRead()
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                let result: GitReadResult = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let pipe = Pipe()
                        let deadline = DispatchWorkItem { reader.stop(timeout: true) }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                        defer {
                            deadline.cancel()
                            try? pipe.fileHandleForReading.close()
                            try? pipe.fileHandleForWriting.close()
                        }
                        do {
                            try reader.start(root: root, arguments: arguments, output: pipe)
                            var data = Data()
                            var truncated = false
                            var lines = 0
                            let descriptor = pipe.fileHandleForReading.fileDescriptor
                            let flags = fcntl(descriptor, F_GETFL)
                            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                                throw WorkspaceFailure("git.error.diff")
                            }
                            var bytes = [UInt8](repeating: 0, count: 16 * 1024)
                            while !reader.isStopped {
                                var readiness = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                                let ready = poll(&readiness, 1, 100)
                                if ready == 0 || (ready < 0 && errno == EINTR) { continue }
                                guard ready > 0 else { throw WorkspaceFailure("git.error.diff") }
                                let count = Darwin.read(descriptor, &bytes, bytes.count)
                                if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                                guard count >= 0 else { throw WorkspaceFailure("git.error.diff") }
                                if count == 0 { break }
                                let chunk = Data(bytes.prefix(count))
                                var accepted = chunk.prefix(max(0, byteLimit - data.count))
                                if lineLimit != .max {
                                    for index in accepted.indices where accepted[index] == 10 {
                                        lines += 1
                                        if lines > lineLimit {
                                            accepted = accepted.prefix(upTo: index)
                                            break
                                        }
                                    }
                                }
                                data.append(accepted)
                                if accepted.count < chunk.count {
                                    truncated = true
                                    reader.stop()
                                    break
                                }
                            }
                            try? pipe.fileHandleForReading.close()
                            reader.process.waitUntilExit()
                            try reader.checkDeadline()
                            guard truncated || reader.process.terminationStatus == 0 else {
                                throw WorkspaceFailure("git.error.diff")
                            }
                            continuation.resume(returning: GitReadResult(data: data, truncated: truncated))
                        } catch {
                            reader.stop()
                            try? pipe.fileHandleForReading.close()
                            if reader.process.isRunning { reader.process.waitUntilExit() }
                            continuation.resume(throwing: error)
                        }
                    }
                }
                try Task.checkCancellation()
                return result
            } catch {
                // A terminated Git process must still surface task cancellation,
                // rather than briefly replacing the next selection with an error.
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { reader.stop() }
    }
}
