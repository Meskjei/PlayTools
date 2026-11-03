#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-window-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc "$root/WindowCaptureGeometry.swift" "$root/Tests/WindowCapture/main.swift" -o "$tmp/window-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/window-test"
"$tmp/window-test"
