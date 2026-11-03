import Foundation
import UIKit

final class Screen { var keyWindow: UIWindow? }
let screen = Screen()

final class PTFakeMetaTouch {
    static var calls: [UITouch.Phase] = []
    static func fakeTouchId(_ id: Int, at point: CGPoint, with phase: UITouch.Phase,
                            in window: UIWindow?, on view: UIView?) -> Int {
        calls.append(phase)
        return phase == .ended || phase == .cancelled ? -1 : 7
    }
}

final class DebugModel {
    static let instance = DebugModel()
    func record(point: CGPoint, phase: UITouch.Phase, tid: Int, description: String) {}
}

enum Toast {
    static func showOver(msg: String) {}
    static func showHint(title: String) {}
}

var id: Int?
let point = CGPoint(x: 1, y: 2)
Toucher.touchcam(point: point, phase: .began, tid: &id, actionName: "test", keyName: "test")
precondition(id == nil && PTFakeMetaTouch.calls.isEmpty, "a missing window must not start a touch")
Toucher.touchcam(point: point, phase: .ended, tid: &id, actionName: "test", keyName: "test")
precondition(PTFakeMetaTouch.calls.isEmpty, "an unmatched release must not create an event")
screen.keyWindow = UIWindow()
Toucher.touchcam(point: point, phase: .began, tid: &id, actionName: "test", keyName: "test")
precondition(id == 7 && PTFakeMetaTouch.calls == [.began], "a valid window must start a touch")
Toucher.touchcam(point: point, phase: .ended, tid: &id, actionName: "test", keyName: "test")
precondition(id == nil && PTFakeMetaTouch.calls == [.began, .ended], "a touch must end normally")
print("Toucher smoke passed")
