#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
TARGET="arm64-apple-macosx14.0"
swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --product SuperMenuGit
GIT_BUILD="$(swift build --package-path "$ROOT" --build-system native --sdk "$SDK" --triple "$TARGET" -c release --show-bin-path)"
swiftc -target "$TARGET" -sdk "$SDK" -O \
  -I "$GIT_BUILD/Modules" -L "$GIT_BUILD" -lSuperMenuGit \
  -o "$WORK/BadgeChecks" \
  "$ROOT"/Sources/SuperMenuCore/*.swift \
  "$ROOT/App/GitBadgeService.swift" "$ROOT/App/GitBadgeWatcher.swift" \
  "$ROOT/Tests/BadgeChecks/main.swift"
"$WORK/BadgeChecks"

# Exercise the same code through a signed App Sandbox client. No developer
# certificate, network permission or persistent data exchange is required.
python3 - "$WORK" "$ROOT" <<'PYTEST'
import pathlib, plistlib, shutil, subprocess, sys, time, uuid
work, root = map(pathlib.Path, sys.argv[1:])
service = 'org.example.badges.' + str(uuid.uuid4())
repo = work / 'fixture'
repo.mkdir()
subprocess.run(['/usr/bin/git', 'init', '-q', str(repo)], check=True)
(repo / 'untracked.txt').write_text('synthetic')
bundle = work / 'SandboxProbe.app'
(bundle / 'Contents/MacOS').mkdir(parents=True)
shutil.copy2(work / 'BadgeChecks', bundle / 'Contents/MacOS/BadgeChecks')
(bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'org.example.SuperMenuBadgeChecks',
    'CFBundleExecutable': 'BadgeChecks', 'CFBundlePackageType': 'APPL'}))
entitlements = plistlib.loads((root / 'Extension/FinderSync.entitlements').read_bytes())
entitlements['com.apple.security.temporary-exception.mach-lookup.global-name'] = [service]
(work / 'client.entitlements').write_bytes(plistlib.dumps(entitlements))
subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(work / 'client.entitlements'), str(bundle)], check=True)
server = subprocess.Popen([str(work / 'BadgeChecks'), '--serve', service])
try:
    time.sleep(.3)
    clients = [subprocess.Popen([str(bundle / 'Contents/MacOS/BadgeChecks'), '--probe', service, str(repo / 'untracked.txt')]) for _ in range(2)]
    for client in clients:
        if client.wait(timeout=20) != 0:
            raise RuntimeError('sandboxed client failed')
finally:
    server.terminate()
    server.wait(timeout=10)
PYTEST
