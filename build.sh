#!/bin/zsh
# Builds WinSnap.app next to this script. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
FLAGS=()
# Some Command Line Tools installs keep a stale module.modulemap that redefines SwiftBridging
# and breaks every AppKit import. Hide it with a VFS overlay rather than requiring sudo.
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [[ -f "$STALE" && -f "${STALE:h}/bridging.modulemap" ]]; then
    : > build/empty.modulemap
    cat > build/overlay.yaml <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "file",
  "name": "$STALE", "external-contents": "$PWD/build/empty.modulemap" } ] }
EOF
    FLAGS=(-vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc build/overlay.yaml)
fi

swiftc -O -target "$(uname -m)-apple-macosx13.0" "${FLAGS[@]}" Sources/WinSnap/*.swift -o build/WinSnap
BIN=build/WinSnap

APP="WinSnap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WinSnap"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WinSnap</string>
    <key>CFBundleDisplayName</key><string>WinSnap</string>
    <key>CFBundleIdentifier</key><string>com.winsnap.app</string>
    <key>CFBundleExecutable</key><string>WinSnap</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS can track the Accessibility permission.
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x WinSnap 2>/dev/null || true
    rm -rf /Applications/WinSnap.app
    cp -R "$APP" /Applications/
    open /Applications/WinSnap.app
    echo "Installed to /Applications and launched"
fi
