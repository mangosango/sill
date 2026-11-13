#!/usr/bin/env python3
"""Window-lane guardrails; deliberately does not claim live fullscreen/responder acceptance."""
from pathlib import Path

root = Path(__file__).resolve().parents[3]
app = (root / 'MacClient/SillViewerApp.swift').read_text()
window = (root / 'MacClient/ViewerWindow.swift').read_text()
menus = (root / 'MacClient/RemoteMenus.swift').read_text()

assert '.windowToolbarStyle(.unifiedCompact)' in app
assert 'Window("Macs", id: "viewer")' in app and 'WindowGroup' not in app
assert '.frame(minWidth: 480, minHeight: 320)' in app
assert '.defaultSize(width: 600, height: 460)' in app
assert '.onDisappear' not in app, 'Sheets/fullscreen must not disconnect the session'
assert 'NSWindow.willCloseNotification' in window and 'self?.close?()' in window
assert 'func disconnect() { input.release(); client.disconnect() }' in app
assert 'guard !started else { return }' in app
assert 'ViewerSurface(client: client, inputState: input)' in app
assert 'Label("Exit Full Screen"' in app and 'if fullScreen {' in app
assert 'hover: window.chromeHover, fullScreen: window.fullScreen)' in app and 'resizing' not in app, 'Resizing and the frame are independent'
assert 'activeState == .key ? AnyShapeStyle(.ultraThinMaterial)' in app, 'An inactive window has a solid frame'
assert 'Color.black.opacity(0.01)' not in app, 'A near-clear layer draws a faint shadow rectangle'
assert '.animation(nil, value: window.expanded)' in app, 'The picture moves with the window in one pass'
assert '.offset(x: chrome ? 0 : frameInset.leading, y: chrome ? 0 : frameInset.top)' in app and '.padding(chrome ? EdgeInsets() : frameInset)' in app, 'The frame grows from behind the picture'
assert 'Color.black.opacity(window.fullScreen && !input.controlling ? 0.4 : 0)' in app, 'Released full screen dims the picture'
assert 'Text(title).font(Font(NSFont.titleBarFont(ofSize: 0)))' in app, 'The frame shows the window title'
assert app.count('.ignoresSafeArea()') == 1 and app.index('.ignoresSafeArea()') < app.index('ViewerConnectView(client: client)'), 'Only the session ignores the safe area'
assert 'window.toolbar?.isVisible = !connected' in window, 'A session has no toolbar band'
assert 'view.layer?.masksToBounds = radius > 0' in app
assert 'client.active == .desktop && client.videoSize != .zero' in app, 'Only the Desktop locks the window shape'
assert '@objc func _mouseInGroup(_ button: NSButton) -> Bool' in app and 'NSWindow.standardWindowButton($0, for: mask)' in app
assert 'glassEffect(.regular, in: shape)' in app and 'background(.regularMaterial, in: shape)' in app
assert '.toolbar {' not in app and 'ToolbarItem' not in app, 'Session controls live on the glass bar, not a native toolbar'
assert 'window?.performDrag(with: event)' in app and 'override var mouseDownCanMoveWindow: Bool { true }' in app
assert 'window.window?.attachedSheet == nil' in app and 'NSApp.modalWindow == nil' in app
assert 'guard !input.controlling, window.fullScreen' in app
assert 'window.window?.toggleFullScreen(nil)' in app
assert '!transitioning, !window.styleMask.contains(.fullScreen)' in window
assert window.count('self?.release?()') == 2, 'Both native fullscreen transitions release input'
assert 'return original' in window and 'installedWindow.delegate = fullScreenDelegate.original' in window
assert 'original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions)' in window
assert '.autoHideToolbar' in window
assert 'window.titlebarAppearsTransparent = connected' in window and 'window.styleMask.insert(.fullSizeContentView)' in window
assert 'Text(client.status)' not in app, 'Normal video has no persistent status band'
assert 'ViewerWindowPolicy.recovery(notice: client.notice?.text' in app
assert 'window.fullScreen ? "Exit Full Screen" : "Enter Full Screen"' in app
assert '.allowsHitTesting(false).accessibilityHidden(true)' in app
for key in ['.keyboardShortcut(",", modifiers: .command)', '.keyboardShortcut("f", modifiers: [.control, .command])', '.keyboardShortcut("d", modifiers: [.command, .shift])']:
    assert key in app
for action in ['ViewerSourceMenu(session: session)', 'ViewerSessionActions(session: session)', 'ViewerControlCommand(session: session)']:
    assert action in app
assert 'button.window === window' in menus and 'button.menu?.popUp(positioning: nil' in menus
assert 'private var generation = 0' in menus, 'Keep native remote menu stale-response protection'
assert 'session.input.release(); session.client.transferLocalClipboard()' in app
assert 'if next != snapshot { snapshot = next }' in app, 'Menus republish only when what they show changes'
for menu in ['private struct ViewerSourceMenu', 'private struct ViewerSessionActions', 'private struct ViewerChrome']:
    body = app[app.index(menu):]
    body = body[:body.index('\n}\n')]
    assert 'ObservedObject private var client: StreamClient' not in body, menu + ' must not redraw for every client publish'
assert 'client.macLocked || !ClipboardPolicy.hostTakes(client.hostClipboard)' in app
assert 'case .window(let id)' in app and '.navigationTitle(title)' in app
assert 'RoundedRectangle(cornerRadius: chrome ? ViewerChromePolicy.frameRadius : ViewerChromePolicy.pictureRadius' in app, 'The hiding frame never gets rounder than the picture'
assert 'NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)' in app and '.inVisibleRect], owner: self))' not in app.split('struct ViewerTrafficLights')[1].split('struct ViewerTitlebarDrag')[0], 'The lights track their bounds'
print('mac-viewer-window: structural guardrails passed (runtime appearance/input not exercised)')
