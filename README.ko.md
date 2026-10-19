<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <strong>한국어</strong>
</p>

<p align="center">
  <img src="site/assets/app-icon.png" width="112" alt="SuperMenu 아이콘">
</p>

<h1 align="center">SuperMenu</h1>

<p align="center">자주 쓰는 파일 작업을 오른쪽 클릭 메뉴에서.</p>
<p align="center">
  <a href="https://openmacapp.github.io/supermenu/">웹사이트</a> ·
  <a href="#installation">설치</a> ·
  <a href="https://github.com/openmacapp/supermenu/issues">문제 신고</a> ·
  <a href="LICENSE">GPL v2</a>
</p>

SuperMenu는 macOS용 네이티브 Finder 확장 프로그램입니다. 파일이나 폴더를 선택하고 오른쪽 클릭 메뉴의 **SuperMenu**에서 경로 복사, 편집기로 열기, 파일 만들기 및 정리 작업을 수행할 수 있습니다. 작업은 용도별로 다섯 그룹에 정리되어 있으며, 필요 없는 항목은 설정에서 끌 수 있습니다.

중국어 간체, 일본어, 한국어, 영어를 지원합니다. 시스템 언어를 따르거나 앱에서 직접 언어를 선택할 수 있습니다.

README 언어는 페이지 상단의 링크로 전환하세요. 앱 언어는 SuperMenu 설정에서, 웹사이트 언어는 페이지 오른쪽 위의 선택 메뉴에서 변경할 수 있습니다.

## 기능

| 그룹          | 작업                                                                                                      |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| 정보 복사     | 절대 경로, 상대 경로, 셸에서 사용할 수 있도록 따옴표로 이스케이프한 경로, 파일 이름, 확장자를 제외한 이름 |
| 다음으로 열기 | VS Code, GoLand, Cursor, WorkBuddy 지원, 다른 앱 추가, 터미널이나 iTerm에서 폴더 열기                     |
| 새 파일       | 텍스트, Markdown, JSON, Swift, Go 파일 생성 및 이름 중복 자동 방지                                        |
| 보내기        | 데스크탑, 문서, 다운로드 등 설정된 폴더로 복사 또는 이동                                                  |
| 파일 도구     | MD5 / SHA256 체크섬, 표시 / 숨기기, 파일 이름으로 폴더 만들기                                             |

- 상대 경로는 기본적으로 Git 저장소 루트를 기준으로 하며, 저장소 밖에서는 현재 Finder 폴더를 사용합니다. 우선 사용할 프로젝트 루트를 설정할 수도 있습니다.
- 설치된 앱은 원래 아이콘으로 표시됩니다. 사용할 수 없는 앱은 메뉴에서 실행할 수 없습니다.
- 메뉴 막대에서도 Finder의 선택 항목을 작업할 수 있습니다. 앱에는 언어, 메뉴, 다음으로 열기, 경로, 앱 정보 설정이 있습니다.

<a id="installation"></a>

## 설치

현재 **소스 빌드**를 제공합니다. 사전 빌드된 설치 파일은 아직 배포하지 않습니다.

요구 사항: **Apple Silicon Mac, macOS 14 이상, Xcode Command Line Tools**. 현재 빌드 스크립트는 `arm64` 앱을 생성하며, Intel 빌드는 제공하지 않습니다.

개발 도구가 없다면 아래 명령을 실행하고 시스템의 설치 안내를 완료하세요.

```sh
xcode-select --install
```

그런 다음 빌드하고 설치합니다.

```sh
git clone https://github.com/openmacapp/supermenu.git
cd supermenu
zsh scripts/build.sh
zsh scripts/install.sh
open "$HOME/Applications/SuperMenu.app"
```

빌드 결과는 `dist/SuperMenu.app`에 생성되며, 앱은 `~/Applications/SuperMenu.app`에 설치됩니다. 설치 스크립트를 다시 실행하면 이 위치의 이전 앱이 교체됩니다. 스크립트는 로컬 ad-hoc 서명을 사용합니다. Developer ID로 서명하거나 공증한 배포 패키지가 아닙니다.

### Finder 확장 활성화

