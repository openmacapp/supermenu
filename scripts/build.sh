#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
TARGET="arm64-apple-macosx14.0"
APP="$ROOT/dist/SuperMenu.app"
APPEX="$APP/Contents/PlugIns/SuperMenuFinderSync.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"

COMMON=(
  -parse-as-library
  -target "$TARGET"
  -sdk "$SDK"
  -O
  -framework AppKit
  -framework FinderSync
)

swiftc "${COMMON[@]}" \
  -framework SwiftUI \
  -o "$APP/Contents/MacOS/SuperMenu" \
  "$ROOT"/Sources/SuperMenuCore/*.swift \
  "$ROOT"/Host/*.swift \
  "$ROOT"/App/*.swift

cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

swiftc "${COMMON[@]}" \
  -module-name SuperMenuFinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/SuperMenuFinderSync" \
  "$ROOT"/Sources/SuperMenuCore/*.swift \
  "$ROOT"/Host/*.swift \
  "$ROOT"/Extension/*.swift

cp "$ROOT/Extension/Info.plist" "$APPEX/Contents/Info.plist"
codesign --force --sign - --entitlements "$ROOT/Extension/FinderSync.entitlements" "$APPEX"
codesign --force --sign - "$APP"
echo "Built $APP"
