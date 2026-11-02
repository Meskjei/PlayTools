#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${PLAYTOOLS_TEST_BUILD_DIR:-"$root/.build/DiscordSession"}
mkdir -p "$tmp"
xcrun swiftc -swift-version 5 -emit-library -static -emit-module -module-name SwordRPC "$root/Tests/DiscordSession/SwordRPC.swift" -emit-module-path "$tmp/SwordRPC.swiftmodule" -o "$tmp/libSwordRPC.a"
xcrun swiftc -swift-version 5 -parse-as-library -I "$tmp" -L "$tmp" -lSwordRPC "$root/PlayTools/DiscordActivity/DiscordActivity.swift" "$root/PlayTools/DiscordActivity/DiscordIPC.swift" "$root/Tests/DiscordSession/main.swift" -o "$tmp/discord-session-test"
# swiftc signs the local executable; no injected dynamic library or re-signing is needed.
TOUCHSTONE_AUTOMATION_TOKEN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$tmp/discord-session-test" automation
TOUCHSTONE_AUTOMATION_TOKEN='' "$tmp/discord-session-test" empty-marker
env -u TOUCHSTONE_AUTOMATION_TOKEN "$tmp/discord-session-test" standalone
env -u TOUCHSTONE_AUTOMATION_TOKEN "$tmp/discord-session-test" disabled
