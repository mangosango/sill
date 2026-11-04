import AppKit
import SwiftUI

extension Notification.Name {
    static let viewerOpenRemoteMenus = Notification.Name("SillViewerOpenRemoteMenus")
}

@MainActor
final class ViewerWindowState: ObservableObject {
    weak var window: NSWindow?
    @Published var fullScreen = false
}

enum ViewerWindowPolicy {
    static func recovery(notice: String?, noSource: Bool, hasVideo: Bool, slowLink: Bool) -> String? {
        if let notice { return notice }
        if noSource { return "No source is streaming. Choose Desktop, a window or an app from Source." }
        if !hasVideo { return "Waiting for the remote picture…" }
        if slowLink { return "The connection is slow. The remote picture may be delayed." }
        return nil
    }
}

/// Interpose only the documented fullscreen-options hook; all other delegate messages go to SwiftUI.
final class ViewerFullScreenDelegate: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    init(original: NSWindowDelegate?) { self.original = original }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        let options = original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
        return options.union([.fullScreen, .autoHideMenuBar, .autoHideToolbar])
    }
}

/// Observe actual window lifecycle, never treating view disappearance as close.
struct ViewerWindowReader: NSViewRepresentable {
    let state: ViewerWindowState
    let connected: Bool
    let close: () -> Void
    let release: () -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.state = state
        probe.close = close
        probe.release = release
        probe.connected = connected
        return probe
    }
    func updateNSView(_ view: Probe, context: Context) { view.changeMode(connected) }

    final class Probe: NSView {
        weak var state: ViewerWindowState?
        var close: (() -> Void)?
        var release: (() -> Void)?
        var connected = false
        private var tokens: [NSObjectProtocol] = []
        private var chooserFrame: NSRect?
        private var sessionFrame: NSRect?
        private var transitioning = false
        private weak var installedWindow: NSWindow?
        private var fullScreenDelegate: ViewerFullScreenDelegate?

        private func restoreDelegate() {
            if let installedWindow, let fullScreenDelegate, installedWindow.delegate === fullScreenDelegate {
                installedWindow.delegate = fullScreenDelegate.original
            }
            fullScreenDelegate = nil
            installedWindow = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            restoreDelegate()
            guard let window else { return }
            let proxy = ViewerFullScreenDelegate(original: window.delegate)
            fullScreenDelegate = proxy
            installedWindow = window
            window.delegate = proxy
            state?.window = window
            window.toolbarStyle = .unifiedCompact
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.minSize = NSSize(width: 480, height: 320)
            observe(NSWindow.willCloseNotification, window: window) { [weak self] in self?.close?() }
            observe(NSWindow.willEnterFullScreenNotification, window: window) { [weak self] in
                self?.release?()
                self?.transitioning = true
            }
            observe(NSWindow.willExitFullScreenNotification, window: window) { [weak self] in
                self?.release?()
                self?.transitioning = true
            }
            observe(NSWindow.didEnterFullScreenNotification, window: window) { [weak self] in
                self?.transitioning = false
                self?.state?.fullScreen = true
            }
            observe(NSWindow.didExitFullScreenNotification, window: window) { [weak self] in
                self?.transitioning = false
                self?.state?.fullScreen = false
            }
        }

        private func observe(_ name: Notification.Name, window: NSWindow, action: @escaping () -> Void) {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in action() })
        }

        func changeMode(_ next: Bool) {
            guard next != connected else { return }
            connected = next
            guard let window, !transitioning, !window.styleMask.contains(.fullScreen) else { return }
            if next {
                chooserFrame = window.frame
                resize(to: sessionFrame ?? NSRect(origin: window.frame.origin, size: NSSize(width: 960, height: 640)))
            } else {
                sessionFrame = window.frame
                if let chooserFrame { resize(to: chooserFrame) }
            }
        }

        private func resize(to proposed: NSRect) {
            guard let window, let screen = window.screen else { return }
            let visible = screen.visibleFrame
            var frame = proposed
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: true)
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
            if let installedWindow, let fullScreenDelegate, installedWindow.delegate === fullScreenDelegate {
                installedWindow.delegate = fullScreenDelegate.original
            }
        }
    }
}
