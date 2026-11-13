import AppKit
import Combine
import StreamProtocol

// No network, defaults, Keychain, pasteboard, decoder or desktop input in this fixture.
final class StreamClient {
    @Published var connected = true
    var inputPaused = false
    var macLocked = false
    var hostKeyRepeat: Int? = 1
    var videoSize = CGSize(width: 640, height: 400)
    var cursorShape: CursorShape?
    var active = StreamSource.desktop
    var awayCapsFrameRate = false
    var lastViewport: Viewport?
    let displayView = HEVCDisplayView(frame: .zero)
    var events: [InputEvent] = []
    var hostGestures: Int? = 1
    static var gesturesOn = true
    var gestures: [TrackpadGestures.Gesture] = []
    func sendInput(_ event: InputEvent) { events.append(event) }
    @discardableResult func sendGesture(_ gesture: TrackpadGestures.Gesture, fingers: Int) -> Bool { gestures.append(gesture); return true }
    func sendViewport(_ viewport: Viewport) { lastViewport = viewport }
}
struct CursorShape {
    let image: NSImage
    let size: CGSize
    let hotspot: CGPoint
}
final class HEVCDisplayView: NSView {
    static func videoRect(in bounds: CGRect, videoSize: CGSize) -> CGRect { bounds }
}
final class RecordingResponder: NSResponder {
    var keyCodes: [UInt16] = []
    override func keyDown(with event: NSEvent) { keyCodes.append(event.keyCode) }
}

// Only the OS boundary is fake; the production capture lifecycle/dispatcher runs unchanged.
@MainActor
final class RecordingKeyboardTap: MacKeyboardTap {
    var trusted = true
    var secureInput = false
    var enabled = false
    var installSucceeds = true
    var startCount = 0
    var receive: ((CGEventType, CGEvent) -> Unmanaged<CGEvent>?)?
    func start(receive: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) -> Bool {
        startCount += 1
        enabled = installSucceeds
        self.receive = receive
        return installSucceeds
    }
    func stop() { enabled = false; receive = nil }
}

// No hardware event source: scrollWheel reads only these overridden fields.
final class RecordingScrollEvent: NSEvent {
    var precise = true
    var gesturePhase: NSEvent.Phase = []
    var coastPhase: NSEvent.Phase = []
    override var locationInWindow: NSPoint { NSPoint(x: 320, y: 200) }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var scrollingDeltaX: CGFloat { 8 }
    override var scrollingDeltaY: CGFloat { -12 }
    override var phase: NSEvent.Phase { gesturePhase }
    override var momentumPhase: NSEvent.Phase { coastPhase }
}

// No hardware event source: a locked pointer reads only these deltas.
final class RecordingMoveEvent: NSEvent {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    override var deltaX: CGFloat { dx }
    override var deltaY: CGFloat { dy }
    override var locationInWindow: NSPoint { NSPoint(x: 320, y: 200) }
}

// Pretend focus and full screen without ordering a window or activating this test process.
final class InputWindow: NSWindow {
    var pretendsKey = true
    var pretendsFullScreen = false
    override var isKeyWindow: Bool { pretendsKey }
    override var styleMask: NSWindow.StyleMask {
        get { pretendsFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
}
