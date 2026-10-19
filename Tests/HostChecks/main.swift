import AppKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func leaves(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in
        if let submenu = item.submenu { return leaves(submenu) }
        return item.isSeparatorItem ? [] : [item]
    }
}

let _ = NSApplication.shared
let target = NSObject()
let action = NSSelectorFromString("performCommand:")
let context = MenuContext(kind: .items, targetedFolder: URL(fileURLWithPath: "/tmp"),
                          selection: [URL(fileURLWithPath: "/tmp/example.txt")])
var config = MenuConfig.standard
config.language = .english
let installed: Set<String> = ["com.jetbrains.goland", "com.todesktop.230313mzl4w4u92",
                             "com.tencent.workbuddy.mac", "com.apple.Terminal", "com.googlecode.iterm2"]
let nodes = MenuBuilder.build(context: context, config: config, installedBundleIDs: installed)
let renderer = MenuRenderer()
let menu = renderer.menu(from: nodes, target: target, action: action)
let items = leaves(menu)

// Finder copies only supported fields, including tag; representedObject is lost.
check(items.allSatisfy { $0.tag > 0 }, "Finder commands must have a transferable identity")
check(Set(items.map(\.tag)).count == items.count, "Different commands must not share tags")

let expected: [(String, MenuCommand)] = [
    ("GoLand", .openApp(bundleIDs: ["com.jetbrains.goland"])),
    ("Cursor", .openApp(bundleIDs: ["com.todesktop.230313mzl4w4u92"])),
    ("WorkBuddy", .openApp(bundleIDs: ["com.tencent.workbuddy.mac", "com.workbuddy.workbuddy"])),
    ("Open in Terminal", .builtin(.openTerminal)),
    ("Open in iTerm", .builtin(.openITerm)),
    ("Copy Absolute Path", .builtin(.copyAbsolute))
]
for (title, command) in expected {
    guard let original = items.first(where: { $0.title == title }) else {
        check(false, "Missing menu item: \(title)")
        continue
    }
    let sender = NSMenuItem(title: title, action: original.action, keyEquivalent: "")
    sender.tag = original.tag
    check(sender.representedObject == nil, "Simulated Finder sender must not carry representedObject")
    check(renderer.command(for: sender) == command, "Finder callback lost or changed \(title)")
}
check(items.first { $0.title.hasPrefix("Visual Studio Code") }?.isEnabled == false,
      "Unavailable VS Code must remain disabled")

// Rebuilding/reordering/localizing another menu must not reinterpret an older menu's tags.
let goLand = items.first { $0.title == "GoLand" }!
config.language = .japanese
config.openWith.reverse()
let rebuilt = renderer.menu(from: MenuBuilder.build(context: context, config: config, installedBundleIDs: installed),
                            target: target, action: action)
check(renderer.command(for: goLand) == .openApp(bundleIDs: ["com.jetbrains.goland"]), "Old menu dispatched a different app")
check(leaves(rebuilt).first { $0.title == "GoLand" }?.tag == goLand.tag, "Repeated menus must reuse command identity")
let unknown = NSMenuItem(title: "GoLand", action: action, keyEquivalent: "")
unknown.tag = Int.max
check(renderer.command(for: unknown) == nil, "Unknown tag must not execute by matching title")
print("Host menu checks passed")
