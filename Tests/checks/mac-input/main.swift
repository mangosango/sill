import AppKit
import StreamProtocol

func key(_ code: UInt16, repeat repeating: Bool = false, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                    isARepeat: repeating, keyCode: code)!
}
var keys = MacKeyForwarder()
precondition(keys.keyDown(key(0), hostKeyRepeat: 1) == [.key(hidUsage: 4, down: true, modifiers: 0)])
precondition(keys.keyDown(key(0, repeat: true), hostKeyRepeat: 1).isEmpty)
precondition(keys.keyDown(key(0, repeat: true), hostKeyRepeat: nil).count == 1)
precondition(keys.down == [4])
precondition(keys.releaseAll() == [.key(hidUsage: 4, down: false, modifiers: 0)])
precondition(keys.releaseAll().isEmpty)
precondition(keys.keyUp(key(0)).isEmpty)
precondition(MacKeyForwarder.usage(forKeyCode: 82) == nil) // keypad zero stays text
precondition(MacKeyForwarder.usage(forKeyCode: 76) == nil) // keypad Enter stays text
precondition(!MacKeyForwarder.staysLocal(keyCode: 12, modifiers: .command))
precondition(!MacKeyForwarder.staysLocal(keyCode: 48, modifiers: .command))
precondition(!MacKeyForwarder.staysLocal(keyCode: 0, modifiers: [.control, .option]))
precondition(MacKeyForwarder.staysLocal(keyCode: 0, modifiers: [.control, .option], voiceOver: true))
precondition(MacKeyForwarder.staysLocal(keyCode: 57, modifiers: [], voiceOver: true))
precondition(MacKeyForwarder.staysLocal(keyCode: 123, modifiers: [.capsLock], voiceOver: true))
precondition(!MacKeyForwarder.staysLocal(keyCode: 57, modifiers: [.capsLock]))
precondition(!MacKeyForwarder.staysLocal(keyCode: 1, modifiers: .command))
precondition(MacKeyForwarder.releasesKeyboard(keyCode: 40, modifiers: [.control, .option, .command]))
precondition(!MacKeyForwarder.releasesKeyboard(keyCode: 40, modifiers: [.control, .option]))
precondition(keys.flagsChanged(key(56, flags: NSEvent.ModifierFlags(rawValue: 0x20002))) == [.key(hidUsage: 0xE1, down: true, modifiers: 0x20000)])
precondition(keys.flagsChanged(key(60, flags: NSEvent.ModifierFlags(rawValue: 0x20006))).count == 1)
precondition(keys.flagsChanged(key(56, flags: NSEvent.ModifierFlags(rawValue: 0x20004))) == [.key(hidUsage: 0xE1, down: false, modifiers: 0x20000)])
precondition(keys.releaseAll() == [.key(hidUsage: 0xE5, down: false, modifiers: 0)])
precondition(keys.flagsChanged(key(57)).count == 2)
// Native text callbacks use UTF-16 replacement ranges, including a Korean syllable rebuilt in place.
var text = TextComposition()
precondition(text.setMarked("ㄋ", selected: NSRange(location: 1, length: 0)).isEmpty)
precondition(text.insert("你") == [.text("你")])
precondition(text.marked == nil)
precondition(text.forget().isEmpty)
precondition(text.insert("한") == [.text("한")])
precondition(text.replace(NSRange(location: 0, length: 1), with: "하") == [.backspaces(1), .text("하")])
text.select(NSRange(location: 0, length: 1))
precondition(text.insert("글") == [.backspaces(1), .text("글")])
precondition(text.forget().isEmpty)
precondition(text.setMarked("´", selected: NSRange(location: 1, length: 0)).isEmpty)
precondition(text.insert("é") == [.text("é")])
precondition(!MacKeyForwarder.rawKey(key(82), composing: false, hostKeyRepeat: 1))
precondition(!MacKeyForwarder.rawKey(key(0), composing: true, hostKeyRepeat: 1))
precondition(!MacKeyForwarder.rawKey(key(0), composing: false, hostKeyRepeat: nil))
precondition(!MacKeyForwarder.rawKey(key(0, flags: .option), composing: false, hostKeyRepeat: 1))
precondition(MacKeyForwarder.rawKey(key(1, flags: .command), composing: false, hostKeyRepeat: nil))
precondition(MacKeyForwarder.rawKey(key(123), composing: false, hostKeyRepeat: nil))
precondition(!MacKeyForwarder.rawKey(key(10), composing: false, hostKeyRepeat: 1))
precondition(MacKeyboardCapturePolicy.availability(trusted: false, secureInput: false, tapEnabled: true) == .permission)
precondition(MacKeyboardCapturePolicy.availability(trusted: true, secureInput: true, tapEnabled: true) == .secureInput)
precondition(MacKeyboardCapturePolicy.availability(trusted: true, secureInput: false, tapEnabled: false) == .interrupted)
precondition(MacKeyboardCapturePolicy.availability(trusted: true, secureInput: false, tapEnabled: true) == nil)
for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
    precondition(MacKeyboardCapturePolicy.route(type: type, keyCode: 48, modifiers: .command,
        owning: true, voiceOver: false) == .deliver)
    precondition(MacKeyboardCapturePolicy.route(type: type, keyCode: 0, modifiers: [],
        owning: true, voiceOver: false) == .deliver, "text and releases share the same ordered delivery")
    precondition(MacKeyboardCapturePolicy.route(type: type, keyCode: 48, modifiers: .command,
        owning: false, voiceOver: false) == .releaseToLocal)
}
for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
    precondition(MacKeyboardCapturePolicy.route(type: type, keyCode: 0, modifiers: [],
        owning: true, voiceOver: false) == .interrupted)
}
precondition(MacKeyboardCapturePolicy.route(type: .keyDown, keyCode: 40, modifiers: [.command, .option, .control],
    owning: true, voiceOver: true) == .release)
