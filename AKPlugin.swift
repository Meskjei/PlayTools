//
//  MacPlugin.swift
//  AKInterface
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ObjectiveC.runtime
import ScreenCaptureKit

enum WindowCaptureSupport {
    static var isAvailable: Bool {
        guard #available(macOS 14.4, *) else { return false }
        return hasRequiredMethods(shareableContent: NSClassFromString("SCShareableContent"),
                                  screenshotManager: NSClassFromString("SCScreenshotManager"))
    }

    static func hasRequiredMethods(shareableContent: AnyClass?, screenshotManager: AnyClass?) -> Bool {
        guard let shareableContent = shareableContent, let screenshotManager = screenshotManager else { return false }
        // Injected iOS apps can pass the OS version check even when the host lacks this selector.
        return class_getClassMethod(shareableContent,
            NSSelectorFromString("getCurrentProcessShareableContentWithCompletionHandler:")) != nil &&
            class_getClassMethod(screenshotManager,
            NSSelectorFromString("captureImageWithFilter:configuration:completionHandler:")) != nil
    }
}

enum WindowRecordingSupport {
    static var isAvailable: Bool {
        guard #available(macOS 14.4, *) else { return false }
        return hasRequiredMethods(shareableContent: NSClassFromString("SCShareableContent"),
                                  contentFilter: NSClassFromString("SCContentFilter"),
                                  streamClass: NSClassFromString("SCStream"),
                                  assetWriter: NSClassFromString("AVAssetWriter"))
    }

    static func hasRequiredMethods(shareableContent: AnyClass?,
                                   contentFilter: AnyClass?,
                                   streamClass: AnyClass?,
                                   assetWriter: AnyClass?) -> Bool {
        guard let shareableContent = shareableContent,
              let contentFilter = contentFilter,
              let streamClass = streamClass,
              let assetWriter = assetWriter else { return false }
        return class_getClassMethod(shareableContent,
            NSSelectorFromString("getCurrentProcessShareableContentWithCompletionHandler:")) != nil &&
            class_getInstanceMethod(contentFilter,
            NSSelectorFromString("initWithDesktopIndependentWindow:")) != nil &&
            class_getInstanceMethod(streamClass,
            NSSelectorFromString("initWithFilter:configuration:delegate:")) != nil &&
            class_getInstanceMethod(streamClass,
            NSSelectorFromString("addStreamOutput:type:sampleHandlerQueue:error:")) != nil &&
            class_getInstanceMethod(streamClass,
            NSSelectorFromString("startCaptureWithCompletionHandler:")) != nil &&
            class_getInstanceMethod(streamClass,
            NSSelectorFromString("stopCaptureWithCompletionHandler:")) != nil &&
            class_getInstanceMethod(assetWriter,
            NSSelectorFromString("initWithURL:fileType:error:")) != nil
    }

    static func isValidRecordingId(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 100 else { return false }
        return value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) ||
            (byte >= 65 && byte <= 90) ||
            (byte >= 97 && byte <= 122) ||
            byte == 45 || byte == 95
        }
    }
}

// Add a lightweight struct so we can decode only the flag we care about
private struct AKAppSettingsData: Codable {
    var hideTitleBar: Bool?
    var floatingWindow: Bool?
    var resolution: Int?
    var resizableAspectRatioWidth: Int?
    var resizableAspectRatioHeight: Int?
}

// UIKit-on-Mac can consult the current cursor instead of the mouse event being dispatched.
private enum MouseEventLocation {
    static var current: NSEvent?

    static let install: Void = {
        guard let sendEvent = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.sendEvent(_:))),
              let scopedSendEvent = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.playToolsSendEvent(_:))),
              let mouseLocation = class_getInstanceMethod(NSWindow.self, #selector(getter: NSWindow.mouseLocationOutsideOfEventStream)),
              let scopedMouseLocation = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.playToolsMouseLocation)) else { return }
        method_exchangeImplementations(sendEvent, scopedSendEvent)
        method_exchangeImplementations(mouseLocation, scopedMouseLocation)
    }()
}

private extension NSApplication {
    @objc dynamic func playToolsSendEvent(_ event: NSEvent) {
        let previous = MouseEventLocation.current
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel:
            MouseEventLocation.current = event
        default:
            MouseEventLocation.current = nil
        }
        defer { MouseEventLocation.current = previous }
        playToolsSendEvent(event)
    }
}

private extension NSWindow {
    @objc dynamic func playToolsMouseLocation() -> NSPoint {
        if Thread.isMainThread, let event = MouseEventLocation.current, event.window === self {
            return event.locationInWindow
        }
        return playToolsMouseLocation()
    }
}

class AKPlugin: NSObject, Plugin {
    private weak var phoneWindow: NSWindow?
    private var phoneCaptureScale: CGFloat?
    private var windowRecorderObject: AnyObject?

    @available(macOS 14.4, *)
    private var windowRecorder: OwnWindowRecorder {
        if let existing = windowRecorderObject as? OwnWindowRecorder {
            return existing
        }
        let created = OwnWindowRecorder()
        windowRecorderObject = created
        return created
    }

