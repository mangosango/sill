#!/usr/bin/env python3
"""Structural UI wiring guard; no app launch or access to user data."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = (root / 'MacClient/SillViewerApp.swift').read_text()
chooser = (root / 'MacClient/ViewerConnectView.swift').read_text()
window = (root / 'MacClient/ViewerWindow.swift').read_text()
source = app + chooser
assert app.count('StreamClient()') == 1, 'Only the app owns a session'
assert 'WindowGroup(' not in app, 'The viewer is a single window'
assert '.onOpenURL' not in source, 'Pasted links only; no claimed URL scheme'
assert 'NSPasteboard' not in source, 'Only explicit system PasteButton reads clipboard'
assert 'client.pair(link:' not in chooser, 'Links must go through confirmation'
assert 'case .failure(.pairingLink):' in chooser, 'Address field links also need confirmation'
assert chooser.count('client.pendingLink = link') == 2
assert chooser.count('client.confirmPendingLink()') == 1
for call in ['client.connect(to: mac)', 'client.connectRemotely(mac.macID)',
             'client.pairHome(code: code)',
             'client.pairTyped(code: code, address: address, overlay: false)',
             'client.cancelPairing()', 'client.forget(id)', 'client.searchNearby()']:
    assert call in chooser, call
assert 'client.savedMacs.remove' not in chooser, 'Removal must retain shared persistence rules'
assert 'func disconnect() { input.release(); client.disconnect() }' in app
assert '.onDisappear' not in app, 'Presentation changes must not disconnect'
assert 'NSWindow.willCloseNotification' in window
assert 'ViewerChooserCommands()' in app, 'Chooser toolbar commands need menu equivalents'
print('Connect UI: single owner/window, confirmed links, nearby discovery and lifecycle passed')
