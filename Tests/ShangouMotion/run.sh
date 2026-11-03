#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-motion-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun clang -fobjc-arc -framework Foundation "$root/Tests/ShangouMotion/main.m" -o "$tmp/motion-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/motion-test"
"$tmp/motion-test"
