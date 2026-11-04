import AppKit
import Combine
import StreamProtocol

/// Fractions use the rendered picture's top-left origin, not AppKit's window coordinates.
enum MacPointerGeometry {
    static func point(_ point: CGPoint, in rect: CGRect, clamp: Bool) -> CGPoint? {
        guard rect.width > 0, rect.height > 0,
              clamp || rect.contains(point) else { return nil }
        return CGPoint(x: min(1, max(0, (point.x - rect.minX) / rect.width)),
                       y: min(1, max(0, (point.y - rect.minY) / rect.height)))
    }
    static func acceptsInput(keyWindow: Bool, firstResponder: Bool, connected: Bool, paused: Bool) -> Bool {
        keyWindow && firstResponder && connected && !paused
    }
    static func phases(_ phase: NSEvent.Phase, momentum: Bool) -> [ScrollPhase] {
        var result: [ScrollPhase] = []
        if phase.contains(.began) { result.append(momentum ? .momentumBegan : .began) }
        if phase.contains(.ended) || phase.contains(.cancelled) { result.append(momentum ? .momentumEnded : .ended) }
        return result
    }
}

#if !POINTER_POLICY_TEST || MAC_INPUT_TEST
/// A read-only native preedit, never a second text responder or pointer target.
final class MacPreeditLabel: NSTextField {
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        setAccessibilityLabel("Input method composition")
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ composition: TextComposition, in bounds: CGRect) {
        guard let marked = composition.marked, !marked.isEmpty else {
            attributedStringValue = NSAttributedString(string: "")
            isHidden = true
            return
        }
        let text = NSMutableAttributedString(string: marked, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        // Both ranges are UTF-16; subtract only after clamping to avoid NSNotFound overflow.
        let start = min(max(0, composition.markedSelection.location), text.length)
        let selection = NSRange(location: start, length: min(max(0, composition.markedSelection.length), text.length - start))
        if selection.length > 0 {
            text.addAttributes([.backgroundColor: NSColor.selectedTextBackgroundColor,
                                .foregroundColor: NSColor.selectedTextColor], range: selection)
        }
        attributedStringValue = text
        sizeToFit()
        frame.size.width = min(frame.width, max(0, bounds.width))
        frame.origin = CGPoint(x: bounds.midX - frame.width / 2, y: bounds.minY)
        isHidden = false
    }
}
#endif