    func activateOwnApplication() -> Bool {
        // Activate only this process; never ask LaunchServices to start another instance.
        return NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    func configurePhoneWindow(_ object: NSObject) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return configurePhoneViewport(object, logicalSize: window.contentLayoutRect.size)
    }

    func configurePhoneViewport(_ object: NSObject, logicalSize: CGSize) -> Bool {
        guard ProcessInfo.processInfo.environment["TOUCHSTONE_PHONE_WINDOW"] == "1",
              let window = object as? NSWindow, NSApplication.shared.windows.contains(where: { $0 === window }),
              let display = window.screen ?? NSScreen.main else { return false }
        let visible = display.visibleFrame
        let titleHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        let content = window.contentLayoutRect.size
        guard logicalSize.width > 0, logicalSize.height > 0,
              let size = fittedPhoneViewportSize(available: CGSize(width: visible.width - 32, height: visible.height - titleHeight - 32),
                                               content: content, logical: logicalSize) else { return false }
        window.contentMinSize = NSSize(width: min(window.contentMinSize.width, size.width), height: min(window.contentMinSize.height, size.height))
        window.contentAspectRatio = NSSize(width: 390, height: 844)
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        phoneWindow = window
        phoneCaptureScale = window.backingScaleFactor
        return true
    }

    var supportsWindowCapture: Bool {
        WindowCaptureSupport.isAvailable
    }

    var supportsWindowRecording: Bool {
        WindowRecordingSupport.isAvailable
    }

