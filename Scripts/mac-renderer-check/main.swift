import AppKit
import StreamProtocol

// Compile fixture only: the shared client is not yet macOS-buildable. This is exactly the
// CursorShape member the renderer consumes, not a replacement networking implementation.
enum StreamClient {
    struct CursorShape { let image: NSImage; let hotspot: CGPoint; let size: CGSize }
}

// Compile the intended attachment contract without opening a window or starting a decoder.
func attachmentContract(_ view: HEVCDisplayView, queue: DispatchQueue, sets: ParameterSets) {
    view.renderQueue = queue
    view.onVideoSize = { _ in }
    view.onVideoSizeForPointer = { _ in }
    view.onNeedsKeyframe = {}
    view.onPictureBack = {}
    view.setCursorShape(nil)
    view.setPointer(nil)
    queue.async {
        view.apply(sets)
        view.enqueue(Data(), isKeyframe: false)
        view.blank()
        view.clear()
        view.checkLayer("attachment check")
    }
}

let bounds = CGRect(x: 10, y: 20, width: 1000, height: 700)
precondition(HEVCDisplayView.videoRect(in: bounds, videoSize: .zero) == .zero)
precondition(HEVCDisplayView.videoRect(in: .zero, videoSize: CGSize(width: 100, height: 100)) == .zero)
precondition(HEVCDisplayView.videoRect(in: bounds, videoSize: CGSize(width: 1000, height: 500))
             == CGRect(x: 10, y: 120, width: 1000, height: 500))
precondition(HEVCDisplayView.videoRect(in: bounds, videoSize: CGSize(width: 500, height: 1000))
             == CGRect(x: 335, y: 20, width: 350, height: 700))
precondition(HEVCDisplayView.videoRect(in: bounds, videoSize: CGSize(width: 1000, height: 700)) == bounds)
print("Mac HEVCDisplayView: attachment contract compiled; 5 geometry checks passed (no view or decoder started).")
