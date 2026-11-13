import AppKit
import SwiftUI

extension Notification.Name {
    static let viewerOpenRemoteMenus = Notification.Name("SillViewerOpenRemoteMenus")
}

@MainActor
final class ViewerWindowState: ObservableObject {
    weak var window: NSWindow?
    @Published var fullScreen = false
    /// The pointer is where the frame's title bar is, or would be.
    @Published var chromeHover = false
    /// The floating window includes the frame's margins. Hidden, the window is just the picture,
    /// so every edge and corner of the picture resizes it, as in iPhone Mirroring.
    @Published var expanded = false
}

enum ViewerChromePolicy {
    /// The glass bar floats this far below the top in full screen.
    static let fullScreenInset: CGFloat = 10
    static let fullScreenHeight: CGFloat = 36
    /// The hover band in full screen: the bar and its margin.
    static let fullScreenBand = fullScreenInset * 2 + fullScreenHeight + 12
    /// In a window, the frame grows this far out from behind the picture, with a title bar on top.
    /// The sizes and the traffic light positions are those of iPhone Mirroring.
    static let margin: CGFloat = 8
    static let titlebar: CGFloat = 38
    static let insets = NSEdgeInsets(top: titlebar, left: margin, bottom: margin, right: margin)
    static let pictureRadius: CGFloat = 10
    static let frameRadius: CGFloat = 18
    static let lightsLeading: CGFloat = 9
    static let lightsPitch: CGFloat = 23
    /// After a click in the title bar, it stays this long once the pointer leaves, as in iPhone Mirroring.
    /// A hover alone hides it at once.
    static let linger: TimeInterval = 3
    /// The hidden title bar's area starts this far above the picture, so its top edge still resizes.
    static let resizeEdge: CGFloat = 6

    /// The title bar, in a view of `size` with y up; nil while it is hidden and outside the window.
    static func band(in size: CGSize, fullScreen: Bool, expanded: Bool) -> CGRect? {
        if fullScreen { return CGRect(x: 0, y: size.height - fullScreenBand, width: size.width, height: fullScreenBand) }
        guard expanded else { return nil }
        return CGRect(x: 0, y: size.height - titlebar, width: size.width, height: titlebar)
    }
    /// On screen, where the hidden title bar would be: above the window, which is just the picture.
    static func header(above picture: CGRect) -> CGRect {
        CGRect(x: picture.minX - margin, y: picture.maxY + resizeEdge,
               width: picture.width + margin * 2, height: titlebar - resizeEdge)
    }
    /// The window frame around a picture frame, and back. AppKit frames have y up.
    static func expanded(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - margin, y: frame.minY - margin,
               width: frame.width + margin * 2, height: frame.height + titlebar + margin)
    }
    static func collapsed(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + margin, y: frame.minY + margin,
               width: frame.width - margin * 2, height: frame.height - titlebar - margin)
    }

    /// A window size whose picture has the remote display's shape. Keep the width, or else the height.
    static func fitted(_ size: CGSize, aspect: CGSize, keepWidth: Bool, expanded: Bool) -> CGSize {
        guard aspect.width > 0, aspect.height > 0 else { return size }
        let ratio = aspect.width / aspect.height
        let horizontal = expanded ? margin * 2 : 0
        let vertical = expanded ? titlebar + margin : 0
        if keepWidth {
            return CGSize(width: size.width, height: ((size.width - horizontal) / ratio).rounded() + vertical)
        }
        return CGSize(width: ((size.height - vertical) * ratio).rounded() + horizontal, height: size.height)
    }
    /// A window's frame shows on hover, as in iPhone Mirroring; it never covers the picture.
    /// In full screen the bar shows, over a dimmed picture, whenever input is released.
    static func shows(connected: Bool, controlling: Bool, hover: Bool, fullScreen: Bool) -> Bool {
        connected && (fullScreen ? !controlling : hover)
    }
    /// The traffic lights follow the bar in a session window; full screen and the chooser keep them.
    static func trafficLights(session: Bool, fullScreen: Bool, chrome: Bool) -> Bool {
        !session || fullScreen || chrome
    }
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

/// Interpose only the documented fullscreen-options and resize hooks; all other delegate messages go to SwiftUI.
final class ViewerFullScreenDelegate: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    /// The remote display's shape while a window shows the Desktop; nil lets the window take any shape.
    var aspect: CGSize?
    var expanded = false
    /// The dimension a live resize follows, chosen once from its first change. Choosing again from
    /// each proposal flips between the two fits and makes the window flicker.
    private var keepWidth: Bool?
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
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let size = original?.windowWillResize?(sender, to: frameSize) ?? frameSize
        guard let aspect, !sender.styleMask.contains(.fullScreen) else { return size }
        if keepWidth == nil {
            guard size != sender.frame.size else { return size }
            keepWidth = size.width != sender.frame.width
        }
        return ViewerChromePolicy.fitted(size, aspect: aspect, keepWidth: keepWidth ?? true, expanded: expanded)
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        keepWidth = nil
        original?.windowDidEndLiveResize?(notification)
    }
}

