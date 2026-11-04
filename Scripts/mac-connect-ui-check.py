#!/usr/bin/env python3
"""Structural UI wiring guard; no app launch or access to user data."""
from pathlib import Path

source = Path(__file__).resolve().parents[1] / 'MacClient/SillViewerApp.swift'
s = source.read_text()
assert s.count('StreamClient()') == 1, 'Only the app owns a session'
assert 'WindowGroup(' not in s, 'The viewer is a single window'
assert '.onOpenURL' not in s, 'Pasted links only; no claimed URL scheme'
assert 'NSPasteboard' not in s, 'Only explicit system PasteButton reads clipboard'
assert 'client.pair(link:' not in s, 'Links must go through confirmation'
assert 'case .failure(.pairingLink):' in s, 'Address field links also need confirmation'
assert s.count('client.pendingLink = link') == 2
assert s.count('client.confirmPendingLink()') == 1
for call in ['client.connect(to: mac)', 'client.connectRemotely(mac.macID)',
             'client.pairHome(code: code)',
             'client.pairTyped(code: code, address: address, overlay: false)',
             'client.cancelPairing()', 'client.forget(id)',
             '.onDisappear { client.disconnect() }']:
    assert call in s, call
assert 'client.savedMacs.remove' not in s, 'Removal must retain shared persistence rules'
print('Connect UI: single owner/window, confirmed links, explicit paste and shared actions passed')
