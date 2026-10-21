"use strict";

// Chinese is the HTML fallback, so the documentation remains usable without JS.
const chinese = Object.fromEntries(
  [...document.querySelectorAll("[data-i18n]")].map((element) => [
    element.dataset.i18n,
    element.textContent,
  ]),
);

const translations = {
  "zh-Hans": chinese,
  en: {
    skip: "Skip to content",
    language: "Language",
    navFeatures: "Features",
    navInstall: "Install",
    heroLine1: "Your next move.",
    heroLine2: "Just a right-click.",
    heroDescription:
      "Copy paths, open your editor, and organize files. Open the Git workspace from Finder to review changes, tidy commits, and understand each command.",
    getStarted: "Get started",
    viewSource: "Explore the source →",
    openSource: "Free & open source",
    demoFile: "One file. A few handy shortcuts.",
    demoNote: "Interactive illustration · Select a group to explore",
    groupCopy: "Copy Info",
    groupOpen: "Open With",
    groupNew: "New File",
    groupSend: "Send To",
    groupTools: "File Tools",
    factNative: "Native Finder extension",
    factGroups: "Groups to keep things tidy",
    factLanguages: "Chinese · Japanese · Korean · English",
    featuresTitle: "Fewer detours. Better flow.",
    featuresIntro: "The Finder you know, with a few more useful moves.",
    pathsTitle: "Paths, ready to paste.",
    pathsDescription:
      "Copy absolute, relative, or shell-quoted paths. Use the Git repository root automatically, or set your own project roots.",
    appsTitle: "Open it your way.",
    appsDescription:
      "Send files to your editor and directories to Terminal or iTerm. Add your own apps and see their original installed icons.",
    filesTitle: "Small tasks. Handled here.",
    filesDescription:
      "Create files, copy or move to common folders, calculate checksums, or toggle hidden files. Turn off any actions you don't need.",
    installTitle: "Make it part of your day.",
    installIntro:
      "Build from source on an Apple Silicon Mac with macOS 14 or later and Xcode Command Line Tools (Swift 6+).",
    releaseNote:
      "No prebuilt installer is published yet. Current builds use local signing and are not notarized.",
    fullGuide: "Full installation guide ↗",
    step1Title: "Build and install",
    step1Description:
      "Install Command Line Tools first, then run the commands below.",
    step2Title: "Enable the Finder extension",
    step2Description:
      "Open the app's Enable page, click Open Finder Extension Settings, and enable SuperMenu in System Settings.",
    step3Title: "Back to Finder. Right-click.",
    step3Description:
      "Select a file or folder and expand SuperMenu. Right-click an empty area to work with the current directory.",
    faqTitle: "A few useful details.",
    faq1Title: "Why isn't the context menu showing up?",
    faq1Answer:
      "Confirm that the Finder extension is enabled in the app, then reopen the Finder menu. The extension and system Services menu are separate. SuperMenu does not add a Finder toolbar button.",
    faq2Title: "Which permissions does it need?",
    faq2Answer:
      "Enable the Finder extension in System Settings. The menu bar opens Git repositories and app settings; it does not read the Finder selection or require Finder automation permission.",
    faq3Title: "Can I change the language and menu actions?",
    faq3Answer:
      "Yes. Choose Chinese, Japanese, Korean, English, or System Default in Settings, and turn off unused actions. System Services, permission prompts, and the system app name still follow the macOS language.",
    faq4Title: "Does it support Intel Macs?",
    faq4Answer:
      "The current build script targets arm64 on Apple Silicon. Intel builds are not provided or verified yet.",
    closingTitle: "A small utility. A smoother day.",
    closingDescription: "Native, open source, and getting better. Join in.",
    feedback: "Ideas & feedback ↗",
    footerNote: "Made for everyday files on macOS.",
    navGit: "Git workspace",
    gitTitle: "Understand changes. Shape your history.",
    gitIntro:
      "Open a directory to explore its history, compare snapshots, organize commits, and handle conflicts in a native panel.",
    gitSample1: "Add welcome page",
    gitSample2: "Refine page description",
    gitSample3: "Update install guide",
    gitIllustrationNote:
      "Feature illustration with fictional commits and code. This is not an app screenshot and runs no Git operations.",
    gitBrowseTitle: "Find a commit. Review each file.",
    gitBrowseDescription:
      "Search by message, author, or SHA. Locate HEAD and navigate to parent commits. Compare two commits or branch snapshots, then browse highlighted diffs in a file tree with individual files loaded on demand.",
    gitEditTitle: "Review the impact before you act.",
    gitEditDescription:
      "Cherry-pick, reword, drop, squash, fixup, or reorder commits. Check the target and affected range before running. Resolve conflicts and continue, or abort the operation. Revert creates undo commits; reset offers soft, mixed, and hard modes.",
    gitLearnTitle: "Learn the commands as you go.",
    gitLearnDescription:
      "Command previews follow your choices and expose rebase todo and helper files. Review results and a redacted operation log afterward. Commands that need helper files are clearly marked before you copy them.",
    gitEntryTitle: "Start with a directory.",
    gitEntryDescription:
      "In Finder, right-click a repository folder or an empty area inside it, then choose SuperMenu → Git History. You can also open a repository from the menu bar or press ⌘O in the app. Use ⌘⇧G in the folder picker to enter a path.",
    gitGetStarted: "Build and enable the extension →",
    gitLimitsTitle: "Current scope",
    gitLimitsDescription:
      "Works on local repositories with no automatic push. Resolve working-tree changes before rewriting history. Replay ranges containing merges and cherry-picking merge commits are not supported. Compare commit or branch snapshots; index and working-tree comparisons are not available yet. Remote warnings use locally known refs, not live remote state.",
  },
  ja: {
    skip: "本文へ移動",
    language: "言語",
    navFeatures: "機能",
    navInstall: "インストール",
    heroLine1: "いつもの操作を、",
    heroLine2: "右クリックから。",
    heroDescription:
      "パスのコピー、エディタの起動、ファイルの整理。FinderからGitワークスペースを開き、変更の確認やコミットの整理をしながら、各コマンドも学べます。",
    getStarted: "使い始める",
    viewSource: "ソースコードを見る →",
    openSource: "無料・オープンソース",
    demoFile: "ひとつのファイルに、便利な操作を。",
    demoNote: "メニューの操作イメージ · グループを選んでみてください",
    groupCopy: "情報をコピー",
    groupOpen: "開くアプリ",
    groupNew: "新規ファイル",
    groupSend: "送る",
    groupTools: "ファイル操作",
    factNative: "ネイティブFinder機能拡張",
    factGroups: "用途別のグループ",
    factLanguages: "中国語・日本語・韓国語・英語",
    featuresTitle: "行き来を減らして、もっとスムーズに。",
    featuresIntro: "いつものFinderに、ちょうどいい操作を。",
    pathsTitle: "そのまま使えるパスを。",
    pathsDescription:
      "絶対パス、相対パス、シェル用パスをコピー。Gitリポジトリのルートを自動で使うほか、独自の基準も設定できます。",
    appsTitle: "使い慣れたツールで開く。",
    appsDescription:
      "ファイルはエディタへ、フォルダはターミナルやiTermへ。アプリを追加でき、インストール済みアプリ本来のアイコンを表示します。",
    filesTitle: "小さな作業を、その場で。",
    filesDescription:
      "ファイル作成、よく使うフォルダへのコピーや移動、チェックサムの計算、表示・非表示の切り替え。使わない操作は設定でオフにできます。",
    installTitle: "ここから始めましょう。",
    installIntro:
      "現在はソースからビルドします。Apple Silicon搭載Mac、macOS 14以降、Xcode Command Line Tools (Swift 6+)が必要です。",
    releaseNote:
      "ビルド済みインストーラは未公開です。現在はローカル署名を使用し、公証は行っていません。",
    fullGuide: "詳しいインストール手順 ↗",
    step1Title: "ビルドしてインストール",
    step1Description:
      "Command Line Toolsのインストール完了後、以下のコマンドを実行します。",
    step2Title: "Finder機能拡張を有効にする",
    step2Description:
      "アプリの「有効化」ページでFinder機能拡張の設定を開き、システム設定でSuperMenuを有効にします。",
    step3Title: "Finderで右クリック",
    step3Description:
      "ファイルやフォルダを選び、SuperMenuを開きます。空白部分の右クリックでは現在のフォルダを操作できます。",
    faqTitle: "知っておくと便利なこと。",
    faq1Title: "右クリックメニューが表示されない場合は？",
    faq1Answer:
      "アプリでFinder機能拡張が有効になっていることを確認し、Finderのメニューを開き直してください。機能拡張とシステムのサービスメニューは別のものです。Finderツールバーへのボタン追加は行いません。",
    faq2Title: "必要なアクセス許可は？",
    faq2Answer:
      "システム設定でFinder機能拡張を有効にします。メニューバーはGitリポジトリや設定を開く入口です。Finderの選択項目は読み取らず、オートメーション権限も不要です。",
    faq3Title: "言語やメニュー項目を変更できますか？",
    faq3Answer:
      "設定で中国語、日本語、韓国語、英語、システム設定に従う、から選択できます。不要な操作もオフにできます。システムのサービス、権限確認、アプリ名はmacOSの言語に従います。",
    faq4Title: "Intel Macに対応していますか？",
    faq4Answer:
      "現在のビルドスクリプトはApple Silicon向けのarm64を対象にしています。Intel向けビルドは提供・検証していません。",
    closingTitle: "小さなツールで、毎日をスムーズに。",
    closingDescription:
      "ネイティブでオープンソース。一緒に改善していきましょう。",
    feedback: "ご意見・不具合報告 ↗",
    footerNote: "macOSの毎日のファイル操作に。",
    navGit: "Gitワークスペース",
    gitTitle: "変更を確認して、履歴を整理。",
    gitIntro:
      "フォルダから履歴を開き、比較、コミットの整理、競合への対応をネイティブのパネルで行えます。",
    gitSample1: "ようこそページを追加",
    gitSample2: "ページの説明を改善",
    gitSample3: "インストール手順を更新",
    gitIllustrationNote:
      "架空のコミットとコードによる機能のイメージです。アプリのスクリーンショットではなく、Git操作も実行しません。",
    gitBrowseTitle: "コミットを探し、ファイルごとに確認。",
    gitBrowseDescription:
      "メッセージ、作者、SHAで履歴を検索し、HEADや親コミットへ移動できます。2つのコミットやブランチのスナップショットを比較し、ファイルツリーから必要なファイルだけを読み込んで、色分けされた差分を確認できます。",
    gitEditTitle: "影響を確かめてから実行。",
    gitEditDescription:
      "Cherry-pick、メッセージの変更、削除、squash、fixup、並べ替えに対応。実行前に対象と影響範囲を確認できます。競合を解消して続行するか、操作を中止できます。Revertは取り消し用のコミットを作成し、resetはsoft・mixed・hardに対応します。",
    gitLearnTitle: "操作しながら、コマンドも学ぶ。",
    gitLearnDescription:
      "選択に応じてコマンドのプレビューが変わり、rebaseのtodoや補助ファイルも確認できます。実行後は結果と機密情報を除いた操作ログを確認できます。補助ファイルが必要なコマンドは、コピー前にその旨を表示します。",
    gitEntryTitle: "フォルダから始めましょう。",
    gitEntryDescription:
      "Finderでリポジトリのフォルダ、またはその中の空白部分を右クリックし、SuperMenu → Git の履歴を選択します。メニューバーやアプリ内の⌘Oからも開けます。フォルダ選択画面では⌘⇧Gでパスを入力できます。",
    gitGetStarted: "ビルドして機能拡張を有効にする →",
    gitLimitsTitle: "現在の対応範囲",
    gitLimitsDescription:
      "ローカルリポジトリを操作し、自動pushは行いません。履歴の変更前に作業ツリーの変更を処理してください。mergeを含む範囲の再適用と、mergeコミットのcherry-pickには未対応です。コミットやブランチのスナップショットを比較できますが、インデックスや作業ツリーとの比較は未対応です。リモートに関する警告はローカルの参照に基づき、リアルタイムの状態ではありません。",
  },
  ko: {
    skip: "본문으로 이동",
    language: "언어",
    navFeatures: "기능",
    navInstall: "설치",
    heroLine1: "익숙한 작업을,",
    heroLine2: "오른쪽 클릭으로.",
    heroDescription:
      "경로 복사, 편집기 열기, 파일 정리까지. Finder에서 Git 작업 공간을 열어 변경 사항을 확인하고 커밋을 정리하며 각 명령도 배울 수 있습니다.",
    getStarted: "시작하기",
    viewSource: "소스 코드 보기 →",
    openSource: "무료 오픈 소스",
    demoFile: "하나의 파일, 더 편리한 작업.",
    demoNote: "메뉴 작동 예시 · 그룹을 선택해 살펴보세요",
    groupCopy: "정보 복사",
    groupOpen: "다음으로 열기",
    groupNew: "새 파일",
    groupSend: "보내기",
    groupTools: "파일 도구",
    factNative: "네이티브 Finder 확장",
    factGroups: "용도별로 정리된 그룹",
    factLanguages: "중국어 · 일본어 · 한국어 · 영어",
    featuresTitle: "오가는 시간은 줄이고, 더 편리하게.",
    featuresIntro: "익숙한 Finder에 꼭 필요한 작업을 더했습니다.",
    pathsTitle: "바로 쓸 수 있는 경로.",
    pathsDescription:
      "절대 경로, 상대 경로, 셸용 경로를 복사하세요. Git 저장소 루트를 자동으로 사용하거나 프로젝트 루트를 직접 설정할 수 있습니다.",
    appsTitle: "익숙한 도구로 여세요.",
    appsDescription:
      "파일은 편집기로, 폴더는 터미널이나 iTerm으로. 앱을 추가할 수 있으며 설치된 앱의 원래 아이콘을 표시합니다.",
    filesTitle: "작은 파일 작업도 그 자리에서.",
    filesDescription:
      "파일 만들기, 자주 쓰는 폴더로 복사 또는 이동, 체크섬 계산, 숨김 전환까지. 필요 없는 작업은 설정에서 끌 수 있습니다.",
    installTitle: "여기서 시작하세요.",
    installIntro:
      "현재 소스 빌드를 제공합니다. Apple Silicon Mac, macOS 14 이상, Xcode Command Line Tools (Swift 6+)가 필요합니다.",
    releaseNote:
      "사전 빌드된 설치 파일은 아직 없습니다. 현재 빌드는 로컬 서명을 사용하며 공증되지 않았습니다.",
    fullGuide: "전체 설치 안내 ↗",
    step1Title: "빌드 및 설치",
    step1Description:
      "Command Line Tools를 먼저 설치한 다음 아래 명령을 실행하세요.",
    step2Title: "Finder 확장 활성화",
    step2Description:
      "앱의 활성화 페이지에서 Finder 확장 프로그램 설정을 열고 시스템 설정에서 SuperMenu를 활성화하세요.",
    step3Title: "Finder에서 오른쪽 클릭",
    step3Description:
      "파일이나 폴더를 선택하고 SuperMenu를 펼치세요. 빈 공간을 오른쪽 클릭하면 현재 폴더를 작업할 수 있습니다.",
    faqTitle: "알아두면 좋은 정보.",
    faq1Title: "오른쪽 클릭 메뉴가 보이지 않아요.",
    faq1Answer:
      "앱에서 Finder 확장이 활성화되어 있는지 확인한 후 Finder 메뉴를 다시 여세요. 확장 프로그램과 시스템 서비스 메뉴는 별개입니다. Finder 도구 막대에 추가 버튼을 만들지 않습니다.",
    faq2Title: "어떤 권한이 필요한가요?",
    faq2Answer:
      "시스템 설정에서 Finder 확장을 활성화하세요. 메뉴 막대는 Git 저장소와 설정을 여는 진입점이며, Finder 선택 항목을 읽거나 자동화 권한을 요구하지 않습니다.",
    faq3Title: "언어와 메뉴 항목을 바꿀 수 있나요?",
    faq3Answer:
      "설정에서 중국어, 일본어, 한국어, 영어 또는 시스템 설정 따르기를 선택하고 쓰지 않는 작업을 끌 수 있습니다. 시스템 서비스, 권한 요청, 시스템 앱 이름은 macOS 언어를 따릅니다.",
    faq4Title: "Intel Mac도 지원하나요?",
    faq4Answer:
      "현재 빌드 스크립트는 Apple Silicon용 arm64 앱을 생성합니다. Intel 빌드는 아직 제공하거나 검증하지 않았습니다.",
    closingTitle: "작은 도구로 더 편리한 하루를.",
    closingDescription: "네이티브 오픈 소스 앱입니다. 함께 개선해 나가요.",
    feedback: "의견 및 문제 신고 ↗",
    footerNote: "macOS의 일상적인 파일 작업을 위해.",
    navGit: "Git 작업 공간",
    gitTitle: "변경을 확인하고, 이력을 정리하세요.",
    gitIntro:
      "폴더에서 이력을 열어 비교, 커밋 정리, 충돌 처리를 네이티브 패널에서 진행하세요.",
    gitSample1: "환영 페이지 추가",
    gitSample2: "페이지 설명 개선",
    gitSample3: "설치 안내 업데이트",
    gitIllustrationNote:
      "가상의 커밋과 코드로 만든 기능 예시입니다. 앱 스크린샷이 아니며 Git 작업을 실행하지 않습니다.",
    gitBrowseTitle: "커밋을 찾고, 파일별로 확인하세요.",
    gitBrowseDescription:
      "메시지, 작성자, SHA로 이력을 검색하고 HEAD와 부모 커밋으로 이동하세요. 두 커밋 또는 브랜치 스냅샷을 비교하고, 파일 트리에서 필요한 파일만 불러와 색상으로 구분된 차이를 확인할 수 있습니다.",
    gitEditTitle: "영향을 확인한 뒤 실행하세요.",
    gitEditDescription:
      "Cherry-pick, 메시지 수정, 삭제, squash, fixup, 순서 변경을 지원합니다. 실행 전에 대상과 영향 범위를 확인하세요. 충돌을 해결한 뒤 계속하거나 작업을 중단할 수 있습니다. Revert는 취소용 커밋을 만들며 reset은 soft, mixed, hard 모드를 제공합니다.",
    gitLearnTitle: "작업하면서 명령도 배우세요.",
    gitLearnDescription:
      "선택에 따라 명령 미리보기가 바뀌며 rebase todo와 보조 파일도 확인할 수 있습니다. 실행 후 결과와 민감 정보를 가린 작업 기록을 볼 수 있습니다. 보조 파일이 필요한 명령은 복사 전에 안내합니다.",
    gitEntryTitle: "폴더에서 시작하세요.",
    gitEntryDescription:
      "Finder에서 저장소 폴더나 폴더 안의 빈 공간을 오른쪽 클릭하고 SuperMenu → Git 커밋 기록을 선택하세요. 메뉴 막대 또는 앱의 ⌘O로도 저장소를 열 수 있습니다. 폴더 선택 창에서는 ⌘⇧G로 경로를 입력할 수 있습니다.",
    gitGetStarted: "빌드하고 확장 활성화하기 →",
    gitLimitsTitle: "현재 지원 범위",
    gitLimitsDescription:
      "로컬 저장소를 다루며 자동으로 push하지 않습니다. 이력을 변경하기 전에 작업 트리의 변경 사항을 처리해야 합니다. merge가 포함된 범위의 재적용과 merge 커밋의 cherry-pick은 지원하지 않습니다. 커밋과 브랜치 스냅샷을 비교할 수 있지만 인덱스와 작업 트리 비교는 아직 지원하지 않습니다. 원격 경고는 로컬에 알려진 참조를 사용하며 실시간 원격 상태를 나타내지 않습니다.",
  },
};

