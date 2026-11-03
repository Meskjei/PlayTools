#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-tab-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun clang -fobjc-arc -framework Foundation -framework CoreGraphics "$root/Tests/ShangouTab/main.m" -o "$tmp/tab-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/tab-test"
"$tmp/tab-test"
