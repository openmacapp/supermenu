import Darwin
import Foundation
import GitKit

struct GitMutationResult: Sendable {
    let started: Bool
    let exitCode: Int32?
    let signalled: Bool
    let stdout: Data
    let stderr: Data
    let stdoutTruncated: Bool
    let stderrTruncated: Bool
}

/// A write must finish even when its output exceeds the display budget or the
/// awaiting UI task is cancelled. Unlike BoundedGitRead, this never kills Git.
enum BoundedGitMutation {
    private final class Capture: @unchecked Sendable {
        // One reader owns each instance; DispatchGroup.wait synchronizes access.
        var data = Data()
        var truncated = false

        func drain(_ handle: FileHandle) {
            defer { try? handle.close() }
            var bytes = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    if count < 0 { truncated = true }
                    return
                }
                let accepted = min(count, max(0, GitOperationLimits.outputBytesPerStream - data.count))
                data.append(contentsOf: bytes.prefix(accepted))
                if accepted < count { truncated = true }
            }
        }
    }

    static func run(root: URL, arguments: [String],
                    executable: URL = URL(fileURLWithPath: GitRunner.defaultGitPath)) async -> GitMutationResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.currentDirectoryURL = root
                process.arguments = arguments
                // Keep GitKit's mutation environment contract, including editor
                // suppression needed by rebase/revert --continue.
                var environment = ProcessInfo.processInfo.environment
                environment["GIT_TERMINAL_PROMPT"] = "0"
                environment["GIT_OPTIONAL_LOCKS"] = "0"
                environment["LC_ALL"] = "C"
                environment["GIT_EDITOR"] = "true"
                environment["GIT_ALLOW_PROTOCOL"] = "https:http:ssh:git:file"
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let stdout = Pipe(), stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do { try process.run() }
                catch {
                    // No read tasks are launched until Process.run succeeds.
                    for pipe in [stdout, stderr] {
                        try? pipe.fileHandleForReading.close()
                        try? pipe.fileHandleForWriting.close()
                    }
                    continuation.resume(returning: GitMutationResult(started: false, exitCode: nil, signalled: false,
                        stdout: Data(), stderr: Data(), stdoutTruncated: false, stderrTruncated: false))
                    return
                }
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                let out = Capture(), err = Capture(), group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async { out.drain(stdout.fileHandleForReading); group.leave() }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async { err.drain(stderr.fileHandleForReading); group.leave() }
                process.waitUntilExit()
                group.wait()
                continuation.resume(returning: GitMutationResult(started: true, exitCode: process.terminationStatus,
                    signalled: process.terminationReason == .uncaughtSignal, stdout: out.data, stderr: err.data,
                    stdoutTruncated: out.truncated, stderrTruncated: err.truncated))
            }
        }
    }
}