const demoItems = {
  "zh-Hans": {
    copy: ["复制绝对路径", "复制相对路径", "复制终端路径", "复制文件名"],
    open: [
      "GoLand",
      "Cursor",
      "Visual Studio Code",
      "WorkBuddy",
      "在终端中打开",
      "在 iTerm 中打开",
    ],
    new: ["文本文件", "Markdown", "JSON", "Swift", "Go"],
    send: ["复制到桌面", "移动到桌面", "复制到文稿", "复制到下载"],
    tools: ["拷贝 MD5", "拷贝 SHA256", "显示 / 隐藏", "按文件名新建文件夹"],
  },
  en: {
    copy: [
      "Copy Absolute Path",
      "Copy Relative Path",
      "Copy Shell Path",
      "Copy File Name",
    ],
    open: [
      "GoLand",
      "Cursor",
      "Visual Studio Code",
      "WorkBuddy",
      "Open in Terminal",
      "Open in iTerm",
    ],
    new: ["Text File", "Markdown", "JSON", "Swift", "Go"],
    send: [
      "Copy to Desktop",
      "Move to Desktop",
      "Copy to Documents",
      "Copy to Downloads",
    ],
    tools: [
      "Copy MD5",
      "Copy SHA256",
      "Show / Hide",
      "New Folder with File Name",
    ],
  },
  ja: {
    copy: [
      "絶対パスをコピー",
      "相対パスをコピー",
      "シェル用パスをコピー",
      "ファイル名をコピー",
    ],
    open: [
      "GoLand",
      "Cursor",
      "Visual Studio Code",
      "WorkBuddy",
      "ターミナルで開く",
      "iTermで開く",
    ],
    new: ["テキストファイル", "Markdown", "JSON", "Swift", "Go"],
    send: [
      "デスクトップにコピー",
      "デスクトップに移動",
      "書類にコピー",
      "ダウンロードにコピー",
    ],
    tools: [
      "MD5をコピー",
      "SHA256をコピー",
      "表示／非表示",
      "ファイル名でフォルダを作成",
    ],
  },
  ko: {
    copy: [
      "절대 경로 복사",
      "상대 경로 복사",
      "셸 경로 복사",
      "파일 이름 복사",
    ],
    open: [
      "GoLand",
      "Cursor",
      "Visual Studio Code",
      "WorkBuddy",
      "터미널에서 열기",
      "iTerm에서 열기",
    ],
    new: ["텍스트 파일", "Markdown", "JSON", "Swift", "Go"],
    send: [
      "데스크탑에 복사",
      "데스크탑으로 이동",
      "문서에 복사",
      "다운로드에 복사",
    ],
    tools: [
      "MD5 복사",
      "SHA256 복사",
      "표시 / 숨기기",
      "파일 이름으로 폴더 만들기",
    ],
  },
};

