import AppKit
import ScreenCaptureKit

// A 390pt AppKit window can be 506pt in Catalyst. Fit UIKit's phone canvas, not a second unrelated rectangle.
let phone = fittedPhoneViewportSize(available: CGSize(width: 2000, height: 1500), content: CGSize(width: 390, height: 844), logical: CGSize(width: 506, height: 1095.0153846153846))!
precondition(abs(phone.width - 300.59288537549406) < 0.01)
precondition(abs(phone.height / phone.width - 844.0 / 390.0) < 0.001)
precondition(fittedPhoneViewportSize(available: .zero, content: CGSize(width: 390, height: 844), logical: CGSize(width: 390, height: 844)) == nil)
precondition(fittedPhoneViewportSize(available: CGSize(width: 1000, height: 1000), content: CGSize(width: 390, height: 844), logical: .zero) == nil)

class OldShareableContent: NSObject {}

class CurrentShareableContent: NSObject {
    @objc(getCurrentProcessShareableContentWithCompletionHandler:)
    class func currentProcess(_ completion: AnyObject) {
        preconditionFailure("Capability probing must not start a capture")
    }
}

class ScreenshotManager: NSObject {
    @objc(captureImageWithFilter:configuration:completionHandler:)
    class func capture(_ filter: AnyObject, configuration: AnyObject, completion: AnyObject) {
        preconditionFailure("Capability probing must not start a capture")
    }
}

precondition(!WindowCaptureSupport.hasRequiredMethods(shareableContent: nil, screenshotManager: ScreenshotManager.self))
precondition(!WindowCaptureSupport.hasRequiredMethods(shareableContent: CurrentShareableContent.self, screenshotManager: nil))
// macOS 14.2.1 has ScreenCaptureKit, but lacks the current-process selector that caused the crash.
precondition(!WindowCaptureSupport.hasRequiredMethods(shareableContent: OldShareableContent.self, screenshotManager: ScreenshotManager.self))
precondition(!WindowCaptureSupport.hasRequiredMethods(shareableContent: CurrentShareableContent.self, screenshotManager: NSObject.self))
precondition(WindowCaptureSupport.hasRequiredMethods(shareableContent: CurrentShareableContent.self, screenshotManager: ScreenshotManager.self))
if #available(macOS 14.4, *) {
    precondition(WindowCaptureSupport.isAvailable == WindowCaptureSupport.hasRequiredMethods(
        shareableContent: NSClassFromString("SCShareableContent"), screenshotManager: NSClassFromString("SCScreenshotManager")))
} else {
    precondition(!WindowCaptureSupport.isAvailable)
}
print("Window capture capability checks passed (host compositor available: \(WindowCaptureSupport.isAvailable))")

class LegacyCapturePlugin: AKPlugin {
    override var supportsWindowCapture: Bool { false }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.makeKeyAndOrderFront(nil)
defer { window.orderOut(nil) }
let plugin = LegacyCapturePlugin()
var rejected = false
plugin.captureWindow(window) { png, error in
    precondition(png == nil && error == "capture_window_unavailable")
    rejected = true
}
precondition(rejected, "Direct capture must reject unavailable APIs before starting an asynchronous capture")
print("Direct capture respects the unsupported-runtime guard")

// Recording geometry & selector guards
let sourceRect = windowRecordingSourceRect(frameSize: CGSize(width: 390, height: 872),
                                           contentRect: CGRect(x: 0, y: 0, width: 390, height: 844))!
precondition(sourceRect == CGRect(x: 0, y: 28, width: 390, height: 844))
precondition(evenRecordingPixelDimension(780) == 780)
precondition(evenRecordingPixelDimension(781) == 780)
precondition(evenRecordingPixelDimension(1) == nil)
precondition(WindowRecordingSupport.isValidRecordingId("run_abc-123"))
precondition(!WindowRecordingSupport.isValidRecordingId("../escape"))

precondition(!WindowRecordingSupport.hasRequiredMethods(
    shareableContent: OldShareableContent.self,
    contentFilter: NSClassFromString("SCContentFilter"),
    streamClass: NSClassFromString("SCStream"),
    assetWriter: NSClassFromString("AVAssetWriter")
))
precondition(!WindowRecordingSupport.hasRequiredMethods(
    shareableContent: CurrentShareableContent.self,
    contentFilter: NSObject.self,
    streamClass: NSClassFromString("SCStream"),
    assetWriter: NSClassFromString("AVAssetWriter")
))
if #available(macOS 14.4, *) {
    precondition(WindowRecordingSupport.isAvailable)
}

class LegacyRecordingPlugin: AKPlugin {
    override var supportsWindowRecording: Bool { false }
}
let legacyRec = LegacyRecordingPlugin()
var recRejected = false
legacyRec.startWindowRecording(window, recordingId: "run_legacy") { info, error in
    precondition(info == nil && error == "recording_unsupported")
    recRejected = true
}
precondition(recRejected, "Direct recording must reject unavailable APIs synchronously")
print("Window recording capability checks passed")
