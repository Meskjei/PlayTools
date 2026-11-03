@_exported import Foundation
@_exported import CoreGraphics
@_exported import QuartzCore

open class UIGestureRecognizer: NSObject {}
public class UIView: NSObject {
    public var layer = CALayer()
    public weak var superview: UIView?
    public var gestureRecognizers: [UIGestureRecognizer]?
}
public class UITextView: UIView {}
public class UITextField: UIView {}
public class UIWindow: UIView {
    public var bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    public var nsWindow: NSObject? = NSObject()
    public var hit: UIView?
    public func hitTest(_ point: CGPoint, with event: Any?) -> UIView? { hit }
}
public class UITouch {
    public enum Phase { case began, moved, ended, cancelled }
}
