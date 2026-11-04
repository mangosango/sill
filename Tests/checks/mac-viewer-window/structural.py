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
assert 'if !input.controlling' in app and 'Button("Exit Full Screen")' in app
assert 'window.window?.attachedSheet == nil' in app and 'NSApp.modalWindow == nil' in app
assert 'guard !input.controlling, window.fullScreen' in app
assert 'window.window?.toggleFullScreen(nil)' in app
assert '!transitioning, !window.styleMask.contains(.fullScreen)' in window
assert window.count('self?.release?()') == 2, 'Both native fullscreen transitions release input'
assert 'return original' in window and 'installedWindow.delegate = fullScreenDelegate.original' in window
assert 'original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions)' in window
assert '.autoHideToolbar' in window
assert app.count('ToolbarItem {') == 3, 'Only source, input and session actions are visible'
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
assert 'session.input.release(); client.transferLocalClipboard()' in app
assert 'client.macLocked || !ClipboardPolicy.hostTakes(client.hostClipboard)' in app
assert 'case .window(let id)' in app and '.navigationTitle(title)' in app
print('mac-viewer-window: structural guardrails passed (runtime appearance/input not exercised)')
