import Foundation

public struct RichPresence {
    public struct Assets { public var largeImage: String?, largeText: String?, smallImage: String?, smallText: String? }
    public struct Timestamps { public var start: Date? }
    public struct Button { public init(label: String, url: String) {} }
    public var details: String?, state: String?
    public var assets = Assets(), timestamps = Timestamps()
    public var buttons: [Button] = []
    public init() {}
}

public final class SwordRPC {
    private static let lock = NSLock()
    private static var values = [0, 0, 0]
    public static var calls: [Int] { lock.lock(); defer { lock.unlock() }; return values }
    private static func record(_ index: Int) { lock.lock(); defer { lock.unlock() }; values[index] += 1 }
    public init(appId: String) { Self.record(0) }
    public func connect() { Self.record(1) }
    public func setPresence(_ presence: RichPresence) { Self.record(2) }
}
