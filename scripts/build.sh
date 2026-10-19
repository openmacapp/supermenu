#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
TARGET="arm64-apple-macosx14.0"
APP="$ROOT/dist/SuperMenu.app"
APPEX="$APP/Contents/PlugIns/SuperMenuFinderSync.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
mkdir -p "$APP/Contents/Resources" "$APPEX/Contents/Resources"

zsh "$ROOT/scripts/build-icons.sh" "$APP/Contents/Resources"
cp "$APP/Contents/Resources/"*.png "$APPEX/Contents/Resources/"
cp "$APP/Contents/Resources/AppIcon.icns" "$APPEX/Contents/Resources/"
for language in en zh-Hans ja ko; do
  for resources in "$APP/Contents/Resources" "$APPEX/Contents/Resources"; do
    mkdir -p "$resources/$language.lproj"
    cp "$ROOT/Sources/SuperMenuCore/Resources/$language.lproj/Localizable.strings" "$resources/$language.lproj/"
    cp "$ROOT/App/Resources/$language.lproj/InfoPlist.strings" "$resources/$language.lproj/"
  done
  cp "$ROOT/App/Resources/$language.lproj/ServicesMenu.strings" "$APP/Contents/Resources/$language.lproj/"
done

COMMON=(
  -parse-as-library
  -target "$TARGET"
  -sdk "$SDK"
  -O
  -framework AppKit
  -framework FinderSync
)

# Build only the Git library, never Gitify's application / Sparkle framework.
swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --product SuperMenuGit
GIT_BUILD="$(swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --show-bin-path)"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp -R "$ROOT/ThirdPartyLicenses" "$APP/Contents/Resources/ThirdPartyLicenses"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

swiftc "${COMMON[@]}" \
  -I "$GIT_BUILD/Modules" -L "$GIT_BUILD" -lSuperMenuGit \
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
