import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Kept independent of the event tap so the trust/routing rules can run without permissions.
enum MacKeyboardCaptureFailure: Equatable {
    case permission, secureInput, unavailable, interrupted

    var message: String {
        switch self {
        case .permission:
            return "Allow Sill Viewer in System Settings → Privacy & Security → Accessibility to capture keyboard shortcuts for the remote Mac. Then click the picture to try again. Viewing does not need this permission."
        case .secureInput:
            return "Secure keyboard input is active on this Mac. Finish or leave the protected input, then click the picture to try again."
        case .unavailable:
            return "Keyboard capture could not start. Input remains local. Check Accessibility permission and try again; you may need to quit and reopen Sill Viewer after granting access."
        case .interrupted:
            return "Keyboard capture stopped. Input has been released. Click the picture to try again."
        }
    }
}

enum MacKeyboardCapturePolicy {
    enum Route { case deliver, release, releaseToLocal, interrupted }

    static func availability(trusted: Bool, secureInput: Bool, tapEnabled: Bool) -> MacKeyboardCaptureFailure? {
        if !trusted { return .permission }
        if secureInput { return .secureInput }
        if !tapEnabled { return .interrupted }
        return nil
    }

    static func route(type: CGEventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                      owning: Bool, voiceOver: Bool) -> Route {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .interrupted }
        guard owning, type == .keyDown || type == .keyUp || type == .flagsChanged else { return .releaseToLocal }
        if type == .keyDown && MacKeyForwarder.releasesKeyboard(keyCode: keyCode, modifiers: modifiers) { return .release }
        if MacKeyForwarder.voiceOverOwns(keyCode: keyCode, modifiers: modifiers, enabled: voiceOver) { return .releaseToLocal }
        return .deliver
    }

    /// WindowServer gesture (29) and Dock control (30) events. These numbers and field 110 are
    /// undocumented; Mac Mouse Fix posts the same values to start Mission Control.
    static let gestureTypes: [UInt32] = [29, 30]
    static let gestureHIDTypeField = CGEventField(rawValue: 110)!
    static let dockSwipeHIDType: Int64 = 23

    /// Nil for any event but a gesture. True for a Dock swipe: Mission Control, App Exposé,
    /// Spaces, Launchpad or Show Desktop. The tap stops it locally only while the remote Mac takes it.
    static func systemGesture(type: UInt32, hidType: Int64) -> Bool? {
        guard gestureTypes.contains(type) else { return nil }
        return type == 30 || hidType == dockSwipeHIDType
    }

    static func rebound(_ event: CGEvent, in window: NSWindow) -> NSEvent? {
        guard [.keyDown, .keyUp, .flagsChanged].contains(event.type), let native = NSEvent(cgEvent: event) else { return nil }
        let isKey = event.type == .keyDown || event.type == .keyUp
        return NSEvent.keyEvent(with: native.type, location: native.locationInWindow,
            modifierFlags: native.modifierFlags, timestamp: native.timestamp,
            windowNumber: window.windowNumber, context: nil,
            characters: isKey ? native.characters ?? "" : "",
            charactersIgnoringModifiers: isKey ? native.charactersIgnoringModifiers ?? "" : "",
            isARepeat: event.type == .keyDown && native.isARepeat,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
    }
}

#if !MAC_CAPTURE_POLICY_TEST
// Only this boundary touches TCC or installs a tap; offline tests substitute an in-memory source.
@MainActor
protocol MacKeyboardTap: AnyObject {
    var trusted: Bool { get }
    var secureInput: Bool { get }
    var enabled: Bool { get }
    func start(receive: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) -> Bool
    func stop()
}

