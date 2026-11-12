import Foundation
import Network
import UIKit
import WebKit

/// Opt-in, loopback-only control for the app hosting PlayTools. Never starts for normal launches.
final class TouchstoneAutomation {
    private static var instance: TouchstoneAutomation?
    private let listener: NWListener
    private let token: String
    private var acting = false // main queue only
    private var phoneWindowConfigured = false
    static var hasActiveAction: Bool { instance?.acting == true }
    private var captureGeneration = 0
    private static let maxRequest = 64 * 1024

    static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        let launchMarker = getenv("TOUCHSTONE_AUTOMATION_TOKEN") != nil
        let foundationMarker = env["TOUCHSTONE_AUTOMATION_TOKEN"] != nil
        print("[touchstone] startup launch_marker=\(launchMarker) foundation_marker=\(foundationMarker) phone_requested=\(env["TOUCHSTONE_PHONE_WINDOW"] == "1") discord=removed")
        guard let token = env["TOUCHSTONE_AUTOMATION_TOKEN"], token.count >= 32,
              let rawPort = env["TOUCHSTONE_AUTOMATION_PORT"], let port = UInt16(rawPort), port >= 1024,
              let service = try? TouchstoneAutomation(token: token, port: port) else { return }
        instance = service
        service.start()
        print("[touchstone] startup listener_requested=true")
    }

    private init(token: String, port: UInt16) throws {
        self.token = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
    }

    private func start() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { connection.cancel() }
            self.read(connection, accumulated: Data())
        }
        listener.start(queue: .main)
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequest) { [weak self] data, _, complete, error in
            guard let self = self else { connection.cancel(); return }
            var buffer = accumulated
            if let data = data { buffer.append(data) }
            guard buffer.count <= Self.maxRequest else { self.reply(connection, error: "request_too_large"); return }
            if let newline = buffer.firstIndex(of: 10) {
                self.handle(connection, data: buffer.prefix(upTo: newline))
            } else if complete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, accumulated: buffer)
            }
        }
    }

    private func handle(_ connection: NWConnection, data: Data) {
        guard let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let suppliedToken = request["token"] as? String, suppliedToken == token,
              let command = request["command"] as? String else { reply(connection, error: "unauthorized_or_invalid"); return }
        switch command {
        case "recordingStop":
            guard AKInterface.shared?.supportsWindowRecording == true,
                  let stopRecording = AKInterface.shared?.stopWindowRecording else {
                reply(connection, error: "recording_unsupported"); return
            }
            guard let recordingId = request["recordingId"] as? String else {
                reply(connection, error: "invalid_recording_id"); return
            }
            stopRecording(recordingId) { [weak self] dict, error in
                DispatchQueue.main.async {
                    guard let self = self else { connection.cancel(); return }
                    if let error = error {
                        self.reply(connection, error: error)
                    } else if let result = dict as? [String: Any] {
                        self.reply(connection, result: result)
                    } else {
                        self.reply(connection, error: "capture_unavailable")
                    }
                }
            }
            return
        case "recordingRead":
            guard AKInterface.shared?.supportsWindowRecording == true,
                  let readRecording = AKInterface.shared?.readWindowRecording else {
                reply(connection, error: "recording_unsupported"); return
            }
            guard let recordingId = request["recordingId"] as? String else {
                reply(connection, error: "invalid_recording_id"); return
            }
            guard let number = request["offset"] as? NSNumber,
                  Double(number.intValue) == number.doubleValue else {
                reply(connection, error: "invalid_recording_offset"); return
            }
            let raw = readRecording(recordingId, number.intValue, 256 * 1024) as? [String: Any] ?? [:]
            if let error = raw["error"] as? String {
                reply(connection, error: error)
            } else {
                reply(connection, result: raw)
            }
            return
        case "recordingRelease":
            guard AKInterface.shared?.supportsWindowRecording == true,
                  let releaseRecording = AKInterface.shared?.releaseWindowRecording else {
                reply(connection, error: "recording_unsupported"); return
            }
            guard let recordingId = request["recordingId"] as? String else {
                reply(connection, error: "invalid_recording_id"); return
            }
            let raw = releaseRecording(recordingId) as? [String: Any] ?? [:]
            if let error = raw["error"] as? String {
                reply(connection, error: error)
            } else {
                reply(connection, result: raw)
            }
            return
        default:
            break
        }
        guard let window = screen.keyWindow, !window.isHidden, window.bounds.width > 0, window.bounds.height > 0 else {
            reply(connection, error: "window_unavailable"); return
        }
        if WindowMouseScroll.shared.isActive && ["tap", "swipe", "longPress", "type", "clearText"].contains(command) {
            reply(connection, error: "busy"); return
        }
        switch command {
        case "info":
            if !phoneWindowConfigured, let native = window.nsWindow {
                if let configure = AKInterface.shared?.configurePhoneViewport {
                    phoneWindowConfigured = configure(native, window.bounds.size)
                } else if let configure = AKInterface.shared?.configurePhoneWindow {
                    phoneWindowConfigured = configure(native)
                }
            }
            var capabilities = ["activate", "screenshot", "tree", "tap", "swipe", "longPress", "type", "clearText"]
            if AKInterface.shared?.supportsWindowRecording == true {
                capabilities.append("recording")
            }
            reply(connection, result: ["protocol": 1, "bundleId": Bundle.main.bundleIdentifier ?? "",
                "pid": ProcessInfo.processInfo.processIdentifier, "width": window.bounds.width, "height": window.bounds.height,
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "windowMode": phoneWindowConfigured ? "phone" : "native",
                "viewportFixed": phoneWindowConfigured,
                "foreground": UIApplication.shared.applicationState == .active,
                "runtime": ["discord": "removed"],
                "capabilities": capabilities])
        case "recordingStart":
            guard AKInterface.shared?.supportsWindowRecording == true,
                  let startRecording = AKInterface.shared?.startWindowRecording else {
                reply(connection, error: "recording_unsupported"); return
            }
            guard let recordingId = request["recordingId"] as? String else {
                reply(connection, error: "invalid_recording_id"); return
            }
            guard let nativeWindow = window.nsWindow else {
                reply(connection, error: "capture_window_unavailable"); return
            }
            if !phoneWindowConfigured {
                if let configure = AKInterface.shared?.configurePhoneViewport {
                    phoneWindowConfigured = configure(nativeWindow, window.bounds.size)
                } else if let configure = AKInterface.shared?.configurePhoneWindow {
                    phoneWindowConfigured = configure(nativeWindow)
                }
            }
            startRecording(nativeWindow, recordingId) { [weak self] dict, error in
                DispatchQueue.main.async {
                    guard let self = self else { connection.cancel(); return }
                    if let error = error {
                        self.reply(connection, error: error)
                    } else if let result = dict as? [String: Any] {
                        self.reply(connection, result: result)
                    } else {
                        self.reply(connection, error: "capture_unavailable")
                    }
                }
            }
        case "activate":
            guard let activate = AKInterface.shared?.activateOwnApplication, activate() else {
                reply(connection, error: "activation_unavailable"); return
            }
            reply(connection, result: ["delivered": true, "pid": ProcessInfo.processInfo.processIdentifier])
        case "tree":
            var nodes: [[String: Any]] = []
            collectViews(window, window: window, parent: nil, depth: 0, nodes: &nodes)
            reply(connection, result: ["nodes": nodes, "pointWidth": window.bounds.width,
                                       "pointHeight": window.bounds.height, "partial": true])
        case "screenshot":
            guard !acting else { reply(connection, error: "busy"); return }
            if AKInterface.shared?.supportsWindowCapture == true,
               let capture = AKInterface.shared?.captureWindow, let nativeWindow = window.nsWindow {
                acting = true
                captureGeneration += 1
                let generation = captureGeneration, size = window.bounds.size
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let self = self, self.captureGeneration == generation else { return }
                    self.captureGeneration += 1; self.acting = false
                    self.reply(connection, error: "capture_timeout")
                }
                capture(nativeWindow) { [weak self] png, error in
                    DispatchQueue.main.async {
                        guard let self = self, self.captureGeneration == generation else { return }
                        self.captureGeneration += 1; self.acting = false
                        guard screen.keyWindow === window, window.bounds.size == size else {
                            self.reply(connection, error: "window_resized"); return
                        }
                        guard let png = png, let image = UIImage(data: png)?.cgImage else {
                            self.reply(connection, error: error ?? "capture_unavailable"); return
                        }
                        self.reply(connection, result: ["png": png.base64EncodedString(), "width": image.width,
                            "height": image.height, "pointWidth": size.width, "pointHeight": size.height,
                            "scale": CGFloat(image.width) / size.width, "source": "own-window-compositor"])
                    }
                }
                return
            }
            guard !hasUnsupportedContent(window) else { reply(connection, error: "capture_contains_unsupported_surface"); return }
            let pages = visibleWebViews(in: window)
            guard pages.count <= 1 else { reply(connection, error: "capture_multiple_web_views_unsupported"); return }
            let size = window.bounds.size
            captureGeneration += 1
            let generation = captureGeneration
            func finish(_ page: WKWebView?, _ pageImage: UIImage?) {
                self.captureGeneration += 1
                guard screen.keyWindow === window, window.bounds.size == size else {
                    self.acting = false; self.reply(connection, error: "window_resized"); return
                }
                let format = UIGraphicsImageRendererFormat()
                format.scale = window.screen.scale
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
                    window.layer.render(in: context.cgContext)
                    if let page = page, let pageImage = pageImage {
                        pageImage.draw(in: page.convert(page.bounds, to: window))
                    }
                }
                self.acting = false
                guard let png = image.pngData() else { self.reply(connection, error: "capture_unavailable"); return }
                self.reply(connection, result: ["png": png.base64EncodedString(), "width": Int(image.size.width * image.scale),
                    "height": Int(image.size.height * image.scale), "scale": image.scale,
                    "pointWidth": window.bounds.width, "pointHeight": window.bounds.height])
            }
            acting = true
            if let page = pages.first {
                guard !page.isLoading, webViewCanBeComposited(page, in: window) else {
                    acting = false; reply(connection, error: "capture_web_view_not_ready_or_obscured"); return
                }
                let pageRect = page.convert(page.bounds, to: window)
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                    guard let self = self, self.acting, self.captureGeneration == generation else { return }
                    self.captureGeneration += 1
                    self.acting = false
                    self.reply(connection, error: "capture_web_view_timeout")
                }
                page.takeSnapshot(with: nil) { [weak self, weak page] image, error in
                    guard let self = self, self.acting, self.captureGeneration == generation else { return }
                    guard let page = page else {
                        self.captureGeneration += 1; self.acting = false; self.reply(connection, error: "capture_web_view_unavailable"); return
                    }
                    guard error == nil, let image = image, !page.isLoading, page.convert(page.bounds, to: window) == pageRect,
                          self.webViewCanBeComposited(page, in: window) else {
                        self.captureGeneration += 1; self.acting = false; self.reply(connection, error: "capture_web_view_unavailable"); return
                    }
                    finish(page, image)
                }
            } else { finish(nil, nil) }
        case "tap":
            guard !acting else { reply(connection, error: "busy"); return }
            guard let x = request["x"] as? Double, let y = request["y"] as? Double,
                  x.isFinite, y.isFinite, x >= 0, x < 1, y >= 0, y < 1 else {
                reply(connection, error: "invalid_coordinate"); return
            }
            guard let width = request["pointWidth"] as? Double, let height = request["pointHeight"] as? Double,
                  width == window.bounds.width, height == window.bounds.height else {
                reply(connection, error: "window_resized"); return
            }
            let point = CGPoint(x: window.bounds.minX + x * window.bounds.width, y: window.bounds.minY + y * window.bounds.height)
            acting = true
            var touchId: Int?
            Toucher.touchcam(point: point, phase: .began, tid: &touchId, actionName: "touchstone", keyName: "tap")
            guard touchId != nil else { acting = false; reply(connection, error: "touch_unavailable"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) { [weak self] in
                guard let self = self else { connection.cancel(); return }
                Toucher.touchcam(point: point, phase: .ended, tid: &touchId, actionName: "touchstone", keyName: "tap")
                self.acting = false
                self.reply(connection, result: ["delivered": true])
            }
        case "swipe", "longPress":
            guard !acting else { reply(connection, error: "busy"); return }
            guard let x = request["x"] as? Double, let y = request["y"] as? Double,
                  let endX = request["endX"] as? Double, let endY = request["endY"] as? Double,
                  let width = request["pointWidth"] as? Double, let height = request["pointHeight"] as? Double,
                  let duration = request["durationMs"] as? Int, duration >= 100, duration <= 5000,
                  [x, y, endX, endY].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 1 }),
                  width == window.bounds.width, height == window.bounds.height else {
                reply(connection, error: "invalid_gesture_or_resized_window"); return
            }
            let start = CGPoint(x: window.bounds.minX + x * width, y: window.bounds.minY + y * height)
            let end = CGPoint(x: window.bounds.minX + endX * width, y: window.bounds.minY + endY * height)
            guard command != "swipe" || max(abs(end.x - start.x), abs(end.y - start.y)) >= 12 else {
                reply(connection, error: "swipe_too_short"); return
            }
            acting = true
            var touchId: Int?
            Toucher.touchcam(point: start, phase: .began, tid: &touchId, actionName: "touchstone", keyName: command)
            guard touchId != nil else { acting = false; reply(connection, error: "touch_unavailable"); return }
            let steps = max(1, min(60, duration / 40))
            func advance(_ step: Int) {
                let fraction = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
                let changed = screen.keyWindow !== window || window.bounds.width != width || window.bounds.height != height
                Toucher.touchcam(point: point, phase: changed ? .cancelled : step == steps ? .ended : .moved,
                                 tid: &touchId, actionName: "touchstone", keyName: command)
                if changed || touchId == nil || step == steps {
                    acting = false
                    if changed || (touchId == nil && step != steps) { reply(connection, error: "gesture_interrupted") }
                    else { reply(connection, result: ["delivered": true]) }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration / steps)) { advance(step + 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(duration / steps)) { advance(1) }
        case "type":
            guard !acting else { reply(connection, error: "busy"); return }
            guard let text = request["text"] as? String, text.utf8.count <= 8192,
                  let input = firstResponder(in: window) as? UIKeyInput else { reply(connection, error: "text_input_unavailable"); return }
            input.insertText(text)
            reply(connection, result: ["delivered": true])
        case "clearText":
            guard !acting else { reply(connection, error: "busy"); return }
            guard let input = firstResponder(in: window) as? UITextInput,
                  let range = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument) else {
                reply(connection, error: "clear_text_unsupported"); return
            }
            input.replace(range, withText: "")
            guard let remaining = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument),
                  input.text(in: remaining) == "" else {
                reply(connection, error: "clear_text_unconfirmed"); return
            }
            reply(connection, result: ["delivered": true])
        default:
            reply(connection, error: "unsupported_command")
        }
    }

    private func firstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for child in view.subviews { if let responder = firstResponder(in: child) { return responder } }
        return nil
    }

    /// UIKit views only: remote web accessibility and virtual nodes are not represented.
    private func collectViews(_ view: UIView, window: UIWindow, parent: Int?, depth: Int, nodes: inout [[String: Any]]) {
        guard depth <= 30, nodes.count < 3000, !view.isHidden, view.alpha > 0 else { return }
        let rect = view.convert(view.bounds, to: window).intersection(window.bounds)
        guard !rect.isNull, !rect.isEmpty else { return }
        let index = nodes.count
        var node: [String: Any] = ["index": index, "depth": depth, "type": String(describing: type(of: view)),
            "x": rect.minX - window.bounds.minX, "y": rect.minY - window.bounds.minY,
            "width": rect.width, "height": rect.height, "enabled": view.isUserInteractionEnabled,
            "focused": view.isFirstResponder, "editable": view is UITextField || view is UITextView]
        if let parent = parent { node["parent"] = parent }
        if let label = view.accessibilityLabel, !label.isEmpty { node["label"] = label }
        if let identifier = view.accessibilityIdentifier { node["identifier"] = identifier }
        if let field = view as? UITextField, !field.isSecureTextEntry, let text = field.text { node["value"] = text }
        if let textView = view as? UITextView, !textView.isSecureTextEntry { node["value"] = textView.text }
        if let label = view as? UILabel, let text = label.text { node["value"] = text }
        nodes.append(node)
        for child in view.subviews { collectViews(child, window: window, parent: index, depth: depth + 1, nodes: &nodes) }
    }

    /// Layer rendering does not reliably include remote WebKit, video, or Metal surfaces.
    private func hasUnsupportedContent(_ view: UIView) -> Bool {
        if view.isHidden || view.alpha <= 0 { return false }
        if view is WKWebView { return false }
        let childLayers = Set(view.subviews.map { ObjectIdentifier($0.layer) })
        if hasUnsupportedLayer(view.layer, skipping: childLayers) { return true }
        return view.subviews.contains { hasUnsupportedContent($0) }
    }

    private func hasUnsupportedLayer(_ layer: CALayer, skipping: Set<ObjectIdentifier>) -> Bool {
        if layer.isHidden || layer.opacity <= 0 { return false }
        let name = String(describing: type(of: layer))
        if name.contains("MetalLayer") || name.contains("PlayerLayer") { return true }
        return (layer.sublayers ?? []).contains { !skipping.contains(ObjectIdentifier($0)) && hasUnsupportedLayer($0, skipping: skipping) }
    }

    private func visibleWebViews(in view: UIView) -> [WKWebView] {
        if view.isHidden || view.alpha <= 0 { return [] }
        if let page = view as? WKWebView { return [page] }
        return view.subviews.flatMap { visibleWebViews(in: $0) }
    }

    /// Overlaying a WebKit snapshot is valid only when nothing above or clipping it changes its pixels.
    private func webViewCanBeComposited(_ page: WKWebView, in window: UIWindow) -> Bool {
        let rect = page.convert(page.bounds, to: window)
        guard !rect.isEmpty, window.bounds.contains(rect) else { return false }
        var current: UIView = page
        while current !== window {
            guard current.transform == .identity, current.alpha == 1, let parent = current.superview,
                  let index = parent.subviews.firstIndex(of: current) else { return false }
            if parent.clipsToBounds && !parent.convert(parent.bounds, to: window).contains(rect) { return false }
            for above in parent.subviews.dropFirst(index + 1) where !above.isHidden && above.alpha > 0 {
                if above.convert(above.bounds, to: window).intersects(rect) { return false }
            }
            current = parent
        }
        return true
    }

    private func reply(_ connection: NWConnection, result: [String: Any]? = nil, error: String? = nil) {
        let response: [String: Any] = error.map { ["ok": false, "error": $0] } ?? ["ok": true, "result": result ?? [:]]
        guard var data = try? JSONSerialization.data(withJSONObject: response) else { connection.cancel(); return }
        data.append(10)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
