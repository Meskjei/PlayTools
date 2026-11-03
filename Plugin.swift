//
//  Plugin.swift
//  PlayTools
//
//  Created by Isaac Marovitz on 13/09/2022.
//

import Foundation

@objc(Plugin)
public protocol Plugin: NSObjectProtocol {
    init()

    var screenCount: Int { get }
    var mousePoint: CGPoint { get }
    var windowFrame: CGRect { get }
    var mainScreenFrame: CGRect { get }
    var isMainScreenEqualToFirst: Bool { get }
    var isFullscreen: Bool { get }
    var cmdPressed: Bool { get }

    func hideCursor()
    func hideCursorMove()
    func warpCursor()
    func unhideCursor()
    @objc optional func activateOwnApplication() -> Bool
    func terminateApplication()
    func setupKeyboard(keyboard: @escaping (UInt16, Bool, Bool, Bool) -> Bool,
                       swapMode: @escaping () -> Bool)
    func setupMouseMoved(_ mouseMoved: @escaping (CGFloat, CGFloat) -> Bool)
    func setupMouseButton(left: Bool, right: Bool, _ consumed: @escaping (Int, Bool) -> Bool)
    func setupScrollWheel(_ onMoved: @escaping (CGFloat, CGFloat) -> Bool)
    func urlForApplicationWithBundleIdentifier(_ value: String) -> URL?
    func setMenuBarVisible(_ value: Bool)
    @objc optional var supportsWindowCapture: Bool { get }
    @objc optional func captureWindow(_ window: NSObject, completion: @escaping (Data?, String?) -> Void)
    /// Normalized coordinates in the same content rectangle used by captureWindow.
    @objc optional func pointerInWindow(_ window: NSObject) -> CGPoint
    @objc optional func configurePhoneWindow(_ window: NSObject) -> Bool
    @objc optional func configurePhoneViewport(_ window: NSObject, logicalSize: CGSize) -> Bool
}