precondition(MacKeyboardCapturePolicy.route(type: .keyDown, keyCode: 0, modifiers: [.option, .control],
    owning: true, voiceOver: true) == .releaseToLocal)
precondition(MacKeyboardCapturePolicy.route(type: .keyDown, keyCode: 0, modifiers: [.option, .control],
    owning: true, voiceOver: false) == .deliver)
precondition(MacKeyboardCapturePolicy.route(type: .flagsChanged, keyCode: 57, modifiers: [],
    owning: true, voiceOver: true) == .releaseToLocal)
precondition(MacKeyboardCapturePolicy.route(type: .keyDown, keyCode: 123, modifiers: [.capsLock],
    owning: true, voiceOver: true) == .releaseToLocal)
print("mac-input: keyboard/composition and permission/capture routing policy assertions passed")

// Detached native label only: no application, window, responder or host IO.
let preedit = MacPreeditLabel()
var preeditText = TextComposition()
precondition(preeditText.insert("prefix") == [.text("prefix")])
precondition(preeditText.setMarked("你😀好", selected: NSRange(location: 1, length: 2)).isEmpty)
preedit.update(preeditText, in: CGRect(x: 0, y: 0, width: 500, height: 300))
precondition(!preedit.isHidden && preedit.stringValue == "你😀好")
var highlighted = NSRange()
precondition(preedit.attributedStringValue.attribute(.backgroundColor, at: 1, effectiveRange: &highlighted) != nil)
precondition(highlighted == NSRange(location: 1, length: 2))
precondition(preedit.accessibilityLabel() == "Input method composition")
precondition(preedit.attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
precondition(preedit.attributedStringValue.attribute(.backgroundColor, at: 3, effectiveRange: nil) == nil)
precondition(!preedit.acceptsFirstResponder && preedit.hitTest(.zero) == nil)
precondition(preeditText.setMarked("中文", selected: NSRange(location: NSNotFound, length: Int.max)).isEmpty)
preedit.update(preeditText, in: CGRect(x: 0, y: 0, width: 20, height: 100))
precondition(preedit.frame.width <= 20 && preedit.frame.midX == 10)
precondition(preeditText.insert("中文") == [.text("中文")])
preedit.update(preeditText, in: .zero)
precondition(preedit.isHidden && preedit.stringValue.isEmpty)
precondition(preeditText.setMarked("未完", selected: NSRange(location: 1, length: 0)).isEmpty)
preedit.update(preeditText, in: CGRect(x: 0, y: 0, width: 500, height: 100))
precondition(!preedit.isHidden)
_ = preeditText.forget()
preedit.update(preeditText, in: .zero)
precondition(preedit.isHidden && preedit.stringValue.isEmpty)
precondition(preeditText.setMarked("未完", selected: NSRange(location: 0, length: 2)).isEmpty)
preedit.update(preeditText, in: CGRect(x: 10, y: 20, width: 500, height: 100))
precondition(preedit.frame.midX == 260 && preedit.frame.minY == 20)
precondition(preeditText.setMarked("", selected: NSRange(location: 0, length: 0)).isEmpty)
preedit.update(preeditText, in: .zero)
precondition(preedit.isHidden && preedit.stringValue.isEmpty)
preeditText = TextComposition()
preedit.update(preeditText, in: .zero)
precondition(preedit.isHidden && preedit.stringValue.isEmpty)
print("mac-input: native preedit UTF-16 selection, resize, clearing and no-preedit-output checks passed")
