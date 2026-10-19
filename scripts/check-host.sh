#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/HostChecks.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"
cp -R "$ROOT/Sources/SuperMenuCore/Resources/"* "$APP/Resources/"
swiftc -o "$APP/MacOS/HostChecks" \
  "$ROOT"/Sources/SuperMenuCore/*.swift \
  "$ROOT"/Host/*.swift \
  "$ROOT/Tests/HostChecks/main.swift"
"$APP/MacOS/HostChecks"
