#!/usr/bin/env python3
"""Query audit and build-configuration fixtures: no Security or real keychain calls."""
from pathlib import Path
s = (Path(__file__).resolve().parents[2] / 'iOSClient/DeviceIdentity.swift').read_text()
assert 'object(forInfoDictionaryKey: "SillViewerKeychainGroup")' in s
assert 'String(group.dropFirst(11)) == bundle' in s
assert 'bundle.lowercased() != "me.saffer.sill.mac", bundle.lowercased() != "me.saffer.sill"' in s
assert 'else { return "invalid.sill.viewer.configuration" }' in s
for target in ('query', 'attributes'):
    block = f'{target}[kSecUseDataProtectionKeychain as String] = true\n        {target}[kSecAttrAccessGroup as String] = accessGroup'
    assert block in s, target
assert s.count('attributes[kSecUseDataProtectionKeychain as String] = true') == 2
assert 'privateAttributes[kSecAttrAccessGroup as String] = accessGroup' in s
for name in ('knownMissing', 'forget', 'read', 'readBack'):
    body = s.split(f'static func {name}(', 1)[1].split('\n    }', 1)[0]
    assert 'keyQuery(' in body, name
assert 'var deletion = keyQuery(currentTag)' in s
assert 'SPKI.fingerprint(of: $0) == want' in s
assert 'if status == errSecMissingEntitlement' in s
assert 'unsigned builds cannot pair' in s
# All added group constraints are macOS-only, preserving iOS queries.
active = False
for line in s.splitlines():
    if line.strip() == '#if os(macOS)': active = True
    if 'kSecAttrAccessGroup as String' in line: assert active
    if line.strip() in ('#endif', '#else'): active = False
print('Viewer identity static query audit passed (no keychain calls)')

# Execute only the configuration closure with fixtures, never DeviceIdentity/Security.
import subprocess
import tempfile
closure = s.split('static let accessGroup: String = {', 1)[1].split('\n    }()', 1)[0]
closure = closure.replace('Bundle.main', 'fixture')
source = '''import Foundation
struct Info {
    let bundleIdentifier: String?
    let group: String?
    func object(forInfoDictionaryKey: String) -> Any? { group }
}
func resolve(_ fixture: Info) -> String {
''' + closure + '''
}
for (team, bundle) in [("9B2KKVM937", "me.saffer.sill.viewer"), ("RPKWZLZ8NN", "com.sangjinlee.sill.viewer")] {
    let group = team + "." + bundle
    assert(resolve(Info(bundleIdentifier: bundle, group: group)) == group)
}
for fixture in [Info(bundleIdentifier: nil, group: nil),
                Info(bundleIdentifier: "me.saffer.sill.mac", group: "RPKWZLZ8NN.me.saffer.sill.mac"),
                Info(bundleIdentifier: "me.saffer.sill", group: "RPKWZLZ8NN.me.saffer.sill"),
                Info(bundleIdentifier: "com.example.viewer", group: "$(TEAM).com.example.viewer"),
                Info(bundleIdentifier: "com.example.viewer", group: "RPKWZLZ8NN.extra.com.example.viewer")] {
    assert(resolve(fixture) == "invalid.sill.viewer.configuration")
}
print("Viewer runtime configuration: default/custom and invalid fixtures passed; no Security calls")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(source)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
