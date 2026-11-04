#!/usr/bin/env python3
"""Native controls wiring guard; does not launch an app or access private data."""
from pathlib import Path
source = (Path(__file__).resolve().parents[3] / 'MacClient/SillViewerApp.swift').read_text()
for action in ['client.select(.desktop)', 'client.select(.window(window.id))',
               'client.launch(bundleID: app.bundleID)', 'client.disconnect()',
               'client.transferLocalClipboard()', 'client.changeSettings(change($0))',
               'client.setSoundMuted($0)']:
    assert 'releasePicture(); ' + action in source, action
for guard in ['client.textScaleOffersOff', 'client.textScaleSelectable',
              'TextScale.scale(at: value)', 'client.remoteRoute != nil',
              'takesDirectWireless != true', 'ClipboardPolicy.hostTakes(client.hostClipboard)',
              'LockedMac.title', 'LockedMac.detail', 'client.settings.displayed']:
    assert guard in source, guard
assert 'may forward received clipboard text to its devices' in source
assert 'remote Command-V will use the remote clipboard' in source
assert 'NSPasteboard' not in source
assert 'send(.changeSettings' not in source
print('viewer-controls: release ordering, shared policies, clipboard distinction and warning passed')
pointer = (Path(__file__).resolve().parents[3] / 'MacClient/StreamInputView.swift').read_text()
assert '-> ViewerSurface { ViewerSurface(client: client) }' in source
assert 'dismantleNSView' in source and 'view.detach()' in source
for contract in ['addSubview(client.displayView)\n        addSubview(input)',
                 'input.frame = bounds', 'client.displayView.frame = bounds',
                 'NSWindow.didEndLiveResizeNotification', 'NSWindow.didChangeScreenNotification',
                 'window?.screen?.maximumFramesPerSecond', 'systemUptime - lastReport >= 0.1',
                 'report(force: changed)', 'scale: client.lastViewport?.scale',
                 'input.releaseInput()\n        input.client = nil']:
    assert contract in pointer, contract
assert 'override func hitTest(_ point: NSPoint) -> NSView? { nil }' in (Path(__file__).resolve().parents[3] / 'MacClient/HEVCDisplayView.swift').read_text()
print('viewer surface: renderer/input attachment, viewport and detach contracts passed')
