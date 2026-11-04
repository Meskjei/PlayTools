#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build="$root/.build/QwenActivity"
mkdir -p "$build"
xcrun clang -std=c11 -Wall -Wextra -Werror "$root/Tests/QwenActivity/main.c" -o "$build/activity-test"
"$build/activity-test"