    func startWindowRecording(_ object: NSObject,
                              recordingId: String,
                              completion: @escaping (NSDictionary?, String?) -> Void) {
        guard #available(macOS 14.4, *), supportsWindowRecording else {
            completion(nil, "recording_unsupported")
            return
        }
        guard let window = object as? NSWindow else {
            completion(nil, "capture_window_unavailable")
            return
        }
        let scale = window.backingScaleFactor
        let outputScale = window === phoneWindow ? phoneCaptureScale ?? scale : scale
        windowRecorder.start(window: window, outputScale: outputScale, recordingId: recordingId, completion: completion)
    }

    func stopWindowRecording(_ recordingId: String,
                             completion: @escaping (NSDictionary?, String?) -> Void) {
        guard #available(macOS 14.4, *), supportsWindowRecording else {
            completion(nil, "recording_unsupported")
            return
        }
        windowRecorder.stop(recordingId: recordingId, completion: completion)
    }

    func readWindowRecording(_ recordingId: String,
                             offset: Int,
                             maxLength: Int) -> NSDictionary {
        guard #available(macOS 14.4, *), supportsWindowRecording else {
            return ["error": "recording_unsupported"]
        }
        return windowRecorder.read(recordingId: recordingId, offset: offset, maxLength: maxLength)
    }

    func releaseWindowRecording(_ recordingId: String) -> NSDictionary {
        guard #available(macOS 14.4, *), supportsWindowRecording else {
            return ["error": "recording_unsupported"]
        }
        return windowRecorder.release(recordingId: recordingId)
    }

    func pointerInWindow(_ object: NSObject) -> CGPoint {
        guard let window = object as? NSWindow, NSApplication.shared.windows.contains(where: { $0 === window }) else {
            return CGPoint(x: -1, y: -1)
        }
        let rect = window.contentLayoutRect, point = window.mouseLocationOutsideOfEventStream
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return CGPoint(x: -1, y: -1) }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (rect.maxY - point.y) / rect.height)
    }

    func captureWindow(_ object: NSObject, completion: @escaping (Data?, String?) -> Void) {
        guard #available(macOS 14.4, *), supportsWindowCapture, let window = object as? NSWindow,
              NSApplication.shared.windows.contains(where: { $0 === window }),
              window.isVisible, !window.isMiniaturized, window.windowNumber > 0 else {
            completion(nil, "capture_window_unavailable"); return
        }
        let number = window.windowNumber, frame = window.frame, contentRect = window.contentLayoutRect
        let scale = window.backingScaleFactor
        let outputScale = window === phoneWindow ? phoneCaptureScale ?? scale : scale
        Task { @MainActor in
            do {
                // This API only lists content available to this process; never fall back to desktop enumeration.
                let content = try await SCShareableContent.currentProcess
                guard let own = content.windows.first(where: { $0.windowID == CGWindowID(number) &&
                    $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else {
                    completion(nil, "capture_window_not_owned"); return
                }
                let filter = SCContentFilter(desktopIndependentWindow: own)
                let config = SCStreamConfiguration()
                config.width = Int(ceil(frame.width * outputScale)); config.height = Int(ceil(frame.height * outputScale))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                config.scalesToFit = true
                config.captureResolution = .best
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard window.isVisible, !window.isMiniaturized, window.windowNumber == number,
                      window.frame == frame, window.contentLayoutRect == contentRect, window.backingScaleFactor == scale else {
                    completion(nil, "window_resized"); return
                }
                guard let rect = windowContentCrop(frameSize: frame.size, contentRect: contentRect,
                                                   imageSize: CGSize(width: image.width, height: image.height)),
                      let cropped = image.cropping(to: rect),
                      let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
                    completion(nil, "capture_unavailable"); return
                }
                completion(png, nil)
            } catch { completion(nil, "capture_compositor_unavailable") }
        }
    }

    required override init() {
        super.init()
        _ = MouseEventLocation.install
        if let window = NSApplication.shared.windows.first {
            window.styleMask.insert([.resizable])
            window.collectionBehavior = [.fullScreenPrimary, .managed, .participatesInCycle]
            window.isMovable = true
            window.isMovableByWindowBackground = true

            if self.hideTitleBarSetting == true {
                window.styleMask.insert([.fullSizeContentView])
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.toolbar = nil
                window.title = ""
            }

            if self.floatingWindowSetting == true {
                window.level = .floating
            }

            if let aspectRatio = self.aspectRatioSetting {
                window.contentAspectRatio = aspectRatio
            }

            NSWindow.allowsAutomaticWindowTabbing = true
        }

        // Apply the same appearance rules to any subsequent windows that may be created
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main) { notif in
                guard let win = notif.object as? NSWindow else { return }
                if win !== self.phoneWindow { win.styleMask.insert([.resizable]) }

                if self.hideTitleBarSetting == true {
                    win.styleMask.insert([.fullSizeContentView])
                    win.titlebarAppearsTransparent = true
                    win.titleVisibility = .hidden
                    win.toolbar = nil
                    win.title = ""
                }

                if self.floatingWindowSetting == true {
                    win.level = .floating
                }

                if win === self.phoneWindow {
                    win.contentAspectRatio = NSSize(width: 390, height: 844)
                } else if let aspectRatio = self.aspectRatioSetting {
                    win.contentAspectRatio = aspectRatio
                }
        }
    }

    var screenCount: Int {
        NSScreen.screens.count
    }

    var mousePoint: CGPoint {
        NSApplication.shared.windows.first?.mouseLocationOutsideOfEventStream ?? CGPoint()
    }

    var windowFrame: CGRect {
        NSApplication.shared.windows.first?.frame ?? CGRect()
    }

    var isMainScreenEqualToFirst: Bool {
        return NSScreen.main == NSScreen.screens.first
    }

    var mainScreenFrame: CGRect {
        return NSScreen.main!.frame as CGRect
    }

    var isFullscreen: Bool {
        NSApplication.shared.windows.first!.styleMask.contains(.fullScreen)
    }

    var cmdPressed: Bool = false
    var cursorHideLevel = 0
    func hideCursor() {
        NSCursor.hide()
        cursorHideLevel += 1
        CGAssociateMouseAndMouseCursorPosition(0)
        warpCursor()
    }

    func hideCursorMove() {
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func warpCursor() {
        guard let firstScreen = NSScreen.screens.first else {return}
        let frame = windowFrame
        // Convert from NS coordinates to CG coordinates
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: firstScreen.frame.height - frame.midY))
    }

    func unhideCursor() {
        NSCursor.unhide()
        cursorHideLevel -= 1
        if cursorHideLevel <= 0 {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    func terminateApplication() {
        NSApplication.shared.terminate(self)
    }

    private var modifierFlag: UInt = 0

    // swiftlint:disable:next function_body_length
    func setupKeyboard(keyboard: @escaping (UInt16, Bool, Bool, Bool) -> Bool,
                       swapMode: @escaping () -> Bool) {
        func checkCmd(modifier: NSEvent.ModifierFlags) -> Bool {
            if modifier.contains(.command) {
                self.cmdPressed = true
                return true
            } else if self.cmdPressed {
                self.cmdPressed = false
            }
            return false
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let consumed = keyboard(event.keyCode, true, event.isARepeat,
                                    event.modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let consumed = keyboard(event.keyCode, false, false,
                                    event.modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            if checkCmd(modifier: event.modifierFlags) {
                return event
            }
            let pressed = self.modifierFlag < event.modifierFlags.rawValue
            let changed = self.modifierFlag ^ event.modifierFlags.rawValue
            self.modifierFlag = event.modifierFlags.rawValue
            let changedFlags = NSEvent.ModifierFlags(rawValue: changed)
            if pressed && changedFlags.contains(.option) {
                if swapMode() {
                    return nil
                }
                return event
            }
            let consumed = keyboard(event.keyCode, pressed, false,
                                    event.modifierFlags.contains(.control))
            if consumed {
                return nil
            }
            return event
        })
    }

    func setupMouseMoved(_ mouseMoved: @escaping (CGFloat, CGFloat) -> Bool) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .otherMouseDragged, .rightMouseDragged]
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            let consumed = mouseMoved(event.deltaX, event.deltaY)
            if consumed {
                return nil
            }
            return event
        })
        // transpass mouse moved event when no button pressed, for traffic light button to light up
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            _ = mouseMoved(event.deltaX, event.deltaY)
            return event
        })
    }

    func setupMouseButton(left: Bool, right: Bool, _ consumed: @escaping (Int, Bool) -> Bool) {
        let downType: NSEvent.EventTypeMask = left ? .leftMouseDown : right ? .rightMouseDown : .otherMouseDown
        let upType: NSEvent.EventTypeMask = left ? .leftMouseUp : right ? .rightMouseUp : .otherMouseUp

        // Helper to detect whether the event is inside any of the window "traffic-light" buttons
        func isInTrafficLightArea(_ event: NSEvent) -> Bool {
            if self.hideTitleBarSetting == false {
                return false
            }
            guard let win = event.window else { return false }
            let pointInWindow = event.locationInWindow
            let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton, .fullScreenButton]
            for type in buttonTypes {
                if let button = win.standardWindowButton(type) {
                    let localPoint = button.convert(pointInWindow, from: nil) // convert from window coords
                    if button.bounds.contains(localPoint) {
                        return true
                    }
                }
            }
            return false
        }

        NSEvent.addLocalMonitorForEvents(matching: downType, handler: { event in
            // Always allow clicks on the window traffic-light buttons to pass through
            if isInTrafficLightArea(event) {
                return event
            }

            // Detect double-clicks on the title-bar area (respecting system preference)

            if left && event.clickCount == 2, self.hideTitleBarSetting, let win = event.window {
                let contentRect = win.contentLayoutRect
                // Title-bar area is the region above contentLayoutRect
                if event.locationInWindow.y > contentRect.maxY {
                    win.performZoom(nil)
                    return nil
                }
            }

            // For traffic light buttons when fullscreen
            if event.window != NSApplication.shared.windows.first! {
                return event
            }
            if consumed(event.buttonNumber, true) {
                return nil
            }
            return event
        })
        NSEvent.addLocalMonitorForEvents(matching: upType, handler: { event in
            // Always allow releases on the traffic-light buttons to pass through
            if isInTrafficLightArea(event) {
                return event
            }
            if consumed(event.buttonNumber, false) {
                return nil
            }
            return event
        })
    }

    func setupScrollWheel(_ onMoved: @escaping (CGFloat, CGFloat) -> Bool) {
        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.scrollWheel, handler: { event in
            var deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                deltaX *= 16
                deltaY *= 16
            }
            let consumed = onMoved(deltaX, deltaY)
            if consumed {
                return nil
            }
            return event
        })
    }

    func urlForApplicationWithBundleIdentifier(_ value: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }

    func setMenuBarVisible(_ visible: Bool) {
        NSMenu.setMenuBarVisible(visible)
    }

    /// Convenience instance property that exposes the cached static preference.
    private var hideTitleBarSetting: Bool { Self.akAppSettingsData?.hideTitleBar ?? false }
    private var floatingWindowSetting: Bool { Self.akAppSettingsData?.floatingWindow ?? false }
    private var aspectRatioSetting: NSSize? {
        guard Self.akAppSettingsData?.resolution == 6 else {
            return nil
        }
        let width = Self.akAppSettingsData?.resizableAspectRatioWidth ?? 0
        let height = Self.akAppSettingsData?.resizableAspectRatioHeight ?? 0
        guard width > 0 && height > 0 else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    fileprivate static var akAppSettingsData: AKAppSettingsData? = {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let settingsURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/io.playcover.PlayCover")
            .appendingPathComponent("App Settings")
            .appendingPathComponent("\(bundleIdentifier).plist")
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? PropertyListDecoder().decode(AKAppSettingsData.self, from: data) else {
            return nil
        }
        return decoded
    }()
}

