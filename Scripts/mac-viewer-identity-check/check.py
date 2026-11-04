#!/usr/bin/env python3
"""Static query audit only: never calls Security or reads a real keychain."""
from pathlib import Path
s = (Path(__file__).resolve().parents[2] / 'iOSClient/DeviceIdentity.swift').read_text()
assert 'static let accessGroup = "9B2KKVM937.me.saffer.sill.viewer"' in s
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
