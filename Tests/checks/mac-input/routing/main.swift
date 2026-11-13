import AppKit
import StreamProtocol

MainActor.assumeIsolated {
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = InputWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400),
                         styleMask: [.borderless], backing: .buffered, defer: false)
let client = StreamClient()
let input = StreamInputView(frame: window.contentView!.bounds)
precondition(!input.reverseScrolling, "scroll reversal is opt-in")
window.contentView!.addSubview(input)
input.client = client
let tap = RecordingKeyboardTap()
var captureFocus = true
var localVoiceOver = false
let capture = MacKeyboardCapture(tap: tap,
    focused: { captureFocus && $0.canTakeControl && $0.window?.firstResponder === $0 },
    voiceOver: { localVoiceOver })
let ownership = ViewerInputState(capture: capture)
var ownershipUpdates: [Bool] = []
let ownershipSubscription = ownership.$controlling.sink { ownershipUpdates.append($0) }
defer { ownershipSubscription.cancel() }
ownership.bind(input)
precondition(!ownership.controlling)
for _ in 0..<3 {
    input.refresh()
    ownership.release()
}
precondition(ownershipUpdates == [false], "released refresh must not republish into SwiftUI updates")
tap.trusted = false
ownership.takeControl()
precondition(!ownership.controlling && ownership.captureFailure == .permission && !tap.enabled)
precondition(tap.startCount == 0, "no tap may be installed before permission")
tap.trusted = true
captureFocus = false
ownership.takeControl()
precondition(!ownership.controlling && ownership.captureFailure == .unavailable && !tap.enabled)
captureFocus = true
ownership.takeControl()
precondition(ownership.controlling && ownership.captureFailure == nil && tap.enabled)
let starts = tap.startCount
ownership.takeControl()
precondition(tap.startCount == starts, "taking existing control must not reinstall capture")
precondition(ownershipUpdates == [false, true], "taking existing control must not republish")
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

// Captured Command-Q goes remote; focus loss still releases before returning local control.
client.events.removeAll()
input.handleCapturedKeyboard(key(.keyDown, code: 12))
input.handleCapturedKeyboard(key(.keyUp, code: 12))
precondition(client.events == [.key(hidUsage: 0x14, down: true, modifiers: 0x100000),
                               .key(hidUsage: 0x14, down: false, modifiers: 0)])
client.events.removeAll()
ownership.takeControl()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
precondition(window.makeFirstResponder(nil))
precondition(client.events.count == 2)
app.sendEvent(up)
precondition(client.events.count == 2)

// A private pasteboard receiving text must not end an ordinary pointer drag.
ownership.takeControl()
precondition(ownership.controlling)
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
// Reversal changes both axes, not speed, units or gesture/momentum phase ordering.
let scroll = RecordingScrollEvent()
for reverse in [false, true] {
    input.reverseScrolling = reverse
    for precise in [false, true] {
        scroll.precise = precise
        let unit: Double = (precise ? 1 : 10) * (reverse ? -1 : 1)
        let delta = InputEvent.scroll(x: 0.5, y: 0.5, dx: 8 * unit / 640, dy: -12 * unit / 400)
        client.events.removeAll()
        scroll.gesturePhase = []; scroll.coastPhase = []
        input.scrollWheel(with: scroll)
        precondition(client.events == [delta], "unphased wheel events must keep their units")
        for (phase, momentum, boundary, begins) in [
            (NSEvent.Phase.began, NSEvent.Phase(), ScrollPhase.began, true),
            (.ended, [], .ended, false),
            ([], .began, .momentumBegan, true),
            ([], .ended, .momentumEnded, false)
        ] {
            client.events.removeAll()
            scroll.gesturePhase = phase
            scroll.coastPhase = momentum
            input.scrollWheel(with: scroll)
            let edge = InputEvent.scrollGesture(boundary, x: 0.5, y: 0.5)
            precondition(client.events == (begins ? [edge, delta] : [delta, edge]))
        }
    }
}
input.reverseScrolling = false
client.events.removeAll()
ownership.release()
input.scrollWheel(with: scroll)
precondition(client.events.isEmpty, "released views do not forward scrolling")
client.events.removeAll()
input.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: 64, y: 200)))
precondition(!ownership.controlling && client.events.isEmpty, "hover cannot take control")
precondition(input.acceptsFirstMouse(for: nil), "an activation click must reach the view")
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 700, y: 200)))
precondition(!ownership.controlling && client.events.isEmpty, "outside-picture clicks cannot take control")
window.pretendsKey = false
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
precondition(!ownership.controlling && client.events.isEmpty)
window.pretendsKey = true
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
input.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 64, y: 200)))
precondition(ownership.controlling && client.events.isEmpty, "activation click is consumed")
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
input.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 64, y: 200)))
precondition(client.events == [.pointer(.leftDown, x: 0.1, y: 0.5),
                               .pointer(.leftUp, x: 0.1, y: 0.5)])
