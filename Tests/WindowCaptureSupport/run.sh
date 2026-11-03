#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-capture-support.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc "$root/AKPlugin.swift" "$root/Plugin.swift" "$root/WindowCaptureGeometry.swift" \
    "$root/Tests/WindowCaptureSupport/main.swift" -framework AppKit -o "$tmp/capture-support-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/capture-support-test"
"$tmp/capture-support-test"
