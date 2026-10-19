<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <strong>日本語</strong> ·
  <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <img src="site/assets/app-icon.png" width="112" alt="SuperMenuのアイコン">
</p>

<h1 align="center">SuperMenu</h1>

<p align="center">いつものファイル操作を、右クリックメニューから。</p>
<p align="center">
  <a href="https://openmacapp.github.io/supermenu/">ウェブサイト</a> ·
  <a href="#installation">インストール</a> ·
  <a href="https://github.com/openmacapp/supermenu/issues">問題を報告</a> ·
  <a href="LICENSE">GPL v2</a>
</p>

SuperMenuはmacOSのネイティブFinder機能拡張です。ファイルやフォルダを選択し、右クリックメニューの「SuperMenu」からパスのコピー、エディタでの起動、ファイルの作成・整理ができます。操作は用途別に5つのグループにまとめられ、不要な項目は設定でオフにできます。

簡体字中国語、日本語、韓国語、英語に対応しています。システムの言語に従うか、アプリ内で言語を選択できます。

READMEの言語はページ上部のリンクで切り替えられます。アプリの言語はSuperMenuの設定で、ウェブサイトの言語はページ右上の選択欄で変更してください。

## 機能

| グループ                   | 操作                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------- |
| 情報をコピー               | 絶対パス、相対パス、シェル用に引用符で囲んだパス、ファイル名、拡張子を除くファイル名              |
| このアプリケーションで開く | VS Code、GoLand、Cursor、WorkBuddyに対応。他のアプリも追加可能。ターミナルやiTermでフォルダを開く |
| 新規ファイル               | テキスト、Markdown、JSON、Swift、Goファイルの作成。同名ファイルとの衝突を自動回避                 |
| 送る                       | デスクトップ、書類、ダウンロードなど、設定したフォルダへのコピー・移動                            |
| ファイル操作               | MD5 / SHA256チェックサム、表示・非表示の切り替え、ファイル名を使ったフォルダ作成                  |

- 相対パスは通常Gitリポジトリのルートを基準とし、リポジトリ外では現在のFinderフォルダを使います。優先するプロジェクトルートも設定できます。
- インストール済みアプリは本来のアイコンで表示されます。利用できないアプリをメニューから起動することはできません。
- メニューバーからもFinderの選択項目を操作できます。アプリには言語、メニュー、開くアプリ、パス、アプリ情報の設定があります。

<a id="installation"></a>

## インストール

現在は**ソースからのビルド**に対応しています。ビルド済みインストーラはまだ公開していません。

必要な環境：**Apple Silicon搭載Mac、macOS 14以降、Xcode Command Line Tools**。現在のビルドスクリプトは`arm64`を対象としており、Intel向けビルドは提供していません。

開発ツールをインストールしていない場合は、次のコマンドを実行し、システムの案内に従ってインストールを完了してください。

```sh
xcode-select --install
```

続いてビルドとインストールを行います。

```sh
git clone https://github.com/openmacapp/supermenu.git
cd supermenu
zsh scripts/build.sh
zsh scripts/install.sh
open "$HOME/Applications/SuperMenu.app"
```

ビルド結果は`dist/SuperMenu.app`に出力され、`~/Applications/SuperMenu.app`にインストールされます。インストールスクリプトを再実行すると、この場所にある旧版アプリが置き換わります。スクリプトはローカルのad-hoc署名を使用します。Developer ID署名や公証を行った配布パッケージではありません。

### Finder機能拡張を有効にする

1. SuperMenuの「有効化」ページで「Finder機能拡張の設定を開く」をクリックします。
2. macOSのシステム設定でSuperMenu機能拡張を有効にし、アプリに戻って状態が「有効」になっていることを確認します。
3. Finderでファイル、フォルダ、またはウインドウの空白部分を右クリックし、「SuperMenu」を開きます。

メニューバーの操作には、Finderで現在選択している項目の読み取りが必要です。初回の確認でSuperMenuによるFinderの制御を許可してください。以前に拒否した場合は、システム設定の「プライバシーとセキュリティ → オートメーション」で変更できます。Finder機能拡張の有効化と、このオートメーションの許可は別の設定です。

システムのサービスメニュー、アクセス許可の確認、システム上のアプリ名はmacOSの言語に従います。アプリ内の言語設定は、設定画面と右クリックメニューに適用されます。

## 開発と検証

```sh
swift test                  # コアロジック、設定の互換性、4言語のリソース、メニューのグループ化
zsh scripts/check-host.sh   # Finderメニューのtagによる振り分けと、再構築後のコマンド対応
zsh scripts/build.sh        # アプリと機能拡張のコンパイル、アイコンと翻訳のパッケージ化
```

`swift test`では実際のFinderクリック操作を検証しません。機能拡張やアプリ起動処理を変更した場合は、ビルド結果をインストールし、Finderでファイル、フォルダ、空白部分、対象アプリの動作を確認してください。

| パス                     | 役割                                                                    |
| ------------------------ | ----------------------------------------------------------------------- |
| `App/`                   | SwiftUIの設定画面、アプリ情報ウインドウ、メニューバー、システムサービス |
| `Extension/`             | FinderSync連携とメニューのコールバック                                  |
| `Host/`                  | AppKitアイコン、アプリの検出、コマンド実行                              |
| `Sources/SuperMenuCore/` | メニューモデル、ファイル操作、設定、ローカライズリソース                |
| `Tests/`                 | コアの単体テストとHostメニューの検証                                    |
| `scripts/`               | ビルド、アイコンのパッケージ化、インストール、検証                      |
| `site/`                  | フレームワークを使わないGitHub Pagesの静的サイト                        |

メインアプリの設定は`~/Library/Application Support/SuperMenu/config.json`に保存されます。通常は設定画面から変更してください。問題の報告時は、個人のパスなど関係のない情報を取り除いてください。

### ウェブサイトのメンテナンス

```sh
python3 -m http.server 8080 --directory site
```

`http://localhost:8080`を開きます。ページ構造、スタイル、4言語の文言は、それぞれ`site/index.html`、`site/styles.css`、`site/site.js`にあります。Node.jsやフロントエンドのビルドツールは不要です。アイコンはアプリと同じデザインを使っています。

`.github/workflows/pages.yml`は、`master`上の関連ファイルが更新されたときに`site/`を公開します。手動実行にも対応しています。GitHubリポジトリのPages公開元は**GitHub Actions**に設定してください。

## フィードバックと貢献

不具合や改善案は[Issues](https://github.com/openmacapp/supermenu/issues)へお寄せください。macOSとアプリのバージョン、操作した入口、ファイルとフォルダのどちらを選択したか、期待した結果と実際の結果を記載してください。コードを提出する前に該当する検証を実行し、4言語のローカライズキーを一致させてください。

機能、インストール手順、制限事項を変更した場合は、`README.md`、`README.en.md`、`README.ja.md`、`README.ko.md`の4ファイルを更新してください。各言語版の章構成、コマンド、リンク先を揃えてください。

ライセンスは[GNU GPL v2](LICENSE)です。
