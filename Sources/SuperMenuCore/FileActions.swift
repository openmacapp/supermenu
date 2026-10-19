import CommonCrypto
import CryptoKit
import Foundation

public struct ActionError: Error, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

public enum HashAlgorithm: String, Equatable {
    case md5
    case sha256
}

public enum FileActions {
    public static func uniqueChildName(stem: String, ext: String, existing: Set<String>) -> String {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let first = stem + suffix
        if !existing.contains(first) { return first }
        var index = 2
        while existing.contains("\(stem) \(index)\(suffix)") {
            index += 1
        }
        return "\(stem) \(index)\(suffix)"
    }

    public static func creationDirectory(context: MenuContext, fileManager: FileManager = .default) -> URL? {
        if context.selection.count == 1 {
            let url = context.selection[0]
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
            return url.deletingLastPathComponent()
        }
        if context.selection.isEmpty {
            return context.targetedFolder
        }
        return context.selection[0].deletingLastPathComponent()
    }

    public static func createFile(
        template: NewFileTemplate,
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let existing = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
        let name = uniqueChildName(stem: "未命名", ext: template.ext, existing: existing)
        let url = directory.appendingPathComponent(name)
        guard fileManager.createFile(atPath: url.path, contents: Data(template.contents.utf8)) else {
            throw ActionError("无法创建 \(name)")
        }
        return url
    }

    public static func placeItems(
        _ urls: [URL],
        into directory: URL,
        move: Bool,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ActionError("目标文件夹不存在")
        }
        var existing = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
        var placed: [URL] = []
        for url in urls {
            var itemIsDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &itemIsDirectory)
            let name = url.lastPathComponent
            let ext = itemIsDirectory.boolValue ? "" : (name as NSString).pathExtension
            let stem = itemIsDirectory.boolValue ? name : PathCommands.stem(of: name)
            let unique = uniqueChildName(stem: stem, ext: ext, existing: existing)
            let destination = directory.appendingPathComponent(unique)
            if move {
                try fileManager.moveItem(at: url, to: destination)
            } else {
                try fileManager.copyItem(at: url, to: destination)
            }
            existing.insert(unique)
            placed.append(destination)
        }
        return placed
    }

    public static func folderFromName(of url: URL, fileManager: FileManager = .default) throws -> URL {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let parent = url.deletingLastPathComponent()
        let existing = Set(try fileManager.contentsOfDirectory(atPath: parent.path))
        let stem = isDirectory.boolValue ? url.lastPathComponent : PathCommands.stem(of: url.lastPathComponent)
        let name = uniqueChildName(stem: stem, ext: "", existing: existing)
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    public static func toggleHidden(of url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isHiddenKey])
        let hidden = !(values.isHidden ?? false)
        var update = URLResourceValues()
        update.isHidden = hidden
        var mutable = url
        try mutable.setResourceValues(update)
        return hidden
    }

    public static func hash(of url: URL, algorithm: HashAlgorithm) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ActionError("只能计算文件的校验值")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        switch algorithm {
        case .md5:
            var context = CC_MD5_CTX()
            CC_MD5_Init(&context)
            while true {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                chunk.withUnsafeBytes { raw in
                    _ = CC_MD5_Update(&context, raw.baseAddress, CC_LONG(chunk.count))
                }
            }
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&digest, &context)
            return digest.map { String(format: "%02x", $0) }.joined()
        case .sha256:
            var hasher = SHA256()
            while true {
                let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
