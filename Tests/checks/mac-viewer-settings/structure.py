from pathlib import Path

source = Path('MacClient/ViewerSettings.swift').read_text()
checks = {
    'three ordered panes': 'case general, sharing, remoteMac',
    'native toolbar panes': 'tabStyle = .toolbar',
    'icon and label': 'displayMode = .iconAndLabel',
    'stable toolbar': 'allowsUserCustomization = false',
    'no minimize or zoom': 'window.styleMask = [.titled, .closable]',
    'auxiliary beside fullscreen session': 'window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]',
    'host-reported away scope': 'if let away = client.settings.host?.away',
    'connection-specific quality scope': 'if away.thisConnectionAway',
    'away edits preserve home defaults': 'saved away settings, not its home defaults',
    'home edits preserve away defaults': 'Its saved away settings stay unchanged.',
    'mixed-session quality explanation': 'if !away.awayRunning',
    'older-host scope not inferred': 'This host does not report separate home and away quality settings.',
    'screen-capped viewport': 'area.height - chrome',
    'grouped forms': '.formStyle(.grouped)',
    'pane restoration': 'pane ?? saved ?? .general',
    'local mute scope': 'Only silences this viewer.',
    'remote explicit scope': 'for all connected devices, not just this viewer',
    'co-resident warning': 'may forward received clipboard text to its devices',
    'retains errors': 'if let problem = client.settingsProblem',
    'retains pending': '!client.settings.pending.isEmpty',
    'retains clipboard status': 'if let note = client.clipboardNote',
    'remote lock/disconnect gate': 'client.connected && !client.macLocked && client.settings.displayed != nil',
    'wireless capability gate': 'client.remoteRoute == nil && client.settings.host?.takesDirectWireless == true',
    'virtual display capability gate': 'client.settings.host?.virtualDisplayAvailable == true || client.settings.displayed?.virtualDisplay == true',
    'stale optional capability gate': 'client.settings.displayed?[keyPath: key] != nil',
}
for name, text in checks.items():
    assert text in source, name
assert source.count('client.connectedAt == session') == 2, 'both binding types reject stale sessions'
assert source.count('releaseInput()\n            guard canEditRemote') == 2, 'release before either remote mutation'
assert 'releaseInput()\n        let saved' in source, 'release before opening Settings'
assert 'transferLocalClipboard(' not in source, 'settings must never transfer text'
assert 'import SillHostCore' not in source, 'no host linkage'
assert 'runModal' not in source, 'no modal loop'
print(f'mac-viewer-settings: {len(checks) + 6} structural assertions passed')
