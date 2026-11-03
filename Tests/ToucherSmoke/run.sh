#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-touch-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -emit-library -emit-module -module-name UIKit "$root/Tests/ToucherSmoke/UIKit.swift" -emit-module-path "$tmp/UIKit.swiftmodule" -o "$tmp/libUIKit.dylib"
xcrun swiftc -I "$tmp" -L "$tmp" -lUIKit "$root/PlayTools/Controls/Backend/Toucher.swift" "$root/Tests/ToucherSmoke/main.swift" -o "$tmp/touch-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/libUIKit.dylib"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/touch-test"
DYLD_LIBRARY_PATH="$tmp" "$tmp/touch-test"
