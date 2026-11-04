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
    func sendInput(_ event: InputEvent) { events.append(event) }
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

// Pretend focus without ordering a window or activating this test process.
final class InputWindow: NSWindow {
    var pretendsKey = true
    override var isKeyWindow: Bool { pretendsKey }
}
