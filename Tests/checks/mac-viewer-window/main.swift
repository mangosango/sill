import AppKit

MainActor.assumeIsolated {
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(condition(), message)
}

check(ViewerWindowPolicy.recovery(notice: nil, noSource: false, hasVideo: true, slowLink: false) == nil, "Normal video has no status band")
check(ViewerWindowPolicy.recovery(notice: "Update the remote Mac", noSource: true, hasVideo: false, slowLink: true) == "Update the remote Mac", "Explicit notice wins")
check(ViewerWindowPolicy.recovery(notice: nil, noSource: true, hasVideo: true, slowLink: false)?.contains("No source") == true, "Do not imply an old frame is live")
check(ViewerWindowPolicy.recovery(notice: nil, noSource: false, hasVideo: false, slowLink: false)?.contains("Waiting") == true, "Initial video wait is visible")
check(ViewerWindowPolicy.recovery(notice: nil, noSource: false, hasVideo: true, slowLink: true)?.contains("slow") == true, "Slow-link state is visible")
check(ViewerChromePolicy.shows(connected: true, controlling: false, hover: true, fullScreen: false), "Hovering the window shows the frame")
check(!ViewerChromePolicy.shows(connected: true, controlling: false, hover: false, fullScreen: false), "Moving away hides the frame")
check(ViewerChromePolicy.shows(connected: true, controlling: true, hover: true, fullScreen: false), "The frame never covers the picture, so it shows while controlling")
check(!ViewerChromePolicy.shows(connected: true, controlling: true, hover: true, fullScreen: true), "In full screen, the top belongs to the remote Mac while controlling")
check(ViewerChromePolicy.shows(connected: true, controlling: false, hover: false, fullScreen: true), "Released full screen always shows the glass bar")
check(!ViewerChromePolicy.shows(connected: false, controlling: false, hover: true, fullScreen: false), "The chooser has no session controls")
check(ViewerChromePolicy.fullScreenBand > ViewerChromePolicy.fullScreenInset + ViewerChromePolicy.fullScreenHeight, "The full screen band covers the floating bar")
check(ViewerChromePolicy.insets.top == ViewerChromePolicy.titlebar && ViewerChromePolicy.insets.left == ViewerChromePolicy.margin, "The picture sits below the title bar, inside the frame")
let display = CGSize(width: 1600, height: 1000)
check(ViewerChromePolicy.fitted(CGSize(width: 816, height: 999), aspect: display, keepWidth: true, expanded: true) == CGSize(width: 816, height: 546), "A wider drag keeps the width and fits the height to the remote display")
check(ViewerChromePolicy.fitted(CGSize(width: 999, height: 546), aspect: display, keepWidth: false, expanded: true) == CGSize(width: 816, height: 546), "A taller drag keeps the height and fits the width")
check(ViewerChromePolicy.fitted(CGSize(width: 800, height: 999), aspect: display, keepWidth: true, expanded: false) == CGSize(width: 800, height: 500), "A collapsed window is just the picture")
check(ViewerChromePolicy.fitted(CGSize(width: 999, height: 500), aspect: display, keepWidth: false, expanded: false) == CGSize(width: 800, height: 500), "A collapsed window fits by its height too")
check(ViewerChromePolicy.fitted(CGSize(width: 999, height: 546), aspect: .zero, keepWidth: true, expanded: true) == CGSize(width: 999, height: 546), "No video, no constraint")
let picture = CGRect(x: 100, y: 100, width: 800, height: 500)
check(ViewerChromePolicy.expanded(picture) == CGRect(x: 92, y: 92, width: 816, height: 546), "The frame grows out on every side, with the title bar on top")
check(ViewerChromePolicy.collapsed(ViewerChromePolicy.expanded(picture)) == picture, "Collapsing returns to the picture")
check(ViewerChromePolicy.band(in: picture.size, fullScreen: false, expanded: false) == nil, "Hidden, the picture itself never shows the bar")
let expandedBand = ViewerChromePolicy.band(in: CGSize(width: 816, height: 546), fullScreen: false, expanded: true)!
check(expandedBand == CGRect(x: 0, y: 546 - ViewerChromePolicy.titlebar, width: 816, height: ViewerChromePolicy.titlebar), "Shown, the band is the title bar")
let header = ViewerChromePolicy.header(above: picture)
let bar = ViewerChromePolicy.expanded(picture)
check(header.minY > picture.maxY && header.maxY == bar.maxY && header.minX == bar.minX && header.maxX == bar.maxX, "Hidden, the band is where the title bar would be, short of the picture's top edge so it still resizes")
check(ViewerChromePolicy.frameRadius > ViewerChromePolicy.pictureRadius, "The hidden frame stays behind the picture's corners")
check(!ViewerChromePolicy.trafficLights(session: true, fullScreen: false, chrome: false), "Traffic lights hide with the bar")
check(ViewerChromePolicy.trafficLights(session: true, fullScreen: false, chrome: true), "Traffic lights show with the bar")
check(ViewerChromePolicy.trafficLights(session: false, fullScreen: false, chrome: false), "The chooser keeps its traffic lights")
check(ViewerChromePolicy.trafficLights(session: true, fullScreen: true, chrome: false), "Full screen keeps the system's title bar")

