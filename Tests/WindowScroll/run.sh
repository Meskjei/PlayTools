#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-scroll-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -emit-library -emit-module -module-name UIKit "$root/Tests/WindowScroll/UIKit.swift" -emit-module-path "$tmp/UIKit.swiftmodule" -o "$tmp/libUIKit.dylib"
xcrun swiftc -I "$tmp" -L "$tmp" -lUIKit "$root/PlayTools/Controls/Frontend/EventAdapter/Mouse/WindowMouseScroll.swift" "$root/Tests/WindowScroll/main.swift" -o "$tmp/scroll-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/libUIKit.dylib"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/scroll-test"
DYLD_LIBRARY_PATH="$tmp" "$tmp/scroll-test"