@available(macOS 14.4, *)
// Keep AKPlugin as the first Objective-C NSObject subclass in __objc_classlist:
// AKInterface Info.plist uses '.AKPlugin', so NSBundle.principalClass falls back to the first ObjC class.
private final class OwnWindowRecorder {
    private struct ArchivedRecording {
        let id: String
        let fileURL: URL
        let startedAt: Int64
        let finishedAt: Int64
        let durationMs: Int
        let width: Int
        let height: Int
        let size: Int
        let error: String?

        var dictionary: NSDictionary {
            var dict: [String: Any] = [
                "startedAt": startedAt,
                "finishedAt": finishedAt,
                "durationMs": durationMs,
                "width": width,
                "height": height,
                "size": size,
                "source": "playcover-own-window-h264",
                "mediaType": "video/mp4",
                "clockUncertaintyMs": 50
            ]
            if let error = error, !error.isEmpty {
                dict["error"] = error
            }
            return dict as NSDictionary
        }
    }

    private final class ActiveSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
        let id: String
        let fileURL: URL
        let pixelWidth: Int
        let pixelHeight: Int
        weak var window: NSWindow?
        let windowNumber: Int
        let initialFrameSize: CGSize
        let initialContentRect: CGRect
        let initialScale: CGFloat
        let writer: AVAssetWriter
        let writerInput: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let sampleQueue: DispatchQueue

        var stream: SCStream?
        var timer: DispatchSourceTimer?
        var streamRunning = false
        var stopping = false
        var finalized = false

        var firstHostPts: CMTime?
        var lastAppendedPts: CMTime = .zero
        var lastAppendHostTime: CMTime = .zero
        var lastPixelBuffer: CVPixelBuffer?
        var frameCount = 0
        var startedAtMs: Int64 = 0
        var earlyStopReason: String?

