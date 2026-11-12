import AppKit
import Foundation

final class SplitColorView: NSView {
    var swapped = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let topColor: NSColor = swapped ? .green : .red
        let bottomColor: NSColor = swapped ? .yellow : .blue
        topColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height / 2).fill()
        bottomColor.setFill()
        NSRect(x: 0, y: bounds.height / 2, width: bounds.width, height: bounds.height / 2).fill()
    }
}

guard #available(macOS 14.4, *) else {
    print("Skipping live WindowRecording test on macOS < 14.4")
    exit(0)
}

setbuf(stdout, nil)
print("STEP: start main")
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory() + "/window-rec-test.mp4"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(
    contentRect: NSRect(x: 140, y: 140, width: 200, height: 320),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
let view = SplitColorView(frame: NSRect(x: 0, y: 0, width: 200, height: 320))
window.contentView = view
window.orderFrontRegardless()
window.displayIfNeeded()

let plugin = AKPlugin()
precondition(plugin.supportsWindowRecording, "Host must support own-window recording")
print("STEP: plugin initialized")

// Reject sharingType == .none (FLAG_SECURE equivalent; use a dedicated window because macOS 27 latches .none)
do {
    let secureWindow = NSWindow(
        contentRect: NSRect(x: 40, y: 40, width: 120, height: 120),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    secureWindow.isReleasedWhenClosed = false
    secureWindow.orderFrontRegardless()
    secureWindow.sharingType = .none
    var secureRejected = false
    plugin.startWindowRecording(secureWindow, recordingId: "run_secure") { info, err in
        precondition(info == nil && err == "capture_secure_window")
        secureRejected = true
    }
    precondition(secureRejected)
    secureWindow.close()
}
print("STEP: secure guard verified")

DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
    print("STEP: calling startWindowRecording")
    plugin.startWindowRecording(window, recordingId: "run_live_1") { started, err in
        print("STEP: startWindowRecording callback err=\(err ?? "nil")")
        guard err == nil, let started = started as? [String: Any] else {
            fputs("startWindowRecording failed: \(err ?? "nil")\n", stderr)
            exit(1)
        }
        precondition((started["source"] as? String) == "playcover-own-window-h264")
        precondition((started["mediaType"] as? String) == "video/mp4")

        // Concurrent start must report recording_busy
        plugin.startWindowRecording(window, recordingId: "run_busy") { busyInfo, busyErr in
            precondition(busyInfo == nil && busyErr == "recording_busy")
        }

        // Hold static for 650ms so 200ms idle heartbeats emit frames, then swap colors, then stop!
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(650)) {
            view.swapped = true
            view.displayIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350)) {
                plugin.stopWindowRecording("run_live_1") { stopped, stopErr in
                    guard stopErr == nil, let stopped = stopped as? [String: Any],
                          let totalSize = stopped["size"] as? Int, totalSize > 0 else {
                        fputs("stopWindowRecording failed: \(stopErr ?? "nil")\n", stderr)
                        exit(1)
                    }
                    var assembled = Data()
                    var offset = 0
                    while offset < totalSize {
                        let part = plugin.readWindowRecording("run_live_1", offset: offset, maxLength: 64 * 1024) as? [String: Any] ?? [:]
                        guard part["error"] == nil,
                              let b64 = part["chunk"] as? String,
                              let chunk = Data(base64Encoded: b64), !chunk.isEmpty else {
                            fputs("readWindowRecording failed at \(offset): \(part)\n", stderr)
                            exit(1)
                        }
                        assembled.append(chunk)
                        offset += chunk.count
                    }
                    precondition(assembled.count == totalSize)
                    try! assembled.write(to: URL(fileURLWithPath: outPath))
                    let rel = plugin.releaseWindowRecording("run_live_1") as? [String: Any] ?? [:]
                    precondition((rel["released"] as? Bool) == true)
                    let afterRel = plugin.readWindowRecording("run_live_1", offset: 0, maxLength: 1024) as? [String: Any] ?? [:]
                    precondition((afterRel["error"] as? String) == "recording_not_found")
                    window.orderOut(nil)
                    print("Recorded \(assembled.count) bytes, width=\(stopped["width"] ?? 0), height=\(stopped["height"] ?? 0), durationMs=\(stopped["durationMs"] ?? 0)")
                    exit(0)
                }
            }
        }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(15)) {
    fputs("Timed out in WindowRecording test\n", stderr)
    exit(2)
}

app.run()