#if !POINTER_POLICY_TEST
/// Attach above the existing renderer with identical bounds; call refresh when client state changes.
/// Keyboard events use either the native text system or the existing HID forwarder.
final class StreamInputView: NSView, NSTextInputClient {
    private var keys = MacKeyForwarder()
    private var composition = TextComposition()
    private let preedit = MacPreeditLabel()
    private var interpreting: NSEvent?
    private func emit(_ events: [InputEvent]) { for event in events { client?.sendInput(event) } }
    private func emitText(_ outputs: [TextComposition.Output]) {
        for output in outputs {
            switch output {
            case .text(let text): client?.sendInput(.text(text))
            case .backspaces(let count):
                for _ in 0..<count { emit(KeyChord.press(0x2A, with: [])) }
            }
        }
        updatePreedit()
    }
    private func updatePreedit() {
        preedit.update(composition, in: bounds)
        inputContext?.invalidateCharacterCoordinates()
    }
    override func layout() {
        super.layout()
        updatePreedit()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard enabled, !MacKeyForwarder.staysLocal(keyCode: event.keyCode, modifiers: event.modifierFlags)
                || MacKeyForwarder.releasesKeyboard(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return false }
        guard event.modifierFlags.contains(.command) else { return false }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard enabled else { return }
        if MacKeyForwarder.releasesKeyboard(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            releaseInput(); window?.makeFirstResponder(nil); return
        }
        guard !MacKeyForwarder.staysLocal(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
            releaseInput(); super.keyDown(with: event); return
        }
        if (event.isARepeat && MacKeyForwarder.usage(forKeyCode: event.keyCode).map { keys.down.contains($0) } == true) || MacKeyForwarder.rawKey(event, composing: composition.isComposing, hostKeyRepeat: client?.hostKeyRepeat) {
            emitText(composition.forget())
            emit(keys.keyDown(event, hostKeyRepeat: client?.hostKeyRepeat))
        } else {
            interpreting = event
            interpretKeyEvents([event])
            interpreting = nil
        }
    }
    override func keyUp(with event: NSEvent) { emit(keys.keyUp(event)) }
    override func flagsChanged(with event: NSEvent) {
        guard enabled else { return }
        if MacKeyForwarder.staysLocal(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            emit(keys.releaseAll()); return
        }
        // Text input owns option/shift for dead keys and composition; raw downs carry their flags.
        if !composition.isComposing { emit(keys.flagsChanged(event)) }
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard enabled else { return }
        let text = (string as? NSAttributedString)?.string ?? (string as? String ?? "")
        if replacementRange.location == NSNotFound { emitText(composition.insert(text)) }
        else { emitText(composition.replace(replacementRange, with: text)) }
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard enabled else { return }
        if replacementRange.location != NSNotFound, !composition.isComposing { composition.select(replacementRange) }
        emitText(composition.setMarked((string as? NSAttributedString)?.string ?? (string as? String ?? ""), selected: selectedRange))
    }
    func unmarkText() { emitText(composition.unmark()) }
    func hasMarkedText() -> Bool { composition.isComposing }
    func markedRange() -> NSRange { composition.markedRange ?? NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { composition.selectedRange }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let document = composition.document as NSString
        guard range.location != NSNotFound, range.location <= document.length else { return nil }
        let valid = NSIntersectionRange(range, NSRange(location: 0, length: document.length))
        actualRange?.pointee = valid
        return NSAttributedString(string: document.substring(with: valid))
    }
    func characterIndex(for point: NSPoint) -> Int { composition.selectedRange.location }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = composition.selectedRange
        let anchor = preedit.isHidden ? NSRect(x: bounds.midX, y: bounds.minY, width: 1, height: 20) : preedit.frame
        return window?.convertToScreen(convert(anchor, to: nil)) ?? .zero
    }
    override func doCommand(by selector: Selector) {
        guard enabled else { return }
        if selector == #selector(NSResponder.deleteBackward(_:)) { emitText(composition.deleteBackward()); return }
        guard let event = interpreting else { return }
        emitText(composition.forget())
        if MacKeyForwarder.usage(forKeyCode: event.keyCode) != nil {
            emit(keys.keyDown(event, hostKeyRepeat: client?.hostKeyRepeat))
        } else if selector == #selector(NSResponder.insertNewline(_:)) {
            client?.sendInput(.text("\n"))
        } else if selector == #selector(NSResponder.insertTab(_:)) {
            client?.sendInput(.text("\t"))
        }
    }

    var client: StreamClient? {
        willSet { releaseInput() }
        didSet {
            connection = client?.$connected.sink { [weak self] connected in
                if !connected { self?.releaseInput() }
            }
            refresh()
        }
    }
    private var connection: AnyCancellable?
    private var keyUpMonitor: Any?
    private var held: Set<Int> = []
    private var lastPoint = CGPoint(x: 0.5, y: 0.5)
    private var observers: [NSObjectProtocol] = []
    private var tracking: NSTrackingArea?
    private var scrolling = false
    private var momentum = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var enabled: Bool {
        MacPointerGeometry.acceptsInput(keyWindow: window?.isKeyWindow == true,
            firstResponder: window?.firstResponder === self, connected: client?.connected == true,
            paused: client?.inputPaused != false)
    }
    private var picture: CGRect { HEVCDisplayView.videoRect(in: bounds, videoSize: client?.videoSize ?? .zero) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(preedit)
        // NSWindow swallows Command-key ups; release our held keys before its dispatch.
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let ups = self.keys.keyUp(event)
            self.emit(ups)
            return ups.isEmpty ? event : nil
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                self.releaseInput()
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseInput() })
        observers.append(center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseInput() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseInput() })
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit {
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        releaseInput()
        super.viewWillMove(toWindow: newWindow)
    }
    override func resignFirstResponder() -> Bool { releaseInput(); return super.resignFirstResponder() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    func refresh() {
        if !enabled { releaseInput() }
        window?.invalidateCursorRects(for: self)
    }
    func releaseInput() {
        if client?.connected == true, client?.inputPaused == false { emitText(composition.forget()) }
        emit(keys.releaseAll())
        composition = TextComposition()
        updatePreedit()
        inputContext?.discardMarkedText()
        for button in held.sorted() { send(button == 0 ? .leftUp : .rightUp, at: lastPoint) }
        held.removeAll()
        if scrolling { boundary(.ended) }
        if momentum { boundary(.momentumEnded) }
        scrolling = false
        momentum = false
        NSCursor.arrow.set()
    }
    private func send(_ action: PointerAction, at point: CGPoint) {
        client?.sendInput(.pointer(action, x: point.x, y: point.y))
    }
    private func location(_ event: NSEvent, clamp: Bool = false) -> CGPoint? {
        MacPointerGeometry.point(convert(event.locationInWindow, from: nil), in: picture, clamp: clamp)
    }
    private func down(_ event: NSEvent, button: Int) {
        guard client?.connected == true, client?.inputPaused == false, window?.isKeyWindow == true,
              let point = location(event) else { return }
        window?.makeFirstResponder(self)
        guard enabled, held.insert(button).inserted else { return }
        emitText(composition.forget())
        lastPoint = point
        send(button == 0 ? .leftDown : .rightDown, at: point)
    }
    private func up(_ event: NSEvent, button: Int) {
        guard held.remove(button) != nil else { return }
        lastPoint = location(event, clamp: true) ?? lastPoint
        send(button == 0 ? .leftUp : .rightUp, at: lastPoint)
        cursorUpdate(with: event)
    }
    override func mouseDown(with event: NSEvent) { down(event, button: 0) }
    override func rightMouseDown(with event: NSEvent) { down(event, button: 1) }
    override func mouseUp(with event: NSEvent) { up(event, button: 0) }
    override func rightMouseUp(with event: NSEvent) { up(event, button: 1) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        guard enabled, let point = location(event, clamp: !held.isEmpty) else { NSCursor.arrow.set(); return }
        lastPoint = point
        send(.move, at: point)
        cursorUpdate(with: event)
    }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func cursorUpdate(with event: NSEvent) {
        guard enabled, location(event) != nil, let shape = client?.cursorShape else { NSCursor.arrow.set(); return }
        let image = shape.image.copy() as! NSImage
        image.size = shape.size
        NSCursor(image: image, hotSpot: shape.hotspot).set()
    }
    private func boundary(_ phase: ScrollPhase) {
        client?.sendInput(.scrollGesture(phase, x: lastPoint.x, y: lastPoint.y))
    }
    override func scrollWheel(with event: NSEvent) {
        guard enabled, let point = location(event, clamp: scrolling || momentum) else { return }
        lastPoint = point
        let phases = MacPointerGeometry.phases(event.phase, momentum: false) + MacPointerGeometry.phases(event.momentumPhase, momentum: true)
        for phase in phases where phase == .began || phase == .momentumBegan { boundary(phase) }
        // AppKit already applies the local Natural Scrolling preference. Never synthesize a coast.
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        client?.sendInput(.scroll(x: point.x, y: point.y, dx: event.scrollingDeltaX * unit / picture.width, dy: event.scrollingDeltaY * unit / picture.height))
        for phase in phases where phase == .ended || phase == .momentumEnded { boundary(phase) }
        if phases.contains(.began) { scrolling = true }
        if phases.contains(.ended) { scrolling = false }
        if phases.contains(.momentumBegan) { momentum = true }
        if phases.contains(.momentumEnded) { momentum = false }
    }
}
#endif

