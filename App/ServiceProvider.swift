import AppKit
import Foundation

final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    @objc func runCommand(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        let l10n = L10n(language: config.language)
        guard let command = MenuCommand.parse(userData) else {
            error.pointee = l10n.text("error.unknownCommand") as NSString
            return
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty else {
            error.pointee = l10n.text("error.noSelection") as NSString
            return
        }
        let context = MenuContext(
            kind: .items,
            targetedFolder: urls[0].deletingLastPathComponent(),
            selection: urls
        )
        CommandRunner.run(command, context: context, config: config, presentErrors: true)
    }
}
