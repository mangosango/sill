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
check(state.window === window, "Observe only the attached window")
check(window.delegate is ViewerFullScreenDelegate, "Install supported fullscreen delegate hook")
check(window.delegate?.windowShouldClose?(window) == false && original.closeQueries == 1, "Forward SwiftUI close decisions")
let proposed: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
let options = window.delegate!.window!(window, willUseFullScreenPresentationOptions: proposed)
check(original.optionQueries == 1, "Consult original fullscreen policy")
check(options.contains(.disableProcessSwitching), "Preserve original delegate additions")
check(options.contains(.autoHideToolbar), "Native toolbar intentionally auto-hides")
check(options.contains(.autoHideMenuBar), "Toolbar auto-hide has required menu-bar option")
check(options.contains(.autoHideDock), "Preserve native Dock behavior")
let initialFrame = window.frame
NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
check(releases == 1, "Green-button fullscreen also releases input")
probe.changeMode(true)
check(window.frame == initialFrame, "Never resize during fullscreen transition")
NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
check(state.fullScreen, "Publish fullscreen entry for local controls and command label")
NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
check(releases == 2, "Exit also releases held input")
NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
check(!state.fullScreen, "Publish fullscreen exit")
NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
check(closes == 1, "Actual close ends session")
probe.removeFromSuperview()
check(window.delegate === original, "Restore original delegate after detach")
check(!window.isVisible, "Fixture never displays the window")
print("mac-viewer-window: \(checks) behavioral checks passed; live fullscreen not exercised")
}
