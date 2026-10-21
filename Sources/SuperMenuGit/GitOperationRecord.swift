import Foundation
import GitKit

enum GitOperationLimits {
    static let recordCount = 100
    static let retainedBytes = 2 * 1024 * 1024
    static let outputBytesPerStream = 32 * 1024
    static let commandBytes = 8 * 1024
}

public enum GitOperationStatus: String, Sendable {
    case notStarted, succeeded, failed, interrupted
}

/// A display-only, sanitized result. No commit objects, patches or raw output
/// survive in the workspace log, and the log is never persisted.
public struct GitOperationRecord: Identifiable, Sendable {
    public let id = UUID()
    public let date = Date()
    public let action: String
    public internal(set) var status = GitOperationStatus.notStarted
    public internal(set) var command: String?
    public internal(set) var commandModified = false
    public internal(set) var exitCode: Int32?
    public internal(set) var signalled = false
    public internal(set) var duration: TimeInterval = 0
    public internal(set) var stdout = ""
    public internal(set) var stderr = ""
    public internal(set) var outputTruncated = false
    public internal(set) var failureKey: String?

    init(action: String) { self.action = action }

    var cost: Int {
        512 + action.utf8.count + (command?.utf8.count ?? 0) + stdout.utf8.count + stderr.utf8.count + (failureKey?.utf8.count ?? 0)
    }
}

struct GitOperationStore {
    private(set) var records: [GitOperationRecord] = []
    private(set) var cost = 0

    mutating func append(_ record: GitOperationRecord) {
        records.append(record)
        cost += record.cost
        while records.count > GitOperationLimits.recordCount || cost > GitOperationLimits.retainedBytes {
            cost -= records.removeFirst().cost
        }
    }

    mutating func clear() { records = []; cost = 0 }
}

enum GitLogRedactor {
    // Patterns are deliberately display-only. Redacted commands are never used
    // for execution and the UI labels them as unsuitable for direct replay.
    static func redact(_ input: String, root: URL) -> String {
        var text = input
        for path in [root.path, root.resolvingSymlinksInPath().path, FileManager.default.homeDirectoryForCurrentUser.path]
            .filter({ $0.count > 1 })
            // sequence.editor is itself a shell command, so its path can
            // already contain escaped apostrophes before argv is formatted.
            .flatMap({ [$0, $0.replacingOccurrences(of: "'", with: "'\\''")] })
            .sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: path, with: "[local-path]")
        }
        let replacements: [(String, String)] = [
            (#"\x1B\[[0-?]*[ -/]*[@-~]"#, ""),
            (#"\x1B\][^\x07]*(?:\x07|\x1B\\)"#, ""),
            (#"(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"#, "[private-key]"),
            (#"(?i)(?:https?|ssh)://[^\s\"'<>]+"#, "[url]"),
            (#"/(?:Users|home)/[^\s\"'<>]+|/(?:private/)?var/folders/[^\s\"'<>]+"#, "[local-path]"),
            (#"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[email]"),
            (#"(?:gh[pousr]_|github_pat_|sk-|xox[baprs]-)[A-Za-z0-9_-]+|AKIA[A-Z0-9]+"#, "[credential]"),
            // Retain no suffix of quoted values or Authorization schemes.
            (#"(?im)\b(?:token|access[_-]?token|password|passwd|secret|authorization|proxy-authorization|api[_-]?key)[\"']?\s*[:=]\s*[^\r\n]*"#, "[credential]")
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text.unicodeScalars.map { scalar in
            if (scalar.value < 32 && scalar != "\n" && scalar != "\t") || (127...159).contains(scalar.value) ||
                scalar.value == 0x2028 || scalar.value == 0x2029 ||
                (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) {
                return "\\u{\(String(scalar.value, radix: 16))}"
            }
            return String(scalar)
        }.joined()
    }

    static func command(_ arguments: [String], root: URL) -> (text: String, modified: Bool) {
        let argv = [GitRunner.defaultGitPath] + arguments
        let original = argv.map(GitCommandFormatter.quote).joined(separator: " ")
        let sanitized = argv.map {
            redact($0, root: root).replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
        }.map(GitCommandFormatter.quote).joined(separator: " ")
        let text = prefix(sanitized, bytes: GitOperationLimits.commandBytes)
        return (text, text != original)
    }

    static func output(_ data: Data, truncated: Bool, root: URL) -> (text: String, truncated: Bool) {
        // An incomplete final line may contain only the prefix of a credential.
        var complete = data
        if truncated { complete = data.lastIndex(of: 10).map { data.prefix(through: $0) } ?? Data() }
        let sanitized = redact(String(decoding: complete, as: UTF8.self), root: root)
        return (prefix(sanitized, bytes: GitOperationLimits.outputBytesPerStream),
                truncated || sanitized.utf8.count > GitOperationLimits.outputBytesPerStream)
    }

    static func prefix(_ text: String, bytes: Int) -> String {
        var data = Data(text.utf8.prefix(bytes))
        while !data.isEmpty {
            if let text = String(data: data, encoding: .utf8) { return text }
            data.removeLast()
        }
        return ""
    }
}

extension GitWorkspace {
    public func operationRecords() -> [GitOperationRecord] { operationStore.records }
    public func clearOperationRecords() { operationStore.clear() }

    func recordOperation(action: String, body: (inout GitOperationRecord) async throws -> Void) async throws {
        var record = GitOperationRecord(action: action)
        let started = ContinuousClock.now
        defer {
            let elapsed = started.duration(to: .now).components
            record.duration = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            operationStore.append(record)
        }
        do { try await body(&record) }
        catch {
            let key = (error as? WorkspaceFailure)?.key ?? "git.log.operationFailed"
            record.failureKey = key
            if record.status == .succeeded { record.status = .failed }
            throw WorkspaceFailure(key)
        }
    }

    func runMutation(_ arguments: [String], record: inout GitOperationRecord) async throws {
        let command = GitLogRedactor.command(arguments, root: root)
        record.command = command.text
        record.commandModified = command.modified
        let result = await BoundedGitMutation.run(root: root, arguments: arguments)
        record.exitCode = result.exitCode
        record.signalled = result.signalled
        let stdout = GitLogRedactor.output(result.stdout, truncated: result.stdoutTruncated, root: root)
        let stderr = GitLogRedactor.output(result.stderr, truncated: result.stderrTruncated, root: root)
        record.outputTruncated = stdout.truncated || stderr.truncated
        record.stdout = stdout.text
        record.stderr = stderr.text
        guard result.started else { throw WorkspaceFailure("git.log.startFailed") }
        if result.exitCode == 0 && !result.signalled {
            record.status = .succeeded
        } else {
            record.status = (try? await operation()) != nil ? .interrupted : .failed
            throw WorkspaceFailure("git.log.commandFailed")
        }
    }
}
