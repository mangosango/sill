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
precondition(MacKeyForwarder.staysLocal(keyCode: 12, modifiers: .command))
precondition(MacKeyForwarder.staysLocal(keyCode: 48, modifiers: .command))
precondition(MacKeyForwarder.staysLocal(keyCode: 0, modifiers: [.control, .option]))
precondition(!MacKeyForwarder.staysLocal(keyCode: 1, modifiers: .command))
precondition(MacKeyForwarder.releasesKeyboard(keyCode: 40, modifiers: [.control, .option, .command]))
precondition(!MacKeyForwarder.releasesKeyboard(keyCode: 40, modifiers: [.control, .option]))
precondition(keys.flagsChanged(key(56, flags: NSEvent.ModifierFlags(rawValue: 0x20002))) == [.key(hidUsage: 0xE1, down: true, modifiers: 0x20000)])
precondition(keys.flagsChanged(key(60, flags: NSEvent.ModifierFlags(rawValue: 0x20006))).count == 1)
precondition(keys.flagsChanged(key(56, flags: NSEvent.ModifierFlags(rawValue: 0x20004))) == [.key(hidUsage: 0xE1, down: false, modifiers: 0x20000)])
precondition(keys.releaseAll() == [.key(hidUsage: 0xE5, down: false, modifiers: 0)])
precondition(keys.flagsChanged(key(57)).count == 2)
print("mac-input: 20 keyboard policy assertions passed (not an attached input surface)")
