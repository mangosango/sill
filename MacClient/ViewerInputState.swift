import AppKit
import Combine

/// A picture click or toolbar action acquires control; focus and hovering alone do not.
@MainActor
final class ViewerInputState: ObservableObject {
    @Published private(set) var controlling = false
    @Published private(set) var captureFailure: MacKeyboardCaptureFailure?
    private let capture: MacKeyboardCapture
    private weak var view: StreamInputView?

    init(capture: MacKeyboardCapture? = nil) {
        self.capture = capture ?? MacKeyboardCapture()
    }

    func bind(_ view: StreamInputView) {
        release()
        self.view?.inputState = nil
        self.view = view
        view.inputState = self
    }

    func unbind(_ view: StreamInputView) {
        guard self.view === view else { return }
        release()
        view.inputState = nil
        self.view = nil
    }

    func release() {
        capture.stop()
        if controlling { controlling = false }
        view?.releaseHeldInput()
    }

    func takeControl() {
        guard let view, view.canTakeControl,
              let window = view.window, window.makeFirstResponder(view),
              window.firstResponder === view else { release(); return }
        guard !controlling else { return }
        if let failure = capture.start(for: view, onFailure: { [weak self] failure in
            self?.release()
            self?.captureFailure = failure
        }) {
            release()
            captureFailure = failure
            return
        }
        captureFailure = nil
        controlling = true
        view.lockPointerIfFullScreen()
    }
}
