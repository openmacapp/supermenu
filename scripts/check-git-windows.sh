#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Example GIT_COMMITTER_NAME=Example
export GIT_AUTHOR_EMAIL=example@example.invalid GIT_COMMITTER_EMAIL=example@example.invalid
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
TARGET="arm64-apple-macosx14.0"
swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --product SuperMenuGit
GIT_BUILD="$(swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --show-bin-path)"
APP="$WORK/WindowChecks.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources" "$WORK/repository"
cp -R "$ROOT/Sources/SuperMenuCore/Resources/"* "$APP/Resources/"
git -C "$WORK/repository" init -q
mkdir -p "$WORK/repository/Sources" "$WORK/repository/docs"
for message in Initial Second; do
  print -rl -- "// $message synthetic revision" "let message = \"$message\"" > "$WORK/repository/Sources/Example.swift"
  print -rl -- "# $message" > "$WORK/repository/docs/Example.md"
  git -C "$WORK/repository" add -- Sources docs
  git -C "$WORK/repository" -c user.name=Example \
    -c user.email=example@example.invalid commit -q --allow-empty -m "$message"
done
APP_SOURCES=("$ROOT"/App/*.swift)
APP_SOURCES=("${(@)APP_SOURCES:#*/SuperMenuApp.swift}")
swiftc -parse-as-library -target "$TARGET" -sdk "$SDK" -O \
  -I "$GIT_BUILD/Modules" -L "$GIT_BUILD" -lSuperMenuGit \
  -framework AppKit -framework SwiftUI -framework FinderSync \
  -o "$APP/MacOS/WindowChecks" \
  "$ROOT"/Sources/SuperMenuCore/*.swift "$ROOT"/Host/*.swift \
  "${APP_SOURCES[@]}" "$ROOT/Tests/WindowChecks/main.swift"
"$APP/MacOS/WindowChecks" "$WORK/repository"