client.events.removeAll()
for (code, flags) in [(UInt16(43), NSEvent.ModifierFlags.command), (3, [.control, .command]),
                      (2, [.shift, .command]), (48, .command), (49, .command), (0, [.control, .option])] {
    ownership.takeControl()
    input.handleCapturedKeyboard(key(.keyDown, code: code, flags: flags))
    input.handleCapturedKeyboard(key(.keyUp, code: code, flags: flags))
    precondition(ownership.controlling && client.events == [
        .key(hidUsage: MacKeyForwarder.usage(forKeyCode: code)!, down: true, modifiers: MacKeyForwarder.flags(flags)),
        .key(hidUsage: MacKeyForwarder.usage(forKeyCode: code)!, down: false, modifiers: 0)])
    client.events.removeAll()
}
// Synthetic CGEvents are converted but never posted or captured from the system.
let eventSource = CGEventSource(stateID: .privateState)!
for down in [true, false] {
    let captured = CGEvent(keyboardEventSource: eventSource, virtualKey: 48, keyDown: down)!
    captured.flags = .maskCommand
    captured.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(9)])
    let rebound = MacKeyboardCapturePolicy.rebound(captured, in: window)!
    precondition(rebound.window === window && rebound.keyCode == 48 && rebound.modifierFlags.contains(.command))
    precondition(tap.receive!(captured.type, captured) == nil, "captured keys must not also reach AppKit")
}
precondition(client.events == [.key(hidUsage: 0x2B, down: true, modifiers: 0x100000),
                               .key(hidUsage: 0x2B, down: false, modifiers: 0)])
client.events.removeAll()
let repeated = CGEvent(keyboardEventSource: eventSource, virtualKey: 9, keyDown: true)!
repeated.flags = .maskCommand
repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
precondition(MacKeyboardCapturePolicy.rebound(repeated, in: window)!.isARepeat)
let modifier = CGEvent(keyboardEventSource: eventSource, virtualKey: 55, keyDown: true)!
modifier.type = .flagsChanged
modifier.flags = CGEventFlags(rawValue: 0x100008)
let reboundModifier = MacKeyboardCapturePolicy.rebound(modifier, in: window)!
precondition(reboundModifier.type == .flagsChanged && reboundModifier.modifierFlags.rawValue == 0x100008)
// Force ordinary text through interpretKeyEvents, not the raw-key optimization.
client.hostKeyRepeat = nil
for down in [true, false] {
    let textKey = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: down)!
    textKey.flags = []
    textKey.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(97)])
    precondition(tap.receive!(textKey.type, textKey) == nil)
}
precondition(client.events == [.text("a")], "captured ordinary text must use NSTextInputClient once")
client.hostKeyRepeat = 1
client.events.removeAll()
ownership.release()
precondition(!tap.enabled && tap.receive == nil)
// Released first responders must let the local responder chain handle Escape and Tab.
let localResponder = RecordingResponder()
let previousResponder = input.nextResponder
input.nextResponder = localResponder
window.sendEvent(key(.keyDown, code: 53, flags: []))
window.sendEvent(key(.keyDown, code: 48, flags: []))
precondition(localResponder.keyCodes == [53, 48])
precondition(client.events.isEmpty)
input.nextResponder = previousResponder

// Native menu tracking releases held input, but only for the owning key window.
ownership.takeControl()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
precondition(client.events.count == 2)
window.pretendsKey = false
NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
precondition(ownership.controlling && client.events.count == 2)
window.pretendsKey = true
NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
precondition(!ownership.controlling)
precondition(client.events == [.key(hidUsage: 0x19, down: true, modifiers: 0x100000),
                               .pointer(.leftDown, x: 0.1, y: 0.5),
                               .key(hidUsage: 0x19, down: false, modifiers: 0),
                               .pointer(.leftUp, x: 0.1, y: 0.5)])
NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
precondition(client.events.count == 4, "menu tracking releases only once")
client.events.removeAll()

// Leaving the remote view releases held input, including during a drag.
input.updateTrackingAreas()
precondition(input.trackingAreas.contains { $0.options.contains(.enabledDuringMouseDrag) })
let exit = NSEvent.enterExitEvent(with: .mouseExited, location: CGPoint(x: 700, y: 200),
    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
    eventNumber: 2, trackingNumber: 0, userData: nil)!
