#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/SuperMenu.app"
DEST="$HOME/Applications/SuperMenu.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$APP" ]]; then
  echo "先运行 scripts/build.sh" >&2
  exit 1
fi

# Read the installed identity so upgrades can also quit a renamed application.
if [[ -f "$DEST/Contents/Info.plist" ]]; then
  INSTALLED_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
  if [[ "$INSTALLED_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    osascript -e "tell application id \"$INSTALLED_ID\" to quit" >/dev/null 2>&1 || true
  fi
fi
sleep 0.4
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
codesign --force --sign - --entitlements "$ROOT/Extension/FinderSync.entitlements" "$DEST/Contents/PlugIns/SuperMenuFinderSync.appex"
codesign --force --sign - "$DEST"
"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/SuperMenuFinderSync.appex" || true
echo "Installed $DEST"
