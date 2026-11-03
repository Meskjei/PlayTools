#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${PLAYTOOLS_TEST_BUILD_DIR:-"$root/.build/ShangouMotion"}
mkdir -p "$tmp"
xcrun clang -fobjc-arc -framework Foundation "$root/Tests/ShangouMotion/main.m" -o "$tmp/motion-test"
# Keep the compiler's signature, as in the Discord fixture; no injected libraries.
"$tmp/motion-test"
