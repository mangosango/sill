#!/usr/bin/env python3
"""Check an unsigned built viewer's resolved configuration without launching it."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('viewer_profile', root / 'Scripts/viewer-profile.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
app, team, bundle = sys.argv[1:]
required = module.configuration(team, bundle)
with (Path(app) / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info['CFBundleIdentifier'] == bundle
assert info['SillViewerKeychainGroup'] == required['keychain-access-groups'][0]
assert not (Path(app) / 'Contents/embedded.provisionprofile').exists()
result = subprocess.run(['codesign', '-d', '--entitlements', ':-', app], capture_output=True)
# Xcode may leave a linker ad-hoc signature; neither it nor unsigned code gets grants.
assert b'keychain-access-groups' not in result.stdout + result.stderr
assert b'com.apple.application-identifier' not in result.stdout + result.stderr
print('Unsigned viewer resolved bundle/group agree:', bundle, info['SillViewerKeychainGroup'])
