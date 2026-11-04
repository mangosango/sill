import AppKit
import Carbon.HIToolbox
import StreamProtocol

/// HID mapping and held-key bookkeeping adapted from Alexander Deutsch's PR #128 (173843be).
/// Text belongs to NSTextInputClient; callers must choose that path before invoking keyDown.
struct MacKeyForwarder {
    /// The keys whose down went to the Mac and whose up has not, in the order they went down.
    private(set) var down: [UInt16] = []

    /// A key went down (repeats included). The events to send.
    mutating func keyDown(_ event: NSEvent, hostKeyRepeat: Int?) -> [InputEvent] {
        guard let usage = Self.usage(forKeyCode: event.keyCode) else { return [] }
        // Older hosts do not repeat: retain AppKit's repeated downs, but never track them twice.
        if event.isARepeat, (hostKeyRepeat ?? 0) >= 1 { return [] }
        if !down.contains(usage) { down.append(usage) }
        return [.key(hidUsage: usage, down: true, modifiers: Self.flags(event.modifierFlags))]
    }

    /// Only the release chord and an active local VoiceOver's navigation stay local.
    static func staysLocal(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, voiceOver: Bool = false) -> Bool {
        releasesKeyboard(keyCode: keyCode, modifiers: modifiers)
            || voiceOverOwns(keyCode: keyCode, modifiers: modifiers, enabled: voiceOver)
    }

    static func voiceOverOwns(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, enabled: Bool) -> Bool {
        enabled && (modifiers.isSuperset(of: [.control, .option])
                    || keyCode == UInt16(kVK_CapsLock) || modifiers.contains(.capsLock))
    }

    static func releasesKeyboard(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(kVK_ANSI_K)
            && modifiers.intersection([.command, .control, .option, .shift]) == [.command, .control, .option]
    }

    /// A key went up: its up, when its down went to the Mac.
    mutating func keyUp(_ event: NSEvent) -> [InputEvent] {
        guard let usage = Self.usage(forKeyCode: event.keyCode) else { return [] }
        return ended(usage).map { [$0] } ?? []
    }

    /// A modifier key changed (shift, control, option, command on either side, Caps Lock): its own key
    /// down or up, judged by whether the Mac already has it down. Caps Lock is a toggle, so each change
    /// is one press, down and up.
    mutating func flagsChanged(_ event: NSEvent) -> [InputEvent] {
        guard let usage = Self.usage(forKeyCode: event.keyCode) else { return [] }
        if usage == Self.capsLock {
            return [.key(hidUsage: usage, down: true, modifiers: held), .key(hidUsage: usage, down: false, modifiers: held)]
        }
        guard let flag = KeyModifiers.flag(forKey: usage) else { return [] }
        let pressed = event.modifierFlags.contains(Self.deviceFlag(for: event.keyCode) ?? Self.nsFlag(for: flag))
        if pressed, !down.contains(usage) {
            down.append(usage)
            return [.key(hidUsage: usage, down: true, modifiers: held)]
        }
        if !pressed, let up = ended(usage) { return [up] }
        return []
    }

    /// Every key still down on the Mac going up, the last pressed first: the stream view losing the
    /// keyboard (another window, another app, the sidebar), after which AppKit sends it no ups.
    mutating func releaseAll() -> [InputEvent] {
        var ups: [InputEvent] = []
        while let usage = down.last, let up = ended(usage) { ups.append(up) }
        return ups
    }

    private mutating func ended(_ usage: UInt16) -> InputEvent? {
        guard let i = down.firstIndex(of: usage) else { return nil }
        down.remove(at: i)
        return .key(hidUsage: usage, down: false, modifiers: held)
    }