// Hidden, disconnected AppKit fixture: no app run loop, defaults writes, devices or real input.
_ = NSApplication.shared
final class OriginalDelegate: NSObject, NSWindowDelegate {
    var closeQueries = 0
    var optionQueries = 0
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeQueries += 1; return false }
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        optionQueries += 1
        return proposedOptions.union(.disableProcessSwitching)
    }
}
let window = NSWindow(contentRect: NSRect(x: 10, y: 10, width: 600, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
let original = OriginalDelegate()
window.delegate = original
let probe = ViewerWindowReader.Probe()
let state = ViewerWindowState()
probe.state = state
var closes = 0
var releases = 0
probe.close = { closes += 1 }
probe.release = { releases += 1 }
window.contentView!.addSubview(probe)
/// Installs its toolbar when it moves to a titled frame, as SwiftUI's hosting view does.
final class ToolbarHost: NSView {
    let toolbar = NSToolbar(identifier: "chooser")
    override func viewDidMoveToWindow() {
        if let window, window.styleMask.contains(.titled) { window.toolbar = toolbar }
    }
}
let toolbarHost = ToolbarHost()
window.contentView!.addSubview(toolbarHost)
check(state.window === window, "Observe only the attached window")
check(window.delegate is ViewerFullScreenDelegate, "Install supported fullscreen delegate hook")
check(window.delegate?.windowShouldClose?(window) == false && original.closeQueries == 1, "Forward SwiftUI close decisions")
let proposed: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
let options = window.delegate!.window!(window, willUseFullScreenPresentationOptions: proposed)
check(original.optionQueries == 1, "Consult original fullscreen policy")
check(options.contains(.disableProcessSwitching), "Preserve original delegate additions")
check(options.contains(.autoHideToolbar), "Any native toolbar auto-hides")
check(options.contains(.autoHideMenuBar), "Toolbar auto-hide has required menu-bar option")
check(options.contains(.autoHideDock), "Preserve native Dock behavior")
let initialFrame = window.frame
NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
check(releases == 1, "Green-button fullscreen also releases input")
probe.changeMode(true)
check(window.frame == initialFrame, "Never resize during fullscreen transition")
check(window.titlebarAppearsTransparent && window.titleVisibility == .hidden && window.styleMask.contains(.fullSizeContentView), "A session draws under a transparent title bar")
check(!window.isOpaque && window.backgroundColor == .clear && window.hasShadow, "A session window is clear until the frame shows")
check(!window.styleMask.contains(.titled), "A floating session has no title bar, so no system border")
check(window.canBecomeKey && window.canBecomeMain, "A floating session still takes the keyboard")
check(window.standardWindowButton(.closeButton) == nil, "The frame draws its own traffic lights")
let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
check(!other.canBecomeKey, "Other borderless windows keep AppKit's rules")
ViewerFloatingWindow.holdTitle(window)
check(window.styleMask.contains(.titled), "Full screen gets the title bar back, though restyling runs on the way")
check(window.standardWindowButton(.closeButton)?.isHidden == true, "Lights stay hidden while the title bar comes back for full screen")
NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
check(!window.styleMask.contains(.titled) && !ViewerFloatingWindow.holdsTitle(window), "The transition's end lets the window float again")
window.performClose(nil)
check(original.closeQueries == 2 && closes == 0, "Close asks SwiftUI first, as a title bar's close button does")
let wide = window.frame.size
probe.setAspect(display)
let resized = window.delegate!.windowWillResize!(window, to: NSSize(width: wide.width + 100, height: wide.height))
check(resized == ViewerChromePolicy.fitted(NSSize(width: wide.width + 100, height: wide.height), aspect: display, keepWidth: true, expanded: false), "Resizing keeps the remote display's shape")
// AppKit applies the fit, then a corner drag moves only vertically: still width-led, no flip.
let start = window.frame
window.setFrame(NSRect(origin: start.origin, size: resized), display: false)
let next = window.delegate!.windowWillResize!(window, to: NSSize(width: resized.width, height: resized.height + 6))
check(next == resized, "One live resize follows one dimension, so it never flickers")
window.delegate!.windowDidEndLiveResize!(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
window.setFrame(start, display: false)
let tall = window.delegate!.windowWillResize!(window, to: NSSize(width: wide.width, height: wide.height + 100))
check(tall == ViewerChromePolicy.fitted(NSSize(width: wide.width, height: wide.height + 100), aspect: display, keepWidth: false, expanded: false), "A new resize from the bottom edge fits the width")
window.delegate!.windowDidEndLiveResize!(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
probe.setAspect(nil)
check(window.delegate!.windowWillResize!(window, to: NSSize(width: 700, height: 700)) == NSSize(width: 700, height: 700), "A remote window source takes any shape")
NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
check(state.fullScreen, "Publish fullscreen entry for local controls and command label")
NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
check(releases == 2, "Exit also releases held input")
NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
check(!state.fullScreen, "Publish fullscreen exit")
NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
check(closes == 1, "Actual close ends session")
probe.frame = window.contentView!.bounds
probe.autoresizingMask = [.width, .height]
probe.lingerDelay = 0.2
probe.collapseDelay = 0.15
probe.updateTrackingAreas()
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
// Hidden: the window is just the picture, and only where the title bar would be shows it.
let pictureFrame = window.frame
probe.pointerMoved(to: NSPoint(x: pictureFrame.midX, y: pictureFrame.maxY - 10))
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.expanded, "Hovering the picture's top does not show the bar")
probe.pointerMoved(to: NSPoint(x: pictureFrame.midX, y: pictureFrame.maxY + 2))
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.expanded, "The picture's top edge still resizes")
probe.pointerMoved(to: NSPoint(x: pictureFrame.midX, y: pictureFrame.maxY + 20))
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(state.expanded && window.frame == ViewerChromePolicy.expanded(pictureFrame), "Hovering where the title bar would be grows the window around the picture at once")
// The fixture's real pointer is elsewhere, so the band reports a leave at once.
check(!state.chromeHover && state.expanded, "The window waits for the frame's hide animation")
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
check(!state.expanded && window.frame == pictureFrame, "Then it is just the picture again, so its edges resize")
probe.collapseDelay = 60
probe.mouseEntered(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(state.expanded, "Shown for the focus checks")
// Shown: a hover alone hides at once; a click in the title bar makes it linger.
let top = NSPoint(x: 100, y: window.contentView!.bounds.height - 15)
state.chromeHover = true
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.chromeHover, "A hover alone hides the bar at once")
state.chromeHover = true
probe.noteClick(in: other, at: top)
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.chromeHover, "A click in another window does not focus the bar")
state.chromeHover = true
probe.noteClick(in: window, at: NSPoint(x: 100, y: 5))
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.chromeHover, "A click on the picture does not focus the bar")
state.chromeHover = true
probe.noteClick(in: window, at: top)
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(state.chromeHover, "A focused bar lingers after the pointer leaves")
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
check(!state.chromeHover, "Then it hides")
state.chromeHover = true
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!state.chromeHover, "The linger ends the focus; the next hover alone hides at once")
state.chromeHover = true
probe.trackMenu(true)
probe.mouseExited(with: NSEvent())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(state.chromeHover, "An open menu from the bar keeps the bar")
probe.trackMenu(false)
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(state.expanded, "Expanded when the session ends")
probe.changeMode(false)
check(!state.expanded, "The chooser forgets the frame")
check(!window.titlebarAppearsTransparent && window.titleVisibility == .visible && !window.styleMask.contains(.fullSizeContentView), "The chooser is a standard window")
check(window.styleMask.contains(.titled), "The chooser has its title bar back")
check(window.toolbar === toolbarHost.toolbar && window.toolbar?.isVisible == true, "The chooser keeps the toolbar SwiftUI installs while the title bar comes back")
let titleBar = window.contentView!.superview!.subviews.last!
check(window.standardWindowButton(.closeButton)!.isDescendant(of: titleBar), "Nothing covers the chooser's title bar")
check(window.isOpaque && window.backgroundColor != .clear, "The chooser is opaque")
check(window.standardWindowButton(.closeButton)?.isHidden == false, "The chooser keeps its traffic lights")
probe.removeFromSuperview()
check(window.delegate === original, "Restore original delegate after detach")
check(!window.isVisible, "Fixture never displays the window")
print("mac-viewer-window: \(checks) behavioral checks passed; live fullscreen not exercised")
}