1. SuperMenu의 **활성화** 페이지에서 **Finder 확장 프로그램 설정 열기**를 클릭합니다.
2. macOS 시스템 설정에서 SuperMenu 확장을 활성화한 후, 앱으로 돌아와 상태가 **활성화됨**인지 확인합니다.
3. Finder에서 파일, 폴더 또는 창의 빈 공간을 오른쪽 클릭하고 **SuperMenu**를 찾습니다.

메뉴 막대 기능은 Finder에서 현재 선택한 항목을 읽어야 합니다. 처음 요청할 때 SuperMenu의 Finder 제어를 허용하세요. 이전에 거부했다면 **시스템 설정 → 개인정보 보호 및 보안 → 자동화**에서 변경할 수 있습니다. Finder 확장 활성화와 이 자동화 권한은 별개의 설정입니다.

시스템 서비스 메뉴, 권한 요청, 시스템에 표시되는 앱 이름은 macOS 언어를 따릅니다. 앱의 언어 설정은 설정 화면과 오른쪽 클릭 메뉴에 적용됩니다.

## 개발 및 검증

```sh
swift test                  # 코어 로직, 설정 호환성, 4개 언어 리소스, 메뉴 그룹
zsh scripts/check-host.sh   # Finder 메뉴 tag 기반 실행 및 메뉴 재생성 후 명령 매핑
zsh scripts/build.sh        # 앱과 확장 컴파일, 아이콘과 번역 패키징
```

`swift test`는 실제 Finder 클릭 동작을 검증하지 않습니다. 확장이나 앱 실행 로직을 변경했다면 빌드 결과를 설치하고 Finder에서 파일, 폴더, 빈 공간 및 대상 앱의 동작을 확인하세요.

| 경로                     | 역할                                                  |
| ------------------------ | ----------------------------------------------------- |
| `App/`                   | SwiftUI 설정, 앱 정보 창, 메뉴 막대, 시스템 서비스    |
| `Extension/`             | FinderSync 연동 및 메뉴 콜백                          |
| `Host/`                  | AppKit 아이콘, 앱 탐색, 명령 실행                     |
| `Sources/SuperMenuCore/` | 메뉴 모델, 파일 작업, 설정, 현지화 리소스             |
| `Tests/`                 | 코어 단위 테스트 및 Host 메뉴 검사                    |
| `scripts/`               | 빌드, 아이콘 패키징, 설치, 검증                       |
| `site/`                  | 프레임워크를 사용하지 않는 GitHub Pages 정적 웹사이트 |

메인 앱 설정은 `~/Library/Application Support/SuperMenu/config.json`에 저장됩니다. 가능한 한 설정 화면에서 변경하세요. 문제를 신고할 때는 개인 경로 등 관련 없는 정보를 제거해 주세요.

### 웹사이트 유지보수

```sh
python3 -m http.server 8080 --directory site
```

`http://localhost:8080`을 엽니다. 페이지 구조, 스타일, 4개 언어 문구는 각각 `site/index.html`, `site/styles.css`, `site/site.js`에 있습니다. Node.js나 프런트엔드 빌드 도구는 필요하지 않습니다. 아이콘은 앱과 같은 디자인을 사용합니다.

`.github/workflows/pages.yml`은 `master`에서 관련 파일이 변경되면 `site/`를 배포하며, 수동 실행도 지원합니다. GitHub 저장소의 Pages 배포 소스는 **GitHub Actions**로 설정하세요.

## 피드백 및 기여

버그나 개선 제안은 [Issues](https://github.com/openmacapp/supermenu/issues)에 남겨 주세요. macOS 버전, 앱 버전, 사용한 진입점, 파일과 폴더 중 무엇을 선택했는지, 예상 결과와 실제 결과를 포함해 주세요. 코드를 제출하기 전에 관련 검사를 실행하고, 네 언어의 현지화 키를 일치시켜 주세요.

기능, 설치 절차 또는 제한 사항을 변경할 때는 `README.md`, `README.en.md`, `README.ja.md`, `README.ko.md`를 함께 업데이트해 주세요. 언어별 문서의 섹션 구조, 명령, 링크 대상을 일치시켜 주세요.

[GNU GPL v2](LICENSE) 라이선스를 따릅니다.