    /// The modifier flags of the modifier keys down on the Mac.
    private var held: UInt64 { down.reduce(0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) } }

    /// Shift, control, option and command from AppKit's flags: the same bit positions as the
    /// protocol's (CGEventFlags), so they travel unchanged. Caps Lock and fn stay here.
    static func flags(_ modifiers: NSEvent.ModifierFlags) -> UInt64 {
        UInt64(modifiers.rawValue) & (KeyModifiers.shift.rawValue | KeyModifiers.control.rawValue
                                      | KeyModifiers.option.rawValue | KeyModifiers.command.rawValue)
    }

    private static func nsFlag(for flag: KeyModifiers) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(flag.rawValue))
    }

    /// The device-dependent bit of one side's modifier key (IOLLEvent.h's NX_DEVICE…KEYMASK), so
    /// letting go of left ⌘ while right ⌘ is held reads as the left key's up.
    private static func deviceFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        let bit: UInt
        switch Int(keyCode) {
        case kVK_Control: bit = 0x0000_0001
        case kVK_Shift: bit = 0x0000_0002
        case kVK_RightShift: bit = 0x0000_0004
        case kVK_Command: bit = 0x0000_0008
        case kVK_RightCommand: bit = 0x0000_0010
        case kVK_Option: bit = 0x0000_0020
        case kVK_RightOption: bit = 0x0000_0040
        case kVK_RightControl: bit = 0x0000_2000
        default: return nil
        }
        return NSEvent.ModifierFlags(rawValue: bit)
    }

    /// Only known direct layouts delegate character repetition; other layouts keep native dead keys.
    static func rawKey(_ event: NSEvent, composing: Bool, hostKeyRepeat: Int?) -> Bool {
        guard !composing, let usage = usage(forKeyCode: event.keyCode) else { return false }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return true }
        if usage >= 0x3A && usage <= 0x52 { return true }
        guard (hostKeyRepeat ?? 0) >= 1, !event.modifierFlags.contains(.option),
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
              let identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let sourceID = Unmanaged<CFString>.fromOpaque(identifier).takeUnretainedValue() as String
        guard ["com.apple.keylayout.US", "com.apple.keylayout.ABC"].contains(sourceID) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ascii).takeUnretainedValue())
            && (Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() as String) == (kTISTypeKeyboardLayout as String)
    }

    static let capsLock: UInt16 = 0x39

    /// A virtual key (kVK_…) as its HID usage, for every key the host maps back
    /// (Sources/SillHost/KeyStrokes.swift's `virtualKeys`), or nil.
    static func usage(forKeyCode code: UInt16) -> UInt16? { usages[code] }

    private static let usages: [UInt16: UInt16] = {
        let map: [Int: UInt16] = [
            kVK_ANSI_A: 0x04, kVK_ANSI_B: 0x05, kVK_ANSI_C: 0x06, kVK_ANSI_D: 0x07, kVK_ANSI_E: 0x08,
            kVK_ANSI_F: 0x09, kVK_ANSI_G: 0x0A, kVK_ANSI_H: 0x0B, kVK_ANSI_I: 0x0C, kVK_ANSI_J: 0x0D,
            kVK_ANSI_K: 0x0E, kVK_ANSI_L: 0x0F, kVK_ANSI_M: 0x10, kVK_ANSI_N: 0x11, kVK_ANSI_O: 0x12,
            kVK_ANSI_P: 0x13, kVK_ANSI_Q: 0x14, kVK_ANSI_R: 0x15, kVK_ANSI_S: 0x16, kVK_ANSI_T: 0x17,
            kVK_ANSI_U: 0x18, kVK_ANSI_V: 0x19, kVK_ANSI_W: 0x1A, kVK_ANSI_X: 0x1B, kVK_ANSI_Y: 0x1C,
            kVK_ANSI_Z: 0x1D,
            kVK_ANSI_1: 0x1E, kVK_ANSI_2: 0x1F, kVK_ANSI_3: 0x20, kVK_ANSI_4: 0x21, kVK_ANSI_5: 0x22,
            kVK_ANSI_6: 0x23, kVK_ANSI_7: 0x24, kVK_ANSI_8: 0x25, kVK_ANSI_9: 0x26, kVK_ANSI_0: 0x27,
            kVK_Return: 0x28, kVK_Escape: 0x29, kVK_Delete: 0x2A, kVK_Tab: 0x2B,
            kVK_Space: 0x2C, kVK_ANSI_Minus: 0x2D, kVK_ANSI_Equal: 0x2E, kVK_ANSI_LeftBracket: 0x2F,
            kVK_ANSI_RightBracket: 0x30, kVK_ANSI_Backslash: 0x31, kVK_ANSI_Semicolon: 0x33,
            kVK_ANSI_Quote: 0x34, kVK_ANSI_Grave: 0x35, kVK_ANSI_Comma: 0x36, kVK_ANSI_Period: 0x37,
            kVK_ANSI_Slash: 0x38, kVK_CapsLock: 0x39,
            kVK_F1: 0x3A, kVK_F2: 0x3B, kVK_F3: 0x3C, kVK_F4: 0x3D, kVK_F5: 0x3E, kVK_F6: 0x3F,
            kVK_F7: 0x40, kVK_F8: 0x41, kVK_F9: 0x42, kVK_F10: 0x43, kVK_F11: 0x44, kVK_F12: 0x45,
            kVK_Home: 0x4A, kVK_PageUp: 0x4B, kVK_ForwardDelete: 0x4C, kVK_End: 0x4D, kVK_PageDown: 0x4E,
            kVK_RightArrow: 0x4F, kVK_LeftArrow: 0x50, kVK_DownArrow: 0x51, kVK_UpArrow: 0x52,
            kVK_Control: 0xE0, kVK_Shift: 0xE1, kVK_Option: 0xE2, kVK_Command: 0xE3,
            kVK_RightControl: 0xE4, kVK_RightShift: 0xE5, kVK_RightOption: 0xE6, kVK_RightCommand: 0xE7,
        ]
        return Dictionary(uniqueKeysWithValues: map.map { (UInt16($0.key), $0.value) })
    }()
}
