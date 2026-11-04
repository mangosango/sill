#!/bin/bash
# Structural integration checks only: never launches the app or touches a Keychain.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import plistlib, subprocess
from pathlib import Path
p = plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', 'iOSClient/Sill.xcodeproj/project.pbxproj']))
o = p['objects']
t = next(v for v in o.values() if v.get('isa') == 'PBXNativeTarget' and v['name'] == 'Sill Viewer')
source_phase = next(o[k] for k in t['buildPhases'] if o[k]['isa'] == 'PBXSourcesBuildPhase')
paths = [o[o[k]['fileRef']]['path'] for k in source_phase['files']]
assert len(paths) == len(set(paths))
for name in ['StreamClient.swift', 'DeviceIdentity.swift', 'StreamClient+Audio.swift', 'StreamClient+Clipboard.swift', '../MacClient/HEVCDisplayView.swift', '../MacClient/SillViewerApp.swift']:
    assert name in paths, name
for source in Path('MacClient').glob('*.swift'):
    assert '../' + str(source) in paths, f'Unregistered viewer source: {source}'
assert 'HEVCDisplayView.swift' not in paths
assert not any('Stub' in x or 'Fixture' in x or x in ['InputOverlay.swift', 'ContentView.swift', 'SillApp.swift'] for x in paths)
for v in o.values():
    if v.get('isa') == 'PBXNativeTarget' and v['name'] == 'Sill':
        for phase in v['buildPhases']:
            if o[phase]['isa'] == 'PBXSourcesBuildPhase':
                assert not any('MacClient/' in o[o[k]['fileRef']]['path'] for k in o[phase]['files'])
info = plistlib.loads(Path('MacClient/Info.plist').read_bytes())
assert 'CFBundleURLTypes' not in info
assert 'NSCameraUsageDescription' not in info
identity = Path('iOSClient/DeviceIdentity.swift').read_text()
assert 'me.saffer.sill.viewer.device-key' in identity
assert identity.count('kSecUseDataProtectionKeychain as String] = true') == 3
assert 'var deletion = keyQuery(currentTag)' in identity
assert 'var query = keyQuery(currentTag)' in identity
assert identity.count('removeValue(forKey: kSecMatchLimit as String)') == 2
assert 'case .fail(let status)' in identity and 'DeviceKeyPolicy.made(readBack: readBack(key)' in identity
assert subprocess.check_output(['git', 'show', '65f16bc:MacClient/HEVCDisplayView.swift']) == Path('MacClient/HEVCDisplayView.swift').read_bytes()
print('Native assembly: source membership, isolation, identity boundaries and renderer preservation passed')
PY
