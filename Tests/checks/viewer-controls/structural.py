#!/usr/bin/env python3
"""Native controls integration guard; no app launch or access to private data."""
from pathlib import Path
root = Path(__file__).resolve().parents[3]
app = (root / 'MacClient/SillViewerApp.swift').read_text()
settings = (root / 'MacClient/ViewerSettings.swift').read_text()
window = (root / 'MacClient/ViewerWindow.swift').read_text()
for action in ['client.select(.desktop)', 'client.select(.window(window.id))',
               'client.launch(bundleID: app.bundleID)', 'client.transferLocalClipboard()',
               'client.setSoundMuted($0)']:
    assert 'session.input.release(); ' + action in app, action
assert 'func disconnect() { input.release(); client.disconnect() }' in app
assert 'releaseInput()\n            guard canEditRemote' in settings
assert 'client.changeSettings(change(value))' in settings
for guard in ['client.textScaleOffersOff', 'client.textScaleSelectable',
              'TextScale.scale(at: value)', 'ClipboardPolicy.hostTakes(client.hostClipboard)',
              'LockedMac.title', 'LockedMac.detail']:
    assert guard in app, guard
for guard in ['client.remoteRoute != nil', 'takesDirectWireless != true',
              'client.settings.displayed', 'client.connectedAt == session',
              'may forward received clipboard text to its devices',
              'it does not transfer local text.']:
    assert guard in settings, guard
assert 'NSPasteboard' not in app + settings
assert 'send(.changeSettings' not in app + settings
assert '.onDisappear' not in app, 'View transitions are not session close'
assert 'NSWindow.willCloseNotification' in window
assert 'ViewerSettingsWindowController(client: client' in app
for source in (app, settings):
    assert '@AppStorage("SillViewer.reverseScrolling") private var reverseScrolling = false' in source
assert 'view.input.reverseScrolling = reverseScrolling\n        view.refresh()' in app
print('viewer-controls: release ordering, scoped settings and clipboard safeguards passed')
pointer = (root / 'MacClient/StreamInputView.swift').read_text()
assert 'ViewerSurface(client: client, inputState: input)' in app
assert 'dismantleNSView' in app and 'view.detach()' in app
for contract in ['addSubview(client.displayView)\n        addSubview(input)',
                 'input.frame = bounds', 'client.displayView.frame = bounds',
                 'NSWindow.didEndLiveResizeNotification', 'NSWindow.didChangeScreenNotification',
                 'window?.screen?.maximumFramesPerSecond', 'systemUptime - lastReport >= 0.1',
                 'report(force: changed)', 'scale: client.lastViewport?.scale',
                 'inputState.unbind(input)\n        input.client = nil']:
    assert contract in pointer, contract
assert 'override func hitTest(_ point: NSPoint) -> NSView? { nil }' in (root / 'MacClient/HEVCDisplayView.swift').read_text()
print('viewer surface: renderer/input attachment, viewport and detach contracts passed')