for drag in [false, true] {
    ownership.takeControl()
    precondition(input.performKeyEquivalent(with: key(.keyDown)))
    input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
    if drag {
        input.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 700, y: 200)))
    } else {
        input.mouseExited(with: exit)
    }
    precondition(!ownership.controlling)
    precondition(client.events == [.key(hidUsage: 0x19, down: true, modifiers: 0x100000),
                                   .pointer(.leftDown, x: 0.1, y: 0.5),
                                   .key(hidUsage: 0x19, down: false, modifiers: 0),
                                   .pointer(.leftUp, x: 0.1, y: 0.5)])
    input.mouseExited(with: exit)
    app.sendEvent(up)
    input.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 700, y: 200)))
    precondition(client.events.count == 4, "exit releases only once")
    client.events.removeAll()
    input.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: 64, y: 200)))
    precondition(!ownership.controlling && client.events.isEmpty, "returning cannot recapture without a click")
    input.rightMouseDown(with: mouse(.rightMouseDown, at: CGPoint(x: 64, y: 200)))
    input.rightMouseUp(with: mouse(.rightMouseUp, at: CGPoint(x: 64, y: 200)))
    precondition(ownership.controlling && client.events.isEmpty, "right-click also takes control without clicking through")
}

// The reserved release chord still releases rather than reaching the remote Mac.
ownership.takeControl()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
precondition(input.performKeyEquivalent(with: key(.keyDown, code: 40, flags: [.control, .option, .command])))
precondition(!ownership.controlling && client.events.count == 2)
client.events.removeAll()

// Lost capture releases held input and reports failure instead of silently leaving partial control.
ownership.takeControl()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
let timeoutCallback = tap.receive!
let placeholder = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)!
precondition(timeoutCallback(.tapDisabledByTimeout, placeholder)?.takeUnretainedValue() === placeholder)
precondition(!ownership.controlling && !tap.enabled && tap.receive == nil && ownership.captureFailure == .interrupted)
precondition(client.events.count == 2)
client.events.removeAll()
for failure in [MacKeyboardCaptureFailure.secureInput, .unavailable] {
    tap.secureInput = failure == .secureInput
    tap.installSucceeds = failure != .unavailable
    ownership.takeControl()
    precondition(!ownership.controlling && !tap.enabled && tap.receive == nil && ownership.captureFailure == failure)
    precondition(client.events.isEmpty)
}
tap.secureInput = false
tap.installSucceeds = true
ownership.takeControl()
precondition(ownership.controlling && ownership.captureFailure == nil)
// The captured-event bridge cannot send an event to a different window.
input.handleCapturedKeyboard(key(.keyDown, in: other))
precondition(!ownership.controlling && !tap.enabled && client.events.isEmpty)

// Real dispatcher: escape is suppressed; active VoiceOver modifiers are returned locally.
for (code, flags, voiceOver, suppressed) in [
    (UInt16(40), CGEventFlags([.maskControl, .maskAlternate, .maskCommand]), false, true),
    (57, [.maskAlphaShift], true, false),
    (123, [.maskAlphaShift], true, false),
    (0, [.maskControl, .maskAlternate], true, false)
] {
    ownership.takeControl()
    precondition(input.performKeyEquivalent(with: key(.keyDown)))
    let callback = tap.receive!
    localVoiceOver = voiceOver
    let local = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true)!
    if code == 57 { local.type = .flagsChanged }
    local.flags = flags
    let returned = callback(local.type, local)
    precondition(suppressed ? returned == nil : returned?.takeUnretainedValue() === local)
    precondition(!ownership.controlling && !tap.enabled && tap.receive == nil && client.events.count == 2)
    precondition(callback(local.type, local)?.takeUnretainedValue() === local, "released callbacks pass through")
    precondition(client.events.count == 2, "release cleanup occurs once")
    client.events.removeAll()
    localVoiceOver = false
}
// Real dispatcher focus loss passes the event back without forwarding its key.
ownership.takeControl()
precondition(input.performKeyEquivalent(with: key(.keyDown)))
let unfocusedCallback = tap.receive!
captureFocus = false
precondition(unfocusedCallback(.keyDown, placeholder)?.takeUnretainedValue() === placeholder)
precondition(!ownership.controlling && !tap.enabled && client.events.count == 2)
client.events.removeAll()
captureFocus = true
// Real watchdog: no input events are needed to detect revoked access or Secure Input.
for reason in ["permission", "secure", "disabled", "focus"] {
    ownership.takeControl()
    precondition(input.performKeyEquivalent(with: key(.keyDown)))
    if reason == "permission" { tap.trusted = false }
    if reason == "secure" { tap.secureInput = true }
    if reason == "disabled" { tap.enabled = false }
    if reason == "focus" { captureFocus = false }
    capture.checkAvailability()
    precondition(!ownership.controlling && !tap.enabled && tap.receive == nil && client.events.count == 2)
    if reason == "permission" { precondition(ownership.captureFailure == .permission) }
    if reason == "secure" { precondition(ownership.captureFailure == .secureInput) }
    if reason == "disabled" { precondition(ownership.captureFailure == .interrupted) }
    capture.checkAvailability()
    precondition(client.events.count == 2)
    client.events.removeAll()
    tap.trusted = true; tap.secureInput = false; captureFocus = true
}