        let callbackLock = NSLock()
        var startCompletion: ((NSDictionary?, String?) -> Void)?
        var stopWaiters: [(NSDictionary?, String?) -> Void] = []
        var onSessionEnded: ((ActiveSession, ArchivedRecording?, String?) -> Void)?

        init(id: String,
             fileURL: URL,
             pixelWidth: Int,
             pixelHeight: Int,
             window: NSWindow,
             windowNumber: Int,
             initialFrameSize: CGSize,
             initialContentRect: CGRect,
             initialScale: CGFloat,
             writer: AVAssetWriter,
             writerInput: AVAssetWriterInput,
             adaptor: AVAssetWriterInputPixelBufferAdaptor,
             sampleQueue: DispatchQueue) {
            self.id = id
            self.fileURL = fileURL
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.window = window
            self.windowNumber = windowNumber
            self.initialFrameSize = initialFrameSize
            self.initialContentRect = initialContentRect
            self.initialScale = initialScale
            self.writer = writer
            self.writerInput = writerInput
            self.adaptor = adaptor
            self.sampleQueue = sampleQueue
            super.init()
        }

        func takeStartCompletion() -> ((NSDictionary?, String?) -> Void)? {
            callbackLock.lock()
            defer { callbackLock.unlock() }
            let cb = startCompletion
            startCompletion = nil
            return cb
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, !stopping, earlyStopReason == nil,
                  CMSampleBufferDataIsReady(sampleBuffer),
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: rawStatus),
                  status == .complete,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let samplePts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard samplePts.isValid && samplePts.isNumeric else { return }
            let nowHost = CMClockGetTime(CMClockGetHostTimeClock())

