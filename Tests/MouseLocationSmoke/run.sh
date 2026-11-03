#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/playtools-mouse-test.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
app_dir="$tmp_dir/MouseTest.app"
mkdir -p "$app_dir/Contents/MacOS"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>MouseTest</string><key>CFBundleIdentifier</key><string>io.playcover.tests.mouse-location</string><key>CFBundleName</key><string>Mouse Location Test</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc AKPlugin.swift Plugin.swift WindowCaptureGeometry.swift Tests/MouseLocationSmoke/main.swift -framework AppKit -o "$app_dir/Contents/MacOS/MouseTest"
if [ -n "${PLAYTOOLS_TEST_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$PLAYTOOLS_TEST_SIGN_IDENTITY" "$app_dir"
fi
echo "Launch $app_dir to run the smoke test, then press Return to remove it."
read -r _
