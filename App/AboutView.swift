import SwiftUI

struct AboutView: View {
    static let windowID = "about"

    @State private var showLicenses = false
    @ObservedObject var model: SettingsModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        let l10n = model.l10n

        VStack(spacing: 16) {
            Image(nsImage: MenuIcons.appIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(l10n.text("app.name"))
                    .font(.largeTitle.bold())
                Text(l10n.text("app.tagline"))
                    .foregroundStyle(.secondary)
                Text(l10n.text("about.version", version, build))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            HStack(spacing: 24) {
                Link(l10n.text("about.project"), destination: URL(string: "https://github.com/openmacapp/supermenu")!)
                Link(l10n.text("about.feedback"), destination: URL(string: "https://github.com/openmacapp/supermenu/issues")!)
            }
            Button(l10n.text("about.licenses")) { showLicenses = true }
            Text(l10n.text("about.license"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 420)
        .environment(\.locale, l10n.locale)
        .sheet(isPresented: $showLicenses) {
            VStack {
                GitDiffText(text: licenseText, highlightDiff: false).frame(width: 700, height: 500)
                Button(l10n.text("git.cancel")) { showLicenses = false }.keyboardShortcut(.cancelAction)
            }.padding()
        }
    }
    private var licenseText: String {
        let paths = ["LICENSE.txt", "THIRD_PARTY_NOTICES.md", "ThirdPartyLicenses/Gitify-MIT.txt"]
        return paths.compactMap { path in
            guard let root = Bundle.main.resourceURL else { return nil }
            return try? String(contentsOf: root.appendingPathComponent(path))
        }.joined(separator: "\n\n────────────────────────\n\n")
    }
}

/// Every entry point opens the same window, including when settings are closed.
struct AboutButton: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AboutView.windowID)
        } label: {
            Label(model.l10n.text("about.title", model.l10n.text("app.name")), systemImage: "info.circle")
        }
    }
}