            if firstHostPts == nil {
                firstHostPts = samplePts
                startedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                guard writer.status == .writing, writerInput.isReadyForMoreMediaData,
                      adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
                    failBeforeFirstFrame("capture_compositor_unavailable")
                    return
                }
                lastPixelBuffer = pixelBuffer
                lastAppendedPts = .zero
                lastAppendHostTime = nowHost
                frameCount = 1
                if let cb = takeStartCompletion() {
                    let info: NSDictionary = [
                        "startedAt": startedAtMs,
                        "width": pixelWidth,
                        "height": pixelHeight,
                        "source": "playcover-own-window-h264",
                        "mediaType": "video/mp4",
                        "clockUncertaintyMs": 50
                    ]
                    DispatchQueue.main.async { cb(info, nil) }
                }
                return
            }

            guard let anchor = firstHostPts, writer.status == .writing else { return }
            lastPixelBuffer = pixelBuffer
            var relative = CMTimeConvertScale(CMTimeSubtract(samplePts, anchor),
                                              timescale: 90_000,
                                              method: .roundHalfAwayFromZero)
            let minNext = CMTimeAdd(lastAppendedPts, CMTime(value: 90, timescale: 90_000))
            if CMTimeCompare(relative, minNext) < 0 {
                relative = minNext
            }
            if writerInput.isReadyForMoreMediaData && adaptor.append(pixelBuffer, withPresentationTime: relative) {
                lastAppendedPts = relative
                lastAppendHostTime = nowHost
                frameCount += 1
            }
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            sampleQueue.async { [weak self] in
                guard let self = self else { return }
                self.streamRunning = false
                if self.stopping { return }
                if self.firstHostPts == nil {
                    self.failBeforeFirstFrame("capture_compositor_unavailable")
                } else if self.earlyStopReason == nil {
                    self.earlyStopReason = "capture_window_changed"
                    self.timer?.cancel()
                    self.timer = nil
                }
            }
        }

        func tickHeartbeat(windowInvalidReason: String?) {
            guard !stopping else { return }
            if let reason = windowInvalidReason, earlyStopReason == nil {
                if firstHostPts == nil {
                    failBeforeFirstFrame(reason)
                } else {
                    earlyStopReason = reason
                    stopStreamEarly()
                }
                return
            }
            guard earlyStopReason == nil, let anchor = firstHostPts else { return }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attrs[.size] as? Int, fileSize >= 248 * 1024 * 1024 {
                earlyStopReason = "recording_size_limit_exceeded"
                stopStreamEarly()
                return
            }
            let nowHost = CMClockGetTime(CMClockGetHostTimeClock())
            let idleSeconds = CMTimeGetSeconds(CMTimeSubtract(nowHost, lastAppendHostTime))
            guard idleSeconds >= 0.19, let pixelBuffer = lastPixelBuffer,
                  writer.status == .writing, writerInput.isReadyForMoreMediaData else { return }
            var relative = CMTimeConvertScale(CMTimeSubtract(nowHost, anchor),
                                              timescale: 90_000,
                                              method: .roundHalfAwayFromZero)
            let minNext = CMTimeAdd(lastAppendedPts, CMTime(value: 900, timescale: 90_000))
            if CMTimeCompare(relative, minNext) < 0 {
                relative = minNext
            }
            if adaptor.append(pixelBuffer, withPresentationTime: relative) {
                lastAppendedPts = relative
                lastAppendHostTime = nowHost
                frameCount += 1
            }
        }

        private func stopStreamEarly() {
            timer?.cancel()
            timer = nil
            guard streamRunning, let activeStream = stream else { return }
            streamRunning = false
            activeStream.stopCapture { _ in }
        }

        func failBeforeFirstFrame(_ reason: String) {
            guard !finalized else { return }
            finalized = true
            stopping = true
            timer?.cancel()
            timer = nil
            let activeStream = stream
            let wasRunning = streamRunning
            streamRunning = false
            if wasRunning, let activeStream = activeStream {
                activeStream.stopCapture { _ in }
            }
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: fileURL)
            let startCb = takeStartCompletion()
            callbackLock.lock()
            let waiters = stopWaiters
            stopWaiters.removeAll()
            callbackLock.unlock()
            onSessionEnded?(self, nil, reason)
            DispatchQueue.main.async {
                startCb?(nil, reason)
                for waiter in waiters { waiter(nil, reason) }
            }
        }

        func requestStop(completion: @escaping (NSDictionary?, String?) -> Void) {
            callbackLock.lock()
            stopWaiters.append(completion)
            callbackLock.unlock()
            sampleQueue.async { [weak self] in
                guard let self = self else { return }
                if self.stopping { return }
                self.stopping = true
                self.timer?.cancel()
                self.timer = nil
                if self.firstHostPts == nil || self.frameCount == 0 {
                    self.failBeforeFirstFrame(self.earlyStopReason ?? "recording_empty")
                    return
                }
                if self.streamRunning, let activeStream = self.stream {
                    self.streamRunning = false
                    activeStream.stopCapture { [weak self] _ in
                        self?.sampleQueue.async { self?.finalizeWriter() }
                    }
                } else {
                    self.finalizeWriter()
                }
            }
        }

        private func finalizeWriter() {
            guard !finalized else { return }
            finalized = true
            if earlyStopReason == nil,
               let anchor = firstHostPts,
               let pixelBuffer = lastPixelBuffer,
               writer.status == .writing,
               writerInput.isReadyForMoreMediaData {
                let nowHost = CMClockGetTime(CMClockGetHostTimeClock())
                let tailPts = CMTimeConvertScale(CMTimeSubtract(nowHost, anchor),
                                                 timescale: 90_000,
                                                 method: .roundHalfAwayFromZero)
                let minTail = CMTimeAdd(lastAppendedPts, CMTime(value: 1_800, timescale: 90_000))
                if CMTimeCompare(tailPts, minTail) >= 0 && adaptor.append(pixelBuffer, withPresentationTime: tailPts) {
                    lastAppendedPts = tailPts
                    frameCount += 1
                }
            }
            guard writer.status == .writing else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: fileURL)
                finishWithFailure("capture_compositor_unavailable")
                return
            }
            writerInput.markAsFinished()
            let finishedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                self.sampleQueue.async {
                    guard self.writer.status == .completed,
                          let attrs = try? FileManager.default.attributesOfItem(atPath: self.fileURL.path),
                          let size = attrs[.size] as? Int, size > 0 else {
                        try? FileManager.default.removeItem(at: self.fileURL)
                        self.finishWithFailure("recording_empty")
                        return
                    }
                    let assetDuration = CMTimeGetSeconds(AVURLAsset(url: self.fileURL).duration)
                    let fallbackSeconds = CMTimeGetSeconds(self.lastAppendedPts)
                    let seconds = (assetDuration.isFinite && assetDuration > 0) ? assetDuration : max(0.001, fallbackSeconds)
                    let durationMs = max(1, Int((seconds * 1000.0).rounded()))
                    let archived = ArchivedRecording(
                        id: self.id,
                        fileURL: self.fileURL,
                        startedAt: self.startedAtMs,
                        finishedAt: max(self.startedAtMs, finishedAtMs),
                        durationMs: durationMs,
                        width: self.pixelWidth,
                        height: self.pixelHeight,
                        size: size,
                        error: self.earlyStopReason
                    )
                    self.callbackLock.lock()
                    let waiters = self.stopWaiters
                    self.stopWaiters.removeAll()
                    self.callbackLock.unlock()
                    self.onSessionEnded?(self, archived, nil)
                    let dict = archived.dictionary
                    DispatchQueue.main.async {
                        for waiter in waiters { waiter(dict, nil) }
                    }
                }
            }
        }

        private func finishWithFailure(_ reason: String) {
            callbackLock.lock()
            let waiters = stopWaiters
            stopWaiters.removeAll()
            callbackLock.unlock()
            onSessionEnded?(self, nil, reason)
            DispatchQueue.main.async {
                for waiter in waiters { waiter(nil, reason) }
            }
        }
    }

    private static let maxRetainedArchives = 4
    private static let maxChunkLength = 256 * 1024

    private let stateLock = NSLock()
    private var active: ActiveSession?
    private var starting = false
    private var archived: [String: ArchivedRecording] = [:]
    private var archivedOrder: [String] = []
    private var storageDirectory: URL?

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.cleanupOnTerminate()
        }
    }

    private func ensureDirectory() throws -> URL {
        if let existing = storageDirectory, FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent(
            "touchstone-playcover-rec-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        storageDirectory = dir
        return dir
    }

    private func cleanupOnTerminate() {
        stateLock.lock()
        let current = active
        let dir = storageDirectory
        active = nil
        archived.removeAll()
        archivedOrder.removeAll()
        stateLock.unlock()
        current?.stream?.stopCapture { _ in }
        current?.writer.cancelWriting()
        if let dir = dir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func start(window: NSWindow,
               outputScale: CGFloat,
               recordingId: String,
               completion: @escaping (NSDictionary?, String?) -> Void) {
        guard WindowRecordingSupport.isValidRecordingId(recordingId) else {
            completion(nil, "invalid_recording_id")
            return
        }
        guard NSApplication.shared.windows.contains(where: { $0 === window }),
              window.isVisible, !window.isMiniaturized, window.windowNumber > 0 else {
            completion(nil, "capture_window_unavailable")
            return
        }
        guard window.sharingType != .none else {
            completion(nil, "capture_secure_window")
            return
        }
        let number = window.windowNumber
        let frameSize = window.frame.size
        let contentRect = window.contentLayoutRect
        let scale = window.backingScaleFactor
        guard let sourceRect = windowRecordingSourceRect(frameSize: frameSize, contentRect: contentRect),
              let pixelWidth = evenRecordingPixelDimension(contentRect.width * outputScale),
              let pixelHeight = evenRecordingPixelDimension(contentRect.height * outputScale) else {
            completion(nil, "capture_window_unavailable")
            return
        }

        stateLock.lock()
        if let current = active, current.id == recordingId, current.firstHostPts != nil {
            let info: NSDictionary = [
                "startedAt": current.startedAtMs,
                "width": current.pixelWidth,
                "height": current.pixelHeight,
                "source": "playcover-own-window-h264",
                "mediaType": "video/mp4",
                "clockUncertaintyMs": 50
            ]
            stateLock.unlock()
            completion(info, nil)
            return
        }
        if active != nil || starting {
            stateLock.unlock()
            completion(nil, "recording_busy")
            return
        }
        let dir: URL
        do {
            dir = try ensureDirectory()
        } catch {
            stateLock.unlock()
            completion(nil, "capture_unavailable")
            return
        }
        starting = true
        stateLock.unlock()

        let fileURL = dir.appendingPathComponent("recording-\(recordingId)-\(UUID().uuidString).mp4")
        Task { @MainActor in
            let abortStart = { [weak self] (reason: String) in
                guard let self = self else { return }
                self.withStateLock { self.starting = false }
                try? FileManager.default.removeItem(at: fileURL)
                completion(nil, reason)
            }

            do {
                let content = try await SCShareableContent.currentProcess
                guard let own = content.windows.first(where: {
                    $0.windowID == CGWindowID(number) &&
                    $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                }) else {
                    abortStart("capture_window_not_owned")
                    return
                }
                guard window.isVisible, !window.isMiniaturized, window.windowNumber == number,
                      window.sharingType != .none,
                      window.frame.size == frameSize, window.contentLayoutRect == contentRect,
                      window.backingScaleFactor == scale else {
                    abortStart(window.sharingType == .none ? "capture_secure_window" : "window_resized")
                    return
                }

                let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
                writer.shouldOptimizeForNetworkUse = true
                let bitrate = max(1_500_000, min(8_000_000, pixelWidth * pixelHeight * 3))
                let compression: [String: Any] = [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: 15,
                    AVVideoMaxKeyFrameIntervalDurationKey: 0.5,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
                ]
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: pixelWidth,
                    AVVideoHeightKey: pixelHeight,
                    AVVideoCompressionPropertiesKey: compression
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                        kCVPixelBufferWidthKey as String: pixelWidth,
                        kCVPixelBufferHeightKey as String: pixelHeight
                    ]
                )
                guard writer.canAdd(input) else {
                    abortStart("capture_unavailable")
                    return
                }
                writer.add(input)
                guard writer.startWriting() else {
                    abortStart("capture_unavailable")
                    return
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                writer.startSession(atSourceTime: .zero)

                let queue = DispatchQueue(label: "touchstone.playcover.recording.\(recordingId)", qos: .userInitiated)
                let session = ActiveSession(
                    id: recordingId,
                    fileURL: fileURL,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    window: window,
                    windowNumber: number,
                    initialFrameSize: frameSize,
                    initialContentRect: contentRect,
                    initialScale: scale,
                    writer: writer,
                    writerInput: input,
                    adaptor: adaptor,
                    sampleQueue: queue
                )
                session.startCompletion = completion
                session.onSessionEnded = { [weak self] ended, archivedEntry, _ in
                    guard let self = self else { return }
                    self.stateLock.lock()
                    if self.active === ended {
                        self.active = nil
                    }
                    if let entry = archivedEntry {
                        self.archived[entry.id] = entry
                        self.archivedOrder.removeAll { $0 == entry.id }
                        self.archivedOrder.append(entry.id)
                        while self.archivedOrder.count > Self.maxRetainedArchives {
                            let evictedId = self.archivedOrder.removeFirst()
                            if let evicted = self.archived.removeValue(forKey: evictedId) {
                                try? FileManager.default.removeItem(at: evicted.fileURL)
                            }
                        }
                    }
                    self.stateLock.unlock()
                }

                let filter = SCContentFilter(desktopIndependentWindow: own)
                let config = SCStreamConfiguration()
                config.sourceRect = sourceRect
                config.width = pixelWidth
                config.height = pixelHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 6
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                config.scalesToFit = true
                config.captureResolution = .best

                let stream = SCStream(filter: filter, configuration: config, delegate: session)
                try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: queue)
                session.stream = stream

                self.withStateLock {
                    self.starting = false
                    self.active = session
                }

                try await stream.startCapture()
                queue.async {
                    guard !session.stopping else { return }
                    session.streamRunning = true
                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
                    timer.setEventHandler { [weak session] in
                        guard let session = session, !session.stopping else { return }
                        DispatchQueue.main.async { [weak session] in
                            guard let session = session, !session.stopping else { return }
                            var invalidReason: String?
                            if let win = session.window {
                                if win.sharingType == .none {
                                    invalidReason = "capture_secure_window"
                                } else if !win.isVisible || win.isMiniaturized || win.windowNumber != session.windowNumber ||
                                          win.frame.size != session.initialFrameSize ||
                                          win.contentLayoutRect != session.initialContentRect ||
                                          win.backingScaleFactor != session.initialScale {
                                    invalidReason = "window_resized"
                                }
                            } else {
                                invalidReason = "capture_window_unavailable"
                            }
                            session.sampleQueue.async {
                                session.tickHeartbeat(windowInvalidReason: invalidReason)
                            }
                        }
                    }
                    session.timer = timer
                    timer.resume()
                }

                queue.asyncAfter(deadline: .now() + .seconds(10)) { [weak session] in
                    guard let session = session, session.firstHostPts == nil, !session.stopping else { return }
                    session.failBeforeFirstFrame("recording_start_timeout")
                }
            } catch {
                let activeSession: ActiveSession? = self.withStateLock {
                    let current = self.active
                    self.starting = false
                    if current?.id == recordingId {
                        self.active = nil
                    }
                    return current
                }
                if let activeSession = activeSession, activeSession.id == recordingId {
                    activeSession.sampleQueue.async {
                        activeSession.failBeforeFirstFrame("capture_compositor_unavailable")
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    completion(nil, "capture_compositor_unavailable")
                }
            }
        }
    }

    func stop(recordingId: String, completion: @escaping (NSDictionary?, String?) -> Void) {
        guard WindowRecordingSupport.isValidRecordingId(recordingId) else {
            completion(nil, "invalid_recording_id")
            return
        }
        stateLock.lock()
        if let done = archived[recordingId] {
            let dict = done.dictionary
            stateLock.unlock()
            completion(dict, nil)
            return
        }
        guard let session = active, session.id == recordingId else {
            stateLock.unlock()
            completion(nil, "recording_not_found")
            return
        }
        stateLock.unlock()
        session.requestStop(completion: completion)
    }

    func read(recordingId: String, offset: Int, maxLength: Int) -> NSDictionary {
        guard WindowRecordingSupport.isValidRecordingId(recordingId) else {
            return ["error": "invalid_recording_id"]
        }
        stateLock.lock()
        if active?.id == recordingId {
            stateLock.unlock()
            return ["error": "recording_not_stopped"]
        }
        guard let entry = archived[recordingId] else {
            stateLock.unlock()
            return ["error": "recording_not_found"]
        }
        stateLock.unlock()

        let limit = maxLength > 0 ? min(maxLength, Self.maxChunkLength) : Self.maxChunkLength
        guard offset >= 0, offset < entry.size, limit > 0 else {
            return ["error": "invalid_recording_offset"]
        }
        let count = min(limit, entry.size - offset)
        do {
            let handle = try FileHandle(forReadingFrom: entry.fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                return ["error": "invalid_recording_offset"]
            }
            return [
                "chunk": data.base64EncodedString(),
                "done": (offset + data.count) >= entry.size,
                "size": entry.size
            ]
        } catch {
            return ["error": "capture_unavailable"]
        }
    }

    func release(recordingId: String) -> NSDictionary {
        guard WindowRecordingSupport.isValidRecordingId(recordingId) else {
            return ["error": "invalid_recording_id"]
        }
        stateLock.lock()
        if active?.id == recordingId {
            stateLock.unlock()
            return ["error": "recording_not_stopped"]
        }
        guard let entry = archived.removeValue(forKey: recordingId) else {
            stateLock.unlock()
            return ["error": "recording_not_found"]
        }
        archivedOrder.removeAll { $0 == recordingId }
        stateLock.unlock()

        try? FileManager.default.removeItem(at: entry.fileURL)
        return ["released": true]
    }
}
