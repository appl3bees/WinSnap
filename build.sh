#!/bin/zsh
# Builds WinSnap.app next to this script. Usage: ./build.sh [--install | --test]
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

if [[ "${1:-}" == "--test" ]]; then
    # Same as `swift test`, for Command Line Tools installs whose SwiftPM can't load Package.swift:
    # compile the app and tests as one module and run them with Swift Testing's own entry point.
    FW=()
    for dir in /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
               "$(xcrun --show-sdk-platform-path 2>/dev/null)/Developer/Library/Frameworks"; do
        [[ -d "$dir/Testing.framework" ]] && FW+=(-F "$dir" -Xlinker -rpath -Xlinker "$dir")
    done
    SOURCES=(Sources/WinSnap/*.swift)
    SOURCES=(${SOURCES:#*/main.swift})
    print 'import Testing
@main struct TestRunner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }' > build/TestRunner.swift
    swiftc -module-name WinSnap -parse-as-library -D WINSNAP_SINGLE_MODULE_TESTS \
        -target "$(uname -m)-apple-macosx13.0" "${FLAGS[@]}" "${FW[@]}" \
        "${SOURCES[@]}" Tests/WinSnapTests/*.swift build/TestRunner.swift -o build/WinSnapTests
    exec build/WinSnapTests
fi

# WINSNAP_UNIVERSAL=1 builds for both Apple silicon and Intel, as release downloads need.
ARCHS=("$(uname -m)")
[[ "${WINSNAP_UNIVERSAL:-}" == 1 ]] && ARCHS=(arm64 x86_64)
for arch in "${ARCHS[@]}"; do
    swiftc -O -target "$arch-apple-macosx13.0" "${FLAGS[@]}" Sources/WinSnap/*.swift -o "build/WinSnap-$arch"
done
BIN=build/WinSnap
lipo -create build/WinSnap-${^ARCHS} -output "$BIN"

# Release builds pass the tag's version, e.g. WINSNAP_VERSION=1.2.0.
VERSION="${WINSNAP_VERSION:-1.0}"

APP="WinSnap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WinSnap"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WinSnap</string>
    <key>CFBundleDisplayName</key><string>WinSnap</string>
    <key>CFBundleIdentifier</key><string>com.winsnap.app</string>
    <key>CFBundleExecutable</key><string>WinSnap</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# macOS ties the Accessibility permission to the signature's designated requirement. An ad-hoc one is
# the binary's hash, so every rebuild loses access; a certificate keeps the same requirement.
IDENTITY="${WINSNAP_SIGN_IDENTITY:-WinSnap Self-Signed}"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP"
    echo "warning: signed ad-hoc, so macOS will drop Accessibility access after each rebuild." >&2
    echo "         Run scripts/create-signing-cert.sh once to keep it." >&2
fi
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x WinSnap 2>/dev/null || true
    rm -rf /Applications/WinSnap.app
    cp -R "$APP" /Applications/
    open /Applications/WinSnap.app
    echo "Installed to /Applications and launched"
fi
