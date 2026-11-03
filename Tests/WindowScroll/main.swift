import Foundation
import UIKit

final class Screen { var keyWindow: UIWindow? }
let screen = Screen()
final class PlaySettings { static let shared = PlaySettings(); var keymapping = true }
final class TouchstoneAutomation { static var hasActiveAction = false }
final class AKInterface {
    static var shared: AKInterface? = AKInterface()
    var pointerInWindow: ((NSObject) -> CGPoint)? = { _ in CGPoint(x: 0.5, y: 0.5) }
}
final class Toucher {
    static var events: [(UITouch.Phase, CGPoint)] = []
    static func touchcam(point: CGPoint, phase: UITouch.Phase, tid: inout Int?, actionName: String, keyName: String) {
        events.append((phase, point)); tid = phase == .ended || phase == .cancelled ? nil : 1
    }
}
let window = UIWindow(), view = UIView()
window.hit = view; view.superview = window; screen.keyWindow = window
let wheel = WindowMouseScroll.shared
precondition(!wheel.handle(deltaX: 0, deltaY: 20), "Native UIKit must keep native scroll events")
final class WeexForwardingGestureRecognizer: UIGestureRecognizer {}
view.gestureRecognizers = [WeexForwardingGestureRecognizer()]
precondition(wheel.handle(deltaX: 0, deltaY: -10), "Embedded Weex must receive wheel touches even without a Metal ancestor")
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
precondition(!wheel.isActive && Toucher.events.last?.0 == .ended)
view.gestureRecognizers = nil; Toucher.events = []
view.layer = CAMetalLayer()
AKInterface.shared!.pointerInWindow = { _ in CGPoint(x: -1, y: -1) }
precondition(!wheel.handle(deltaX: 0, deltaY: 20))
AKInterface.shared!.pointerInWindow = { _ in CGPoint(x: 0.5, y: 0.5) }
TouchstoneAutomation.hasActiveAction = true
precondition(!wheel.handle(deltaX: 0, deltaY: 20), "A protocol action must not overlap a mouse touch")
TouchstoneAutomation.hasActiveAction = false
PlaySettings.shared.keymapping = false
precondition(!wheel.handle(deltaX: 0, deltaY: 20))
PlaySettings.shared.keymapping = true
precondition(!wheel.handle(deltaX: .nan, deltaY: 1))
let input = UITextView(); input.layer = CAMetalLayer(); input.superview = window; window.hit = input
precondition(!wheel.handle(deltaX: 0, deltaY: 20), "Text input must retain native handling")
window.hit = view
precondition(wheel.handle(deltaX: 0, deltaY: -30))
precondition(wheel.handle(deltaX: 0, deltaY: -10))
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
precondition(!wheel.isActive)
precondition(Toucher.events.filter { $0.0 == .began }.count == 1)
precondition(Toucher.events.last?.0 == .ended)
precondition(Toucher.events.filter { $0.0 == .moved }.last!.1.y < 400)
Toucher.events = []
precondition(wheel.handle(deltaX: 0, deltaY: 0.1))
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(Toucher.events.last?.0 == .cancelled && !wheel.isActive, "A tiny wheel delta must never activate a button as a tap")
Toucher.events = []
precondition(wheel.handle(deltaX: 0, deltaY: 20))
window.bounds.size.width += 1
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
precondition(Toucher.events.last?.0 == .cancelled && !wheel.isActive, "Resize must cancel the old touch")
precondition(wheel.handle(deltaX: 0, deltaY: 20))
screen.keyWindow = UIWindow()
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
precondition(Toucher.events.last?.0 == .cancelled && !wheel.isActive, "Window changes must cancel the old touch")
print("Mouse wheel routing, coalescing, release and resize checks passed")
