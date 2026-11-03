//
//  MacPlugin.swift
//  AKInterface
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import AppKit
import CoreGraphics
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

    func activateOwnApplication() -> Bool {
        // Activate only this process; never ask LaunchServices to start another instance.
        return NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }

    func configurePhoneWindow(_ object: NSObject) -> Bool {
        guard ProcessInfo.processInfo.environment["TOUCHSTONE_PHONE_WINDOW"] == "1",
              let window = object as? NSWindow, NSApplication.shared.windows.contains(where: { $0 === window }),
              let display = window.screen ?? NSScreen.main else { return false }
        let visible = display.visibleFrame
        let titleHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        guard let size = fittedPhoneWindowSize(available: CGSize(width: visible.width - 32, height: visible.height - titleHeight - 32)) else { return false }
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
