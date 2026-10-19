<p align="center">
  <img src="site/assets/app-icon.png" width="112" alt="SuperMenu 图标">
</p>

<h1 align="center">SuperMenu · 超级右键</h1>

<p align="center">把常用文件操作，放回右键菜单。</p>
<p align="center">
  <a href="https://openmacapp.github.io/supermenu/">项目网站</a> ·
  <a href="#安装">安装</a> ·
  <a href="https://github.com/openmacapp/supermenu/issues">反馈问题</a> ·
  <a href="LICENSE">GPL v2</a>
</p>

SuperMenu 是原生 macOS Finder 扩展。选中文件或文件夹，在右键菜单的「超级右键」中复制路径、打开编辑器、新建文件或整理文件。功能按用途收进五个分组，设置里可以关闭不需要的操作。

支持简体中文、日本語、한국어和 English，可跟随系统或在应用内切换。

## 功能

| 分组     | 操作                                                                                 |
| -------- | ------------------------------------------------------------------------------------ |
| 复制信息 | 绝对路径、相对路径、适合终端使用的引号转义路径、文件名、无扩展名文件名               |
| 打开方式 | VS Code、GoLand、Cursor、WorkBuddy；支持添加其他应用；在 Terminal / iTerm 中打开目录 |
| 新建     | 文本、Markdown、JSON、Swift、Go 文件，自动避开重名                                   |
| 发送到   | 复制或移动到桌面、文稿、下载等配置的目录                                             |
| 文件工具 | MD5 / SHA256 校验值、显示 / 隐藏、按文件名新建文件夹                                 |

- 相对路径默认以 Git 仓库根为基准，仓库外使用当前 Finder 文件夹；也可以设置优先使用的项目根。
- 已安装的应用使用原始应用图标；不可用的应用不会作为可执行操作。
- 菜单栏也可以操作当前 Finder 选择，应用中提供语言、菜单、打开方式、路径和关于设置。

## 安装

当前提供**源码构建**，尚未发布预编译安装包。

要求：**Apple Silicon Mac、macOS 14 或更新版本、Xcode Command Line Tools**。当前构建脚本固定生成 `arm64` 应用，未提供 Intel 构建。

如果没有开发工具，先运行并完成系统安装提示：

```sh
xcode-select --install
```

然后构建和安装：

```sh
git clone https://github.com/openmacapp/supermenu.git
cd supermenu
zsh scripts/build.sh
zsh scripts/install.sh
open "$HOME/Applications/SuperMenu.app"
```

构建产物位于 `dist/SuperMenu.app`，安装到 `~/Applications/SuperMenu.app`。再次运行安装脚本会替换这个位置的旧版应用。脚本使用本地 ad-hoc 签名，不是 Developer ID 签名或公证发行包。

### 启用 Finder 扩展

1. 打开 SuperMenu 的「启用」页，点击「打开访达扩展设置」。
2. 在 macOS 系统设置中启用 SuperMenu 扩展，再回到应用确认状态为「已启用」。
3. 在 Finder 中右键文件、文件夹或窗口空白处，找到「超级右键」。

菜单栏入口需要读取 Finder 当前选择。首次使用时允许应用控制 Finder；如曾拒绝，可在系统设置的「隐私与安全性 → 自动化」中调整。Finder 扩展的启用与这项自动化权限是两个不同设置。

系统服务菜单、权限提示和系统显示的应用名称跟随 macOS 语言；应用内的语言选项控制设置与右键菜单。

## 开发与验证

```sh
swift test                  # 核心逻辑、配置兼容、四语言资源和菜单分组
zsh scripts/check-host.sh   # Finder 菜单 tag 分发与重建后的命令映射
zsh scripts/build.sh        # 编译主应用、Finder 扩展并打包图标和翻译
```

`swift test` 不包含真实 Finder 点击链路。修改扩展或应用启动逻辑后，还需要安装构建结果，在 Finder 中验证文件、文件夹、空白区域及目标应用。

| 路径                     | 职责                                     |
| ------------------------ | ---------------------------------------- |
| `App/`                   | SwiftUI 设置、关于窗口、菜单栏与系统服务 |
| `Extension/`             | FinderSync 接入与菜单回调                |
| `Host/`                  | AppKit 图标、应用发现与命令执行          |
| `Sources/SuperMenuCore/` | 菜单模型、文件操作、配置与本地化资源     |
| `Tests/`                 | 核心单测与 Host 菜单检查                 |
| `scripts/`               | 构建、图标打包、安装与验证               |
| `site/`                  | 无框架的 GitHub Pages 静态站点           |

主应用配置保存在 `~/Library/Application Support/SuperMenu/config.json`。优先通过设置界面修改；报告问题时请去掉个人路径等无关信息。

### 维护项目网站

```sh
python3 -m http.server 8080 --directory site
```

打开 `http://localhost:8080`。页面结构、样式和四语言文案分别在 `site/index.html`、`site/styles.css` 和 `site/site.js`，不需要 Node.js 或前端构建工具。图标复用应用的原始设计。

`.github/workflows/pages.yml` 在 `master` 上相关文件更新时发布 `site/`，也支持手动触发。GitHub 仓库的 Pages 发布源应为 **GitHub Actions**。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/openmacapp/supermenu/issues) 提交问题或建议。描述 macOS 版本、应用版本、操作入口、选择的是文件还是文件夹，以及预期和实际结果。提交代码前请运行对应验证，并保持四种语言的 key 一致。

项目采用 [GNU GPL v2](LICENSE) 许可。
