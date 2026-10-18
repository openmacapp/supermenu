import AppKit
import Foundation

final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    @objc func runCommand(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let command = MenuCommand.parse(userData) else {
            error.pointee = "无法识别的命令" as NSString
            return
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty else {
            error.pointee = "没有选中文件" as NSString
            return
        }
        let context = MenuContext(
            kind: .items,
            targetedFolder: urls[0].deletingLastPathComponent(),
            selection: urls
        )
        let config = ConfigStore.load(from: ConfigStore.defaultURL())
        CommandRunner.run(command, context: context, config: config, presentErrors: true)
    }
}
