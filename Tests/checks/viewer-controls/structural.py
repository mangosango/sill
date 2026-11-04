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
assert 'Remote Command-V uses the remote clipboard' in source
assert 'NSPasteboard' not in source
assert 'send(.changeSettings' not in source
print('viewer-controls: release ordering, shared policies, clipboard distinction and warning passed')
