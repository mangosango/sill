import AppKit
import Combine
import StreamProtocol

// No network, defaults, Keychain, pasteboard, decoder or desktop input in this fixture.
final class StreamClient {
    @Published var connected = true
    var inputPaused = false
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
// Pretend focus without ordering a window or activating this test process.
final class InputWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
