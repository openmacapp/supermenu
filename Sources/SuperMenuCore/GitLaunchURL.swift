import Foundation

/// The extension hands off a directory only. URLs can never request a mutation.
public enum GitLaunchURL {
    public static func make(_ directory: URL) -> URL? {
        guard directory.isFileURL else { return nil }
        var parts = URLComponents()
        parts.scheme = "supermenu"
        parts.host = "git"
        parts.queryItems = [URLQueryItem(name: "path", value: directory.path)]
        return parts.url
    }

    public static func directory(from url: URL) -> URL? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "supermenu", parts.host == "git",
              let items = parts.queryItems, items.count == 1,
              items[0].name == "path", let path = items[0].value,
              path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return URL(fileURLWithPath: path)
    }
}
