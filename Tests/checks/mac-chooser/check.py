#!/usr/bin/env python3
"""Bounded source-contract checks; no app, persistence, or network is launched."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[3]
source_path = Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] != '--mutants' else root / 'MacClient/ViewerConnectView.swift'
source = source_path.read_text()
if '--mutants' in sys.argv:
    mutations = [
        ('return !saved.contains(id) && seen.insert(id).inserted', 'return seen.insert(id).inserted'),
        ('return !saved.contains(id) && seen.insert(id).inserted', 'return !saved.contains(id)'),
        ('guard let id = mac.macID else { return true }', 'guard let id = mac.macID else { return false }'),
        ('mac.door == .pairingRequired', 'mac.door == .plain'),
        ('client.remoteDial != nil', 'false'),
        ('Button("Search Nearby") { client.searchNearby() }', 'Button("Search Nearby") {}'),
        ('if client.showsNearbyHint {', 'if false {'),
        ('struct ViewerChooserCommands: Commands', 'struct MissingChooserCommands: Commands'),
    ]
    with tempfile.TemporaryDirectory(prefix='sill-chooser-mutants-') as directory:
        for index, (old, new) in enumerate(mutations):
            assert old in source
            mutant = Path(directory) / f'mutant-{index}.swift'
            mutant.write_text(source.replace(old, new, 1))
            result = subprocess.run([sys.executable, __file__, str(mutant)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            assert result.returncode != 0, f'mutant survived: {old}'
    print(f'mac-chooser: {len(mutations)} mutants rejected')
    sys.exit(0)
assert 'List(selection: $selection)' in source
assert 'Section("Paired Macs")' in source and 'Section("Available to Pair")' in source
assert source.count('.sheet(') == 1
for token in ['if client.showsNearbyHint {', 'if client.searchingNearby {',
              'Button("Search Nearby") { client.searchNearby() }',
              '"Looking on your network and nearby…"', 'struct ViewerChooserCommands: Commands',
              '.focusedSceneValue(\\.viewerChooserActions,', '@FocusedValue(\\.viewerChooserActions)',
              'CommandGroup(after: .newItem)']:
    assert token in source, token
for token in ['List(selection: $selection)', '.onKeyPress(.return)', 'primaryAction: { ids in',
              'Button("Forget Selected Mac…")', 'mac.door == .pairingRequired',
              '"Pair…"', '"Not found nearby"', 'client.remoteDial != nil',
              'client.connection != nil', 'Button("Cancel Connection") { client.disconnect() }']:
    assert token in source, token
assert 'Mac-to-Mac pairing does not use' not in source
assert 'Button("Forget…")' not in source
for token in ['client.connect(to: route)', 'client.connect(to: mac)',
              'client.connectRemotely(mac.macID)', 'client.cancelPendingLink()',
              'client.cancelPairing()', 'client.confirmPendingLink()',
              'client.pairHome(code: code)', 'client.pairTyped(code: code, address: address, overlay: false)',
              '.keyboardShortcut(.cancelAction)', 'client.homeAsk != nil',
              'Remove this viewer separately', '.accessibilityLabel("Mac address")']:
    assert token in source, token
assert 'savedByName' not in source  # A name match is not a recognized identity.
assert source.index('Button("Confirm Pairing")') < source.index('client.confirmPendingLink()')
body = source.split('private var available: [FoundMac] {', 1)[1].split('\n    }', 1)[0]
# Execute the production filter with tiny value fixtures, including equal names and name-only trust.
program = '''
struct FoundMac { let name: String; let macID: String? }
struct Saved { let macID: String }
struct Client { let savedMacs: [Saved]; let macs: [FoundMac] }
func available(_ client: Client) -> [FoundMac] {
''' + body + '''
}
let rows = [FoundMac(name: "Same", macID: "paired"),
            FoundMac(name: "Same", macID: nil),
            FoundMac(name: "Same", macID: nil),
            FoundMac(name: "New", macID: "new"),
            FoundMac(name: "Other route", macID: "new")]
let result = available(Client(savedMacs: [Saved(macID: "paired")], macs: rows))
assert(result.count == 3)
assert(result[0].macID == nil && result[1].macID == nil)
assert(result[2].macID == "new")
assert(available(Client(savedMacs: [], macs: [])).isEmpty)
print("mac-chooser: identity fixtures passed")
'''
# Compile the actual Foundation-only discovery decision, excluding unrelated protocol policy.
policy = (root / 'iOSClient/DiscoveryPolicy.swift').read_text().split('    static func isPeerToPeer', 1)[0] + '\n}\n'
program = policy + program + '''
var fresh = DiscoveryPolicy.Input(now: 4, connected: false, onNetwork: [], remembered: [],
    searchingSince: 0, askedNearby: false, nearbyRunning: false, listed: 0)
let before = DiscoveryPolicy.decide(fresh)
assert(before.showHint && !before.browseNearby)
fresh.askedNearby = true
assert(DiscoveryPolicy.decide(fresh).browseNearby)
fresh.connected = true
assert(!DiscoveryPolicy.decide(fresh).browseNearby)
fresh.connected = false
fresh.localNetworkDenied = true
assert(!DiscoveryPolicy.decide(fresh).browseNearby)
print("mac-chooser: fresh-viewer discovery policy passed")
'''
with tempfile.TemporaryDirectory(prefix='sill-mac-chooser-') as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'check'
    swift.write_text(program)
    subprocess.run(['xcrun', 'swiftc', '-j', '4', str(swift), '-o', str(binary)], check=True, timeout=40)
    subprocess.run([str(binary)], check=True, timeout=5)
subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', str(source_path)], check=True, timeout=20)
print('mac-chooser: source contracts and Swift parse passed')
