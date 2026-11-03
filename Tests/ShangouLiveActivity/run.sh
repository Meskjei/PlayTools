#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build=${PLAYTOOLS_TEST_BUILD_DIR:-"$root/.build/ShangouLiveActivity"}
mkdir -p "$build"
xcrun clang -fblocks -framework Foundation "$root/Tests/ShangouLiveActivity/main.m" -o "$build/activity-test"
"$build/activity-test"