const languagePicker = document.getElementById("language");
const groupButtons = [...document.querySelectorAll("[data-group]")];
let currentLanguage = "zh-Hans";
let currentGroup = "copy";

function renderDemo() {
  const button = groupButtons.find(
    (item) => item.dataset.group === currentGroup,
  );
  document.getElementById("demo-title").textContent =
    button.querySelector("[data-i18n]").textContent;
  const items = demoItems[currentLanguage][currentGroup].map((label) => {
    const item = document.createElement("li");
    item.textContent = label;
    return item;
  });
  document.getElementById("demo-items").replaceChildren(...items);
  for (const item of groupButtons) {
    const selected = item.dataset.group === currentGroup;
    item.classList.toggle("selected", selected);
    item.setAttribute("aria-pressed", String(selected));
  }
}

const readmeFiles = {
  "zh-Hans": "README.md",
  en: "README.en.md",
  ja: "README.ja.md",
  ko: "README.ko.md",
};

function setLanguage(language) {
  currentLanguage = Object.hasOwn(translations, language) ? language : "en";
  const text = translations[currentLanguage];
  document.documentElement.lang = currentLanguage;
  languagePicker.value = currentLanguage;
  for (const element of document.querySelectorAll("[data-i18n]")) {
    element.textContent =
      text[element.dataset.i18n] ?? chinese[element.dataset.i18n];
  }
  document.title = `SuperMenu — ${text.heroLine1} ${text.heroLine2}`;
  for (const meta of document.querySelectorAll(
    'meta[name="description"], meta[property="og:description"]',
  )) {
    meta.content = text.heroDescription;
  }
  document.querySelector('[data-i18n="fullGuide"]').href =
    `https://github.com/openmacapp/supermenu/blob/master/${readmeFiles[currentLanguage]}#installation`;
  renderDemo();
}

function preferredLanguage() {
  try {
    const saved = localStorage.getItem("supermenu-language");
    if (Object.hasOwn(translations, saved)) return saved;
  } catch {
    /* Language switching also works when browser storage is unavailable. */
  }
  const browserLanguage = navigator.language.split("-")[0];
  return browserLanguage === "zh" ? "zh-Hans" : browserLanguage;
}

languagePicker.addEventListener("change", () => {
  setLanguage(languagePicker.value);
  try {
    localStorage.setItem("supermenu-language", currentLanguage);
  } catch {
    /* Optional preference only. */
  }
});
for (const button of groupButtons) {
  button.addEventListener("click", () => {
    currentGroup = button.dataset.group;
    renderDemo();
  });
}
setLanguage(preferredLanguage());
