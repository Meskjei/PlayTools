#!/bin/sh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/playtools-window-recording.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc "$root/AKPlugin.swift" "$root/Plugin.swift" "$root/WindowCaptureGeometry.swift" \
    "$root/Tests/WindowRecording/main.swift" -framework AppKit -o "$tmp/window-recording-test"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/window-recording-test"
"$tmp/window-recording-test" "$tmp/out.mp4"

# Regression guard: AKInterface.bundle's Info.plist uses '.AKPlugin', so NSBundle.principalClass
# relies on AKPlugin being the first Objective-C class in AKInterface's __objc_classlist.
mkdir -p "$tmp/AKInterface.bundle/Contents/MacOS"
cat > "$tmp/AKInterface.bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AKInterface</string>
    <key>CFBundleIdentifier</key><string>io.playcover.AKInterface</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>NSPrincipalClass</key><string>.AKPlugin</string>
</dict>
</plist>
PLIST
xcrun swiftc -emit-library -module-name AKInterface \
    "$root/AKPlugin.swift" "$root/Plugin.swift" "$root/WindowCaptureGeometry.swift" \
    -framework AppKit -o "$tmp/AKInterface.bundle/Contents/MacOS/AKInterface"
codesign --force --sign "${PLAYTOOLS_TEST_SIGN_IDENTITY:--}" "$tmp/AKInterface.bundle"
xcrun swift - "$tmp/AKInterface.bundle" <<'SWIFT'
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let bundle = Bundle(url: url)!
try! bundle.loadAndReturnError()
let cls: AnyClass = bundle.principalClass!
let name = NSStringFromClass(cls)
let proto = NSProtocolFromString("Plugin")!
precondition(name.hasSuffix(".AKPlugin"), "Expected AKPlugin principalClass, got \(name)")
precondition((cls as! NSObject.Type).conforms(to: proto), "AKPlugin must conform to @objc(Plugin)")
print("Bundle principalClass verified: \(name)")
SWIFT

python3 - "$tmp/out.mp4" <<'PY'
import json, subprocess, sys
mp4 = sys.argv[1]
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=codec_name,pix_fmt,width,height:frame=pts_time",
    "-of", "json", mp4
], text=True))
stream = probe["streams"][0]
assert stream["codec_name"] == "h264", stream
assert stream["width"] % 2 == 0 and stream["height"] % 2 == 0, stream
pts = [float(f["pts_time"]) for f in probe["frames"]]
assert len(pts) >= 5, f"Expected >=5 frames including static heartbeat, got {len(pts)}: {pts}"
assert abs(pts[0] - 0.0) < 1e-4, f"First frame PTS must start at 0, got {pts[0]}"
for a, b in zip(pts, pts[1:]):
    assert b > a, f"Non-monotonic PTS: {pts}"
    assert (b - a) < 0.55, f"Gap too large without idle heartbeat: {b - a}s in {pts}"

# Verify first frame top pixel is red (not macOS window titlebar gray) and bottom pixel is blue!
w, h = stream["width"], stream["height"]
raw = subprocess.check_output([
    "ffmpeg", "-v", "error", "-i", mp4, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
])
top_px = raw[(10 * w + w // 2) * 3 : (10 * w + w // 2) * 3 + 3]
bot_px = raw[((h - 10) * w + w // 2) * 3 : ((h - 10) * w + w // 2) * 3 + 3]
assert top_px[0] > 180 and top_px[1] < 80 and top_px[2] < 80, f"Top pixel included titlebar or wrong color: {list(top_px)}"
assert bot_px[2] > 180 and bot_px[0] < 80 and bot_px[1] < 80, f"Bottom pixel wrong color: {list(bot_px)}"
print(f"MP4 verified: {stream['width']}x{stream['height']} h264, {len(pts)} frames, pts=[{pts[0]:.3f}..{pts[-1]:.3f}], top={list(top_px)}, bot={list(bot_px)}")
PY