// Lifecycle loss releases the published owner and the held remote key exactly once.
for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
    ownership.takeControl()
    precondition(input.performKeyEquivalent(with: key(.keyDown)))
    NotificationCenter.default.post(name: notification, object: window)
    precondition(!ownership.controlling)
    precondition(client.events.count == 2)
    client.events.removeAll()
}
ownership.takeControl()
client.connected = false
precondition(!ownership.controlling)
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
precondition(!ownership.controlling && client.events.isEmpty)
ownership.takeControl()
precondition(!ownership.controlling)
client.connected = true
client.inputPaused = true
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 64, y: 200)))
precondition(!ownership.controlling && client.events.isEmpty)
ownership.takeControl()
precondition(!ownership.controlling)
client.inputPaused = false
client.macLocked = true
ownership.takeControl()
precondition(!ownership.controlling && !tap.enabled)
client.macLocked = false
ownership.takeControl()
precondition(ownership.controlling)

// A Dock swipe goes to the remote Mac only while it takes gestures; other gesture events stay local.
let dock = CGEvent(source: eventSource)!
dock.type = CGEventType(rawValue: 30)!
precondition(tap.receive!(dock.type, dock) == nil && ownership.controlling, "a Dock swipe is stopped locally and keeps control")
let gesture = CGEvent(source: eventSource)!
gesture.type = CGEventType(rawValue: 29)!
gesture.setIntegerValueField(MacKeyboardCapturePolicy.gestureHIDTypeField, value: 8)
precondition(tap.receive!(gesture.type, gesture) != nil && ownership.controlling, "a magnify stays local and keeps control")
gesture.setIntegerValueField(MacKeyboardCapturePolicy.gestureHIDTypeField, value: 23)
precondition(tap.receive!(gesture.type, gesture) == nil, "a Dock swipe's gesture event is stopped too")
client.hostGestures = nil
precondition(tap.receive!(dock.type, dock) != nil && ownership.controlling, "a Mac without gestures leaves the local one")
client.hostGestures = 1
StreamClient.gesturesOn = false
precondition(tap.receive!(dock.type, dock) != nil, "a switched-off device leaves the local gesture")
StreamClient.gesturesOn = true
precondition(client.events.isEmpty && client.gestures.isEmpty, "a Dock event alone sends nothing")

// Full screen locks the pointer to the picture. Only the fake boundary runs: no real pointer moves.
var detaches: [Bool] = []
var warps = 0
var detachWorks = true
input.pointerSystem = MacPointerLockSystem(detach: { detaches.append($0); return detachWorks }, warp: { _ in warps += 1 })
ownership.release()
precondition(!input.pointerLocked && detaches.isEmpty, "a window never locks")
window.pretendsFullScreen = true
ownership.takeControl()
precondition(ownership.controlling && input.pointerLocked && detaches == [true])
let screens = NSScreen.screens.isEmpty ? 0 : 1
precondition(warps == screens, "the hidden pointer waits mid-window")
client.events.removeAll()
let move = RecordingMoveEvent()
(move.dx, move.dy) = (-10_000, -10_000)
input.mouseMoved(with: move)
(move.dx, move.dy) = (64, 40)
input.mouseMoved(with: move)
precondition(client.events == [.pointer(.move, x: 0, y: 0), .pointer(.move, x: 0.1, y: 0.1)],
             "locked moves follow deltas and stay in the picture")
input.mouseExited(with: exit)
precondition(ownership.controlling, "a locked pointer cannot leave")
client.events.removeAll()
input.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 600, y: 300)))
input.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 600, y: 300)))
precondition(client.events == [.pointer(.leftDown, x: 0.1, y: 0.1), .pointer(.leftUp, x: 0.1, y: 0.1)],
             "locked clicks act at the drawn cursor, not the hidden one")
ownership.release()
precondition(!input.pointerLocked && detaches == [true, false] && warps == screens * 2, "release unlocks once")
ownership.release()
precondition(detaches == [true, false], "unlock is idempotent")
detachWorks = false
ownership.takeControl()
precondition(ownership.controlling && !input.pointerLocked, "a failed detach does not lock")
ownership.release()
precondition(detaches == [true, false, true], "a failed lock needs no unlock")
window.pretendsFullScreen = false
detachWorks = true
ownership.takeControl()
precondition(ownership.controlling)
ownership.unbind(input)
precondition(!ownership.controlling)
ownership.takeControl()
precondition(!ownership.controlling, "detached ownership cannot resume")
precondition(!window.isVisible && !other.isVisible)
print("mac-input: AppKit-routed shortcut releases, window isolation, focus cleanup and private-clipboard drag passed")
}