/// A floating session window has no title bar, so the system draws no border around its clear
/// margin. Without a title bar, SwiftUI's window refuses key status and the Close and Minimize
/// commands beep. Overrides on the window's class keep them working for adopted windows only;
/// every other window takes the inherited behavior. The class itself never changes, because
/// AppKit observes the window with KVO. Full screen needs the title bar, so it comes back first.
enum ViewerFloatingWindow {
    private static var key = 0
    private static var holdKey = 0
    private static var patched: Set<ObjectIdentifier> = []

    static func adopt(_ window: NSWindow) {
        objc_setAssociatedObject(window, &key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // `type(of:)` asks -class, which hides KVO's subclass.
        let type: AnyClass = Swift.type(of: window)
        guard patched.insert(ObjectIdentifier(type)).inserted else { return }
        patch(type, #selector(getter: NSWindow.canBecomeKey))
        patch(type, #selector(getter: NSWindow.canBecomeMain))
        patch(type, #selector(NSWindow.performClose(_:))) { window, sender in
            if window.delegate?.windowShouldClose?(window) == false { return }
            window.close()
        }
        patch(type, #selector(NSWindow.performMiniaturize(_:))) { window, sender in window.miniaturize(sender) }
        patch(type, #selector(NSWindow.toggleFullScreen(_:)), always: true) { window, _ in holdTitle(window) }
    }

    /// Keep the title bar until the full screen transition ends. Restyling on the way would remove it.
    static func holdTitle(_ window: NSWindow) {
        objc_setAssociatedObject(window, &holdKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let frame = window.frame
        window.styleMask.insert(.titled)
        if window.frame != frame { window.setFrame(frame, display: true) }
    }
    static func holdsTitle(_ window: NSWindow) -> Bool { objc_getAssociatedObject(window, &holdKey) != nil }
    static func releaseTitle(_ window: NSWindow) {
        objc_setAssociatedObject(window, &holdKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Adopted and without a title bar.
    static func floats(_ window: NSWindow) -> Bool {
        objc_getAssociatedObject(window, &key) != nil && !window.styleMask.contains(.titled)
    }

    private static func patch(_ type: AnyClass, _ selector: Selector) {
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let inherited = unsafeBitCast(class_getMethodImplementation(type, selector)!, to: Getter.self)
        let block: @convention(block) (NSWindow) -> Bool = { window in
            floats(window) || inherited(window, selector)
        }
        class_replaceMethod(type, selector, imp_implementationWithBlock(block), "c@:")
    }

    /// Run `action` instead of the inherited method while floating; with `always`, before it.
    private static func patch(_ type: AnyClass, _ selector: Selector, always: Bool = false,
                              _ action: @escaping (NSWindow, AnyObject?) -> Void) {
        typealias Action = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let inherited = unsafeBitCast(class_getMethodImplementation(type, selector)!, to: Action.self)
        let block: @convention(block) (NSWindow, AnyObject?) -> Void = { window, sender in
            guard floats(window) else { return inherited(window, selector, sender) }
            action(window, sender)
            if always { inherited(window, selector, sender) }
        }
        class_replaceMethod(type, selector, imp_implementationWithBlock(block), "v@:@")
    }
}

/// Observe actual window lifecycle, never treating view disappearance as close.
struct ViewerWindowReader: NSViewRepresentable {
    let state: ViewerWindowState
    let connected: Bool
    var chrome = false
    var aspect: CGSize? = nil
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
    func updateNSView(_ view: Probe, context: Context) {
        view.changeMode(connected)
        view.showChrome(chrome)
        view.setAspect(aspect)
    }

    final class Probe: NSView {
        weak var state: ViewerWindowState?
        var close: (() -> Void)?
        var release: (() -> Void)?
        var connected = false
        private var chrome = false
        private var aspect: CGSize?
        private var band: NSTrackingArea?
        private var shadowTimer: Timer?
        private var tokens: [NSObjectProtocol] = []
        private var menuTokens: [NSObjectProtocol] = []
        private var chooserFrame: NSRect?
        private var sessionFrame: NSRect?
        private var transitioning = false
        /// While a menu from the bar is open, the pointer leaving the band must not hide the bar.
        private var menuTracking = false
        /// A click in the band focuses the bar, so it lingers after the pointer leaves.
        private var focused = false
        private var linger: Timer?
        var lingerDelay = ViewerChromePolicy.linger
        private var bandRect = NSRect.zero
        private var clickMonitor: Any?
        private var moveMonitors: [Any] = []
        private var expanded = false
        private var collapse: Timer?
        /// The window shrinks back after the frame's hide animation.
        var collapseDelay: TimeInterval = 0.4
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
            proxy.aspect = aspect
            proxy.expanded = expanded
            fullScreenDelegate = proxy
            installedWindow = window
            window.delegate = proxy
            state?.window = window
            window.toolbarStyle = .unifiedCompact
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.minSize = NSSize(width: 480, height: 320)
            applyStyle()
            observe(NSWindow.willCloseNotification, window: window) { [weak self] in self?.close?() }
            observe(NSWindow.didEndLiveResizeNotification, window: window) { [weak self] in self?.updateTrackingAreas() }
            menuTokens.forEach(NotificationCenter.default.removeObserver)
            menuTokens = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.trackMenu(name == NSMenu.didBeginTrackingNotification) }
                }
            }
            if clickMonitor == nil {
                // A local monitor sees the click before the button or frame under it takes it.
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    MainActor.assumeIsolated { self?.noteClick(in: event.window, at: event.locationInWindow) }
                    return event
                }
            }
            if moveMonitors.isEmpty {
                // The hidden title bar is outside the window, where no tracking area sees the pointer.
                // Watching moves needs no permission; only key events do.
                let moved: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
                moveMonitors = [NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved),
                                NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { moved($0); return $0 }].compactMap { $0 }
            }
            observe(NSWindow.willEnterFullScreenNotification, window: window) { [weak self] in
                self?.release?()
                self?.transitioning = true
            }
            observe(NSWindow.willExitFullScreenNotification, window: window) { [weak self] in
                self?.release?()
                self?.transitioning = true
            }
            observe(NSWindow.didEnterFullScreenNotification, window: window) { [weak self, weak window] in
                if let window { ViewerFloatingWindow.releaseTitle(window) }
                self?.transitioning = false
                self?.state?.fullScreen = true
                self?.applyStyle()
            }
            observe(NSWindow.didExitFullScreenNotification, window: window) { [weak self, weak window] in
                if let window { ViewerFloatingWindow.releaseTitle(window) }
                self?.transitioning = false
                self?.state?.fullScreen = false
                self?.applyStyle()
                self?.fit()
            }
        }

        private func observe(_ name: Notification.Name, window: NSWindow, action: @escaping () -> Void) {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in action() })
        }

        /// A session is content first: the picture floats in a clear, borderless window, and the
        /// frame shows only on hover. Full screen and the chooser have the system's title bar.
        private func applyStyle() {
            guard let window else { return }
            // AppKit keeps the content size across a style change; keep the frame instead.
            let frame = window.frame
            let floating = connected && !window.styleMask.contains(.fullScreen) && !ViewerFloatingWindow.holdsTitle(window)
            if floating { ViewerFloatingWindow.adopt(window) }
            window.toolbar?.isVisible = !connected
            if floating { window.styleMask.remove(.titled) } else { window.styleMask.insert(.titled) }
            window.hasShadow = true
            window.isOpaque = !floating
            // Full screen letterboxes the picture in black, as the picture view does.
            window.backgroundColor = floating ? .clear : connected ? .black : .windowBackgroundColor
            window.titlebarAppearsTransparent = connected
            window.titleVisibility = connected ? .hidden : .visible
            if connected { window.styleMask.insert(.fullSizeContentView) }
            else { window.styleMask.remove(.fullSizeContentView) }
            if window.frame != frame { window.setFrame(frame, display: true) }
            showChrome(chrome, force: true)
            updateTrackingAreas()
        }

        func showChrome(_ next: Bool, force: Bool = false) {
            guard force || next != chrome else { return }
            chrome = next
            guard let window else { return }
            if !window.isOpaque { followShadow() }
            let visible = ViewerChromePolicy.trafficLights(session: connected,
                fullScreen: window.styleMask.contains(.fullScreen), chrome: next)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = !visible
            }
        }

