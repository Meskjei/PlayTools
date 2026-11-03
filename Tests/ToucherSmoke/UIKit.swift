@_exported import Foundation

public class UIView {
    public init() {}
}

public class UIWindow: UIView {
    public func hitTest(_ point: CGPoint, with event: Any?) -> UIView? { UIView() }
}

public class UITouch {
    public enum Phase: Int { case began, moved, stationary, ended, cancelled }
}

extension CGPoint {
    public var debugDescription: String { "(\(x), \(y))" }
}
