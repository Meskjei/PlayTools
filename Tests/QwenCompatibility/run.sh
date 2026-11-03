#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-qwen-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun clang -std=c11 -Wall -Wextra -Werror Tests/QwenCompatibility/main.c -o "$tmp/qwen-compat-test"
if [ -n "${PLAYTOOLS_TEST_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$PLAYTOOLS_TEST_SIGN_IDENTITY" "$tmp/qwen-compat-test"
fi
"$tmp/qwen-compat-test"