#if !POINTER_POLICY_TEST
/// One native surface owns geometry and pointer input; the renderer remains non-hit-testing.
final class ViewerSurface: NSView {
    let input = StreamInputView(frame: .zero)
    private let client: StreamClient
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var lastReport = -Double.infinity
    private var source: StreamSource?

    init(client: StreamClient) {
        self.client = client
        super.init(frame: .zero)
        addSubview(client.displayView)
        addSubview(input)
        input.client = client
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didEndLiveResizeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let window = note.object as? NSWindow, window !== self.window { return }
                self.report()
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    override func layout() {
        super.layout()
        client.displayView.frame = bounds
        input.frame = bounds
        input.refresh()
        if !inLiveResize || ProcessInfo.processInfo.systemUptime - lastReport >= 0.1 { report(force: false) }
        else {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.report(force: false) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
    func refresh() {
        input.refresh()
        let changed = source != client.active
        source = client.active
        report(force: changed)
    }
    private func report(force: Bool = true) {
        pending?.cancel()
        pending = nil
        guard window != nil, bounds.width > 0, bounds.height > 0, client.connected else { return }
        let fps = MacViewportRate.wanted(screen: window?.screen?.maximumFramesPerSecond ?? 60,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, away: client.awayCapsFrameRate)
        let viewport = Viewport(width: bounds.width, height: bounds.height,
            scale: client.lastViewport?.scale, localCursor: true, fps: fps)
        guard force || viewport != client.lastViewport else { return }
        lastReport = ProcessInfo.processInfo.systemUptime
        client.sendViewport(viewport)
    }
    func detach() {
        pending?.cancel()
        pending = nil
        input.releaseInput()
        input.client = nil
    }
}
#endif

enum MacViewportRate {
    static func wanted(screen: Int, lowPower: Bool, away: Bool) -> Int {
        let rate = max(30, screen)
        return lowPower || away ? min(60, rate) : rate
    }
}
