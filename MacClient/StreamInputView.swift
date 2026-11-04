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

#if !POINTER_POLICY_TEST
/// Attach above the existing renderer with identical bounds; call refresh when client state changes.
/// This surface deliberately implements no keyboard or text-input handling.
final class StreamInputView: NSView {
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
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                self.releaseInput()
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseInput() })
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    deinit {
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
    /// Later keyboard integration must release its held keys here too, before changing client.
    func releaseInput() {
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
