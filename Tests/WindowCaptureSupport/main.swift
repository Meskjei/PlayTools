import AppKit
import ScreenCaptureKit

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