@MainActor
private final class SystemKeyboardTap: MacKeyboardTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var receive: ((CGEventType, CGEvent) -> Unmanaged<CGEvent>?)?
    var trusted: Bool { AXIsProcessTrusted() }
    var secureInput: Bool { IsSecureEventInputEnabled() }
    var enabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(receive: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) -> Bool {
        stop()
        self.receive = receive
        let types = [CGEventType.keyDown, .keyUp, .flagsChanged].map(\.rawValue) + MacKeyboardCapturePolicy.gestureTypes
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // This source is installed only on the main run loop, including menu-tracking modes.
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<SystemKeyboardTap>.fromOpaque(context).takeUnretainedValue()
                    guard let receive = owner.receive else { return Unmanaged.passUnretained(event) }
                    return receive(type, event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { stop(); return false }
        tap = port
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { stop(); return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        guard enabled else { stop(); return false }
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        receive = nil
    }

    deinit {
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}

/// Main-run-loop only. No logging, reposting, or capture outside explicit remote ownership.
@MainActor
final class MacKeyboardCapture {
    private let tap: MacKeyboardTap
    private let focused: @MainActor (StreamInputView) -> Bool
    private let voiceOver: @MainActor () -> Bool
    private var watchdog: Timer?
    private weak var view: StreamInputView?
    private var onFailure: ((MacKeyboardCaptureFailure) -> Void)?

    init(tap: MacKeyboardTap? = nil,
         focused: @escaping @MainActor (StreamInputView) -> Bool = { $0.keyboardCaptureFocused },
         voiceOver: @escaping @MainActor () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }) {
        self.tap = tap ?? SystemKeyboardTap()
        self.focused = focused
        self.voiceOver = voiceOver
    }

    static func requestPermission() {
        // The system prompt occurs only after the user chooses Allow Keyboard Capture.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func start(for view: StreamInputView, onFailure: @escaping (MacKeyboardCaptureFailure) -> Void) -> MacKeyboardCaptureFailure? {
        stop()
        if let failure = MacKeyboardCapturePolicy.availability(trusted: tap.trusted,
                                                               secureInput: tap.secureInput, tapEnabled: true) {
            return failure
        }
        guard focused(view) else { return .unavailable }
        self.view = view
        self.onFailure = onFailure
        guard tap.start(receive: { [weak self] type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return self.handle(type, event)
        }), tap.enabled else { stop(); return .unavailable }
        // Secure Input or revoked permission can stop events without a tap-disabled callback.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAvailability() }
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
        return nil
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        tap.stop()
        view = nil
        onFailure = nil
    }

    deinit { watchdog?.invalidate() }

    private func fail(_ failure: MacKeyboardCaptureFailure) {
        let notify = onFailure
        stop()
        notify?(failure)
    }

    func checkAvailability() {
        guard let view, focused(view), view.inputState?.controlling == true else {
            let owner = view?.inputState
            stop()
            owner?.release()
            return
        }
        if let failure = MacKeyboardCapturePolicy.availability(trusted: tap.trusted,
            secureInput: tap.secureInput, tapEnabled: tap.enabled) { fail(failure) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle gestures before key routing: a non-key event there releases control.
        if let dockSwipe = MacKeyboardCapturePolicy.systemGesture(type: type.rawValue,
            hidType: event.getIntegerValueField(MacKeyboardCapturePolicy.gestureHIDTypeField)) {
            guard dockSwipe, let view, focused(view), view.inputState?.controlling == true,
                  view.takesSystemGestures else { return Unmanaged.passUnretained(event) }
            view.noteSystemGesture()
            return nil
        }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch MacKeyboardCapturePolicy.route(type: type, keyCode: code, modifiers: flags,
            owning: view.map { focused($0) } == true && view?.inputState?.controlling == true,
            voiceOver: voiceOver()) {
        case .interrupted:
            fail(.interrupted)
            return Unmanaged.passUnretained(event)
        case .releaseToLocal:
            let owner = view?.inputState
            stop()
            owner?.release()
            return Unmanaged.passUnretained(event)
        case .release:
            let input = view
            let owner = input?.inputState
            stop()
            owner?.release()
            input?.window?.makeFirstResponder(nil)
            return nil
        case .deliver:
            // All downs/ups/modifiers take the same synchronous path: mixing queued
            // AppKit downs with tap ups can stick keys. Rebind for NSTextInputContext.
            guard let view, let window = view.window,
                  let rebound = MacKeyboardCapturePolicy.rebound(event, in: window) else {
                fail(.interrupted)
                return nil
            }
            view.handleCapturedKeyboard(rebound)
            return nil
        }
    }
}
#endif
