<p align="center">
  <a href="README.md">简体中文</a> ·
  <strong>English</strong> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <img src="site/assets/app-icon.png" width="112" alt="SuperMenu icon">
</p>

<h1 align="center">SuperMenu</h1>

<p align="center">Everyday file actions, right in your context menu.</p>
<p align="center">
  <a href="https://openmacapp.github.io/supermenu/">Website</a> ·
  <a href="#installation">Install</a> ·
  <a href="https://github.com/openmacapp/supermenu/issues">Report an issue</a> ·
  <a href="LICENSE">GPL v2</a>
</p>

SuperMenu is a native macOS Finder extension. Select a file or folder, then open **SuperMenu** in the context menu to copy paths, launch an editor, create files, or organize them. Actions are arranged into five groups, and you can turn off the ones you don't need in Settings.

Supports Simplified Chinese, Japanese, Korean, and English. Follow the system language or choose a language in the app.

Use the links at the top to switch README languages. Change the app language in SuperMenu Settings, and the website language using the selector at the top right of the page.

## Features

| Group      | Actions                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------- |
| Copy Info  | Absolute paths, relative paths, shell-quoted paths, file names, and names without extensions  |
| Open With  | VS Code, GoLand, Cursor, and WorkBuddy; add other apps; open directories in Terminal or iTerm |
| New File   | Text, Markdown, JSON, Swift, and Go files, with automatic name collision handling             |
| Send To    | Copy or move to configured destinations such as Desktop, Documents, and Downloads             |
| File Tools | MD5 / SHA256 checksums, show / hide items, and create a folder using a file's name            |

- Relative paths use the Git repository root by default, or the current Finder folder outside a repository. You can also configure preferred project roots.
- Installed apps display their original icons; unavailable apps cannot be launched from the menu.
- The menu bar can also act on your Finder selection. The app provides language, menu, Open With, path, and About settings.

## Git history

Right-click a repository directory in Finder and choose **SuperMenu → Git History**, or use **Git → Open Repository** in the app. The graph shows branches and merges. Select a commit for files and diffs, or multiple commits for squash/revert. Advanced actions organize linear history (reorder, combine, edit messages) and reset with soft/mixed/hard modes.

Every operation has a preview; repository changes invalidate it. A clean working tree is required. Nothing is automatically stashed, discarded or pushed. Merge commits are not rewritten and merge-revert mainlines are not guessed. Resolve conflicts in your editor, mark files resolved, then continue or abort. Remote warnings use locally known refs, not freshly fetched server state.

Git execution and graph layout reuse MIT-licensed GitKit. Full licenses are available in About → Open-source licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

<a id="installation"></a>

## Installation

Currently available as a **source build**. No prebuilt installer has been published yet.

Requirements: **an Apple Silicon Mac, macOS 14 or later, and Xcode Command Line Tools (Swift 6+)**. The current build script targets `arm64`; Intel builds are not provided.

If the developer tools are missing, run this command and complete the system installation prompt:

```sh
xcode-select --install
```

Then build and install:

```sh
git clone https://github.com/openmacapp/supermenu.git
cd supermenu
zsh scripts/build.sh
zsh scripts/install.sh
open "$HOME/Applications/SuperMenu.app"
```

The build output is `dist/SuperMenu.app`, and the app is installed at `~/Applications/SuperMenu.app`. Running the install script again replaces the previous app at that location. The scripts use local ad-hoc signing; this is not a Developer ID-signed or notarized distribution.

### Enable the Finder extension

1. Open the app's **Enable** page and click **Open Finder Extension Settings**.
2. Enable the SuperMenu extension in macOS System Settings, then return to the app and confirm the status is **Enabled**.
3. Right-click a file, folder, or empty area in a Finder window and look for **SuperMenu**.

The menu bar needs to read your current Finder selection. Allow SuperMenu to control Finder when prompted. If you previously denied access, change it in **System Settings → Privacy & Security → Automation**. Enabling the Finder extension and granting this automation permission are separate settings.

System Services menus, permission prompts, and the system-displayed app name follow the macOS language. The app's language setting controls its settings interface and context menus.

## Development and validation

```sh
swift test                  # Core logic, config compatibility, four-language resources, and menu groups
zsh scripts/check-host.sh   # Finder menu tag dispatch and command mapping after menu rebuilds
zsh scripts/build.sh        # Compile the app and extension; package icons and translations
```

`swift test` does not exercise real Finder clicks. After changing the extension or app-launch behavior, install the build and verify files, folders, empty areas, and target apps in Finder.

| Path                     | Responsibility                                                       |
| ------------------------ | -------------------------------------------------------------------- |
| `App/`                   | SwiftUI settings, About window, menu bar, and system services        |
| `Extension/`             | FinderSync integration and menu callbacks                            |
| `Host/`                  | AppKit icons, app discovery, and command execution                   |
| `Sources/SuperMenuCore/` | Menu models, file actions, configuration, and localization resources |
| `Tests/`                 | Core unit tests and Host menu checks                                 |
| `scripts/`               | Building, icon packaging, installation, and validation               |
| `site/`                  | Framework-free static GitHub Pages website                           |

The main app stores its configuration in `~/Library/Application Support/SuperMenu/config.json`. Prefer editing it through Settings. Remove personal paths and unrelated information when reporting an issue.

### Maintain the website

```sh
python3 -m http.server 8080 --directory site
```

Open `http://localhost:8080`. Page structure, styles, and four-language copy live in `site/index.html`, `site/styles.css`, and `site/site.js`, respectively. No Node.js or frontend build tooling is required. The website reuses the app's icon design.

`.github/workflows/pages.yml` publishes `site/` when relevant files change on `master`, and also supports manual runs. Set the repository's Pages publishing source to **GitHub Actions**.

## Feedback and contributions

Before your first commit, run `python3 scripts/install-privacy-hooks.py` and use your GitHub private email. Checks reject noncompliant identities and recognized private data; see [commit privacy checks](docs/privacy.md) for custom hook integration and verification.

Use [Issues](https://github.com/openmacapp/supermenu/issues) to report bugs or suggest improvements. Include the macOS and app versions, which entry point you used, whether you selected a file or folder, and the expected and actual results. Run the relevant checks before submitting code, and keep localization keys consistent across all four languages.

When changing features, installation steps, or limitations, update all four READMEs: `README.md`, `README.en.md`, `README.ja.md`, and `README.ko.md`. Keep their section structure, commands, and link destinations consistent.

Licensed under [GNU GPL v2](LICENSE).
