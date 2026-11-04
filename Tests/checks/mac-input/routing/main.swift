import AppKit
import StreamProtocol

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = InputWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400),
                         styleMask: [.borderless], backing: .buffered, defer: false)
let client = StreamClient()
let input = StreamInputView(frame: window.contentView!.bounds)
window.contentView!.addSubview(input)
input.client = client
precondition(window.makeFirstResponder(input))
precondition(!window.isVisible)
func key(_ type: NSEvent.EventType, code: UInt16 = 9, flags: NSEvent.ModifierFlags = .command,
         in target: NSWindow = window) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: target.windowNumber, context: nil, characters: "v",
                    charactersIgnoringModifiers: "v", isARepeat: false, keyCode: code)!
}
let up = key(.keyUp)
precondition(up.window === window)
precondition(input.performKeyEquivalent(with: key(.keyDown)))
precondition(client.events == [.key(hidUsage: 0x19, down: true, modifiers: 0x100000)])
app.sendEvent(up)
precondition(client.events == [.key(hidUsage: 0x19, down: true, modifiers: 0x100000),
                               .key(hidUsage: 0x19, down: false, modifiers: 0)],
             "Command-V must release even when NSWindow swallows its keyUp")
input.keyUp(with: up)
precondition(client.events.count == 2, "a second delivery must not send another up")
// Keep the modifier held after V's release, then release it separately.
client.events.removeAll()
input.flagsChanged(with: key(.flagsChanged, code: 55, flags: NSEvent.ModifierFlags(rawValue: 0x100008)))
precondition(input.performKeyEquivalent(with: key(.keyDown)))
app.sendEvent(up)
input.flagsChanged(with: key(.flagsChanged, code: 55, flags: []))
precondition(client.events == [
    .key(hidUsage: 0xE3, down: true, modifiers: 0x100000),
    .key(hidUsage: 0x19, down: true, modifiers: 0x100000),
    .key(hidUsage: 0x19, down: false, modifiers: 0x100000),
    .key(hidUsage: 0xE3, down: false, modifiers: 0)])

// An event in another window must not release this view's tracked key.
let other = InputWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
client.events.removeAll()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
app.sendEvent(key(.keyUp, in: other))
precondition(client.events.count == 1)
app.sendEvent(up)
precondition(client.events.count == 2)

// Local shortcuts and untracked ups send nothing; focus loss still releases first.
client.events.removeAll()
precondition(!input.performKeyEquivalent(with: key(.keyDown, code: 12))) // Command-Q
app.sendEvent(key(.keyUp, code: 12))
precondition(client.events.isEmpty)
precondition(input.performKeyEquivalent(with: key(.keyDown)))
precondition(window.makeFirstResponder(nil))
precondition(client.events.count == 2)
app.sendEvent(up)
precondition(client.events.count == 2)

// A private pasteboard receiving text must not end an ordinary pointer drag.
precondition(window.makeFirstResponder(input))
client.events.removeAll()
let board = NSPasteboard.withUniqueName()
let clipboard = MacClipboard(board: board)
func mouse(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                      windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                      clickCount: 1, pressure: 1)!
}
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
clipboard.write("test copy", lifetime: 60)
input.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 320, y: 200)))
input.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 320, y: 200)))
precondition(client.events == [.pointer(.leftDown, x: 0.1, y: 0.5),
                               .pointer(.move, x: 0.5, y: 0.5),
                               .pointer(.leftUp, x: 0.5, y: 0.5)])
clipboard.reset()
board.releaseGlobally()
precondition(!window.isVisible && !other.isVisible)
print("mac-input: AppKit-routed shortcut releases, window isolation, focus cleanup and private-clipboard drag passed")
