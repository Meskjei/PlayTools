import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.makeKeyAndOrderFront(nil)
let otherWindow = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 200, height: 200),
                           styleMask: [.titled], backing: .buffered, defer: false)
otherWindow.orderFront(nil)
let plugin = AKPlugin()
var observed = false
let windowBefore = window.mouseLocationOutsideOfEventStream
let otherBefore = otherWindow.mouseLocationOutsideOfEventStream
let target = windowBefore == NSPoint(x: 81, y: 109) ? NSPoint(x: 91, y: 119) : NSPoint(x: 81, y: 109)
let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
    precondition(event.window === window)
    precondition(window.mouseLocationOutsideOfEventStream == target, "event position not used")
    precondition(otherWindow.mouseLocationOutsideOfEventStream == otherBefore, "other window was affected")
    observed = true
    return nil
}
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: target, modifierFlags: [], timestamp: 1,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                               clickCount: 1, pressure: 1)!
app.sendEvent(event)
precondition(observed, "mouse event was not dispatched")
precondition(window.mouseLocationOutsideOfEventStream == windowBefore, "event location leaked outside dispatch")
NSEvent.removeMonitor(monitor!)
withExtendedLifetime(plugin) {}
let label = NSTextField(labelWithString: "Mouse location smoke passed")
label.frame = NSRect(x: 20, y: 120, width: 350, height: 30)
window.contentView?.addSubview(label)
otherWindow.orderOut(nil)
window.makeKeyAndOrderFront(nil)
print("Mouse location smoke passed")
app.run()
