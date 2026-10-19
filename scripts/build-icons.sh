#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="${1:?Usage: build-icons.sh <bundle-resources-directory>}"
SOURCE="$ROOT/App/Resources"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" "$RESOURCES"

# Keep the image-tool originals; derive every macOS size at build time.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE/AppIconSource.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$SOURCE/AppIconSource.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

sips -z 18 18 "$SOURCE/MenuBarSource.png" --out "$RESOURCES/MenuBarTemplate.png" >/dev/null
sips -z 36 36 "$SOURCE/MenuBarSource.png" --out "$RESOURCES/MenuBarTemplate@2x.png" >/dev/null