        /// A clear window's shadow follows its drawn pixels; redraw it while the frame animates.
        private func followShadow() {
            shadowTimer?.invalidate()
            var ticks = 0
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    ticks += 1
                    self?.window?.invalidateShadow()
                    if ticks >= 24 || self == nil { timer.invalidate() }
                }
            }
            shadowTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let band { removeTrackingArea(band) }
            band = nil
            guard connected, let window else { return }
            guard let rect = ViewerChromePolicy.band(in: bounds.size, fullScreen: window.styleMask.contains(.fullScreen),
                                                     expanded: expanded) else { bandRect = .zero; return }
            let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
            addTrackingArea(area)
            band = area
            bandRect = rect
            // A resize moves the edges under the pointer; the bar waits for its end.
            guard !window.inLiveResize else { return }
            if rect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { enter() } else { leave() }
        }
        override func mouseEntered(with event: NSEvent) { if window?.inLiveResize != true { enter() } }
        override func mouseExited(with event: NSEvent) { if !menuTracking, window?.inLiveResize != true { leave() } }

        /// While the frame is hidden, the pointer reaching where its title bar would be shows it.
        func pointerMoved(to point: NSPoint = NSEvent.mouseLocation) {
            guard let window, connected, !expanded, ViewerFloatingWindow.floats(window), !window.inLiveResize,
                  ViewerChromePolicy.header(above: window.frame).contains(point) else { return }
            enter()
        }

        func noteClick(in clicked: NSWindow?, at point: NSPoint) {
            guard clicked === window, connected, bandRect.contains(convert(point, from: nil)) else { return }
            focused = true
        }
        private func enter() {
            linger?.invalidate()
            linger = nil
            publish(hover: true)
        }
        private func leave() {
            guard focused else { return publish(hover: false) }
            guard linger == nil else { return }
            let timer = Timer(timeInterval: lingerDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.linger = nil
                    self?.focused = false
                    self?.publish(hover: false)
                }
            }
            linger = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        /// At the menu's end, the bar follows the pointer again.
        func trackMenu(_ open: Bool) {
            menuTracking = open
            if !open { updateTrackingAreas() }
        }
        /// AppKit calls these during SwiftUI's own updates; publish after them, and only changes.
        private func publish(hover: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let state else { return }
                if state.chromeHover != hover { state.chromeHover = hover }
                follow(hover)
            }
        }

        /// Grow the floating window at once as the bar shows; shrink it once the frame has hidden.
        private func follow(_ hover: Bool) {
            guard let window else { return }
            if hover {
                collapse?.invalidate()
                collapse = nil
                if !expanded, ViewerFloatingWindow.floats(window) { setExpanded(true) }
            } else if expanded, collapse == nil {
                let timer = Timer(timeInterval: collapseDelay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.collapse = nil
                        if self?.state?.chromeHover == false { self?.setExpanded(false) }
                    }
                }
                collapse = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        /// The picture's inset changes with the window frame in one pass, so the picture stays put.
        private func setExpanded(_ next: Bool, moveWindow: Bool = true) {
            guard next != expanded else { return }
            expanded = next
            state?.expanded = next
            fullScreenDelegate?.expanded = next
            if moveWindow, let window, ViewerFloatingWindow.floats(window) {
                let frame = next ? ViewerChromePolicy.expanded(window.frame) : ViewerChromePolicy.collapsed(window.frame)
                window.setFrame(frame, display: true)
            }
            updateTrackingAreas()
        }

        func setAspect(_ next: CGSize?) {
            fullScreenDelegate?.aspect = next
            guard next != aspect else { return }
            aspect = next
            fit()
        }

        /// Give the picture the remote display's shape, so it has no black bars. Keep the top edge.
        private func fit() {
            guard let aspect, let window, let screen = window.screen, connected, !transitioning,
                  !window.styleMask.contains(.fullScreen) else { return }
            let visible = screen.visibleFrame
            var size = ViewerChromePolicy.fitted(window.frame.size, aspect: aspect, keepWidth: true, expanded: expanded)
            if size.height > visible.height {
                size = ViewerChromePolicy.fitted(CGSize(width: size.width, height: visible.height), aspect: aspect,
                                                 keepWidth: false, expanded: expanded)
            }
            guard size != window.frame.size else { return }
            resize(to: NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height))
        }

        func changeMode(_ next: Bool) {
            guard next != connected else { return }
            let wasExpanded = expanded
            collapse?.invalidate()
            collapse = nil
            if !next { setExpanded(false, moveWindow: false) }
            connected = next
            applyStyle()
            guard let window, !transitioning, !window.styleMask.contains(.fullScreen) else { return }
            if next {
                chooserFrame = window.frame
                resize(to: sessionFrame ?? NSRect(origin: window.frame.origin, size: NSSize(width: 960, height: 640)))
                fit()
            } else {
                sessionFrame = wasExpanded ? ViewerChromePolicy.collapsed(window.frame) : window.frame
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
            shadowTimer?.invalidate()
            linger?.invalidate()
            collapse?.invalidate()
            moveMonitors.forEach(NSEvent.removeMonitor)
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            menuTokens.forEach(NotificationCenter.default.removeObserver)
            tokens.forEach(NotificationCenter.default.removeObserver)
            if let installedWindow, let fullScreenDelegate, installedWindow.delegate === fullScreenDelegate {
                installedWindow.delegate = fullScreenDelegate.original
            }
        }
    }
}
