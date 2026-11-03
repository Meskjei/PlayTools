import UIKit
import QuartzCore

/// Native wheel events do not reach the touch forwarding used by Metal and embedded Weex renderers.
final class WindowMouseScroll {
    static let shared = WindowMouseScroll()
    private weak var window: UIWindow?
    private var bounds = CGRect.zero
    private var point = CGPoint.zero
    private var target = CGPoint.zero
    private var origin = CGPoint.zero
    private var movedBeyondTap = false
    private var touch: Int?
    private var lastWheel = Date.distantPast
    var isActive: Bool { touch != nil }

    func handle(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard Thread.isMainThread, PlaySettings.shared.keymapping, !TouchstoneAutomation.hasActiveAction,
              deltaX.isFinite, deltaY.isFinite, deltaX != 0 || deltaY != 0,
              let current = screen.keyWindow, let native = current.nsWindow,
              let pointer = AKInterface.shared?.pointerInWindow else { return false }
        let normalized = pointer(native)
        guard normalized.x >= 0, normalized.x < 1, normalized.y >= 0, normalized.y < 1 else { return false }
        let cursor = CGPoint(x: current.bounds.minX + normalized.x * current.bounds.width,
                             y: current.bounds.minY + normalized.y * current.bounds.height)
        var hit = current.hitTest(cursor, with: nil), customRenderer = false
        while let view = hit {
            if view is UITextView || view is UITextField { return false }
            customRenderer = customRenderer || view.layer is CAMetalLayer ||
                (view.gestureRecognizers ?? []).contains {
                    let name = String(describing: type(of: $0))
                    return name.hasSuffix("UnicornComponentTouchGestureRecognizer") || name.hasSuffix("WeexForwardingGestureRecognizer")
                }
            hit = view.superview
        }
        guard customRenderer else { return false }
        if isActive && (window !== current || bounds != current.bounds) { finish(cancelled: true) }
        if !isActive {
            window = current; bounds = current.bounds; point = cursor; target = cursor
            origin = cursor; movedBeyondTap = false
            Toucher.touchcam(point: point, phase: .began, tid: &touch, actionName: "WindowScroll", keyName: "wheel")
            guard touch != nil else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { self.tick() }
        }
        target.x = min(bounds.maxX - 2, max(bounds.minX + 2, target.x + deltaX * 2))
        target.y = min(bounds.maxY - 2, max(bounds.minY + 2, target.y + deltaY * 2))
        lastWheel = Date()
        return true
    }

    private func tick() {
        guard isActive else { return }
        guard let window = window, screen.keyWindow === window, window.bounds == bounds else {
            finish(cancelled: true); return
        }
        let dx = target.x - point.x, dy = target.y - point.y
        if abs(dx) + abs(dy) > 0.5 {
            point.x += dx / 2; point.y += dy / 2
            movedBeyondTap = movedBeyondTap || max(abs(point.x - origin.x), abs(point.y - origin.y)) >= 12
            Toucher.touchcam(point: point, phase: .moved, tid: &touch, actionName: "WindowScroll", keyName: "wheel")
        } else if Date().timeIntervalSince(lastWheel) > 0.12 || point.x <= bounds.minX + 3 ||
                    point.x >= bounds.maxX - 3 || point.y <= bounds.minY + 3 || point.y >= bounds.maxY - 3 {
            finish(cancelled: false); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { self.tick() }
    }

    private func finish(cancelled: Bool) {
        // A tiny wheel movement must not become a tap on the control under the pointer.
        Toucher.touchcam(point: point, phase: cancelled || !movedBeyondTap ? .cancelled : .ended, tid: &touch,
                         actionName: "WindowScroll", keyName: "wheel")
        touch = nil; window = nil
    }
}
