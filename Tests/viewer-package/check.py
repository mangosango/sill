#!/usr/bin/env python3
"""Private profile fixtures; no credentials or app execution."""
import copy
import datetime
import importlib.util
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('viewer_profile', root / 'Scripts/viewer-profile.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with (root / 'Packaging/SillViewer.entitlements').open('rb') as file:
    entitlements = plistlib.load(file)
now = datetime.datetime(2026, 1, 1)
profile = dict(Platform=['OSX'], TeamIdentifier=[module.TEAM],
               ExpirationDate=now + datetime.timedelta(days=1),
               DeveloperCertificates=[b'private fake certificate'], Entitlements=entitlements.copy())
module.validate(profile, entitlements, b'private fake certificate', now)
for key, value in [('Platform', ['iOS']), ('TeamIdentifier', ['OTHER']),
                   ('ExpirationDate', now), ('DeveloperCertificates', [b'other'])]:
    bad = copy.deepcopy(profile)
    bad[key] = value
    try:
        module.validate(bad, entitlements, b'private fake certificate', now)
    except ValueError:
        pass
    else:
        raise AssertionError(key)
for key in entitlements:
    bad = copy.deepcopy(profile)
    del bad['Entitlements'][key]
    try:
        module.validate(bad, entitlements, b'private fake certificate', now)
    except ValueError:
        pass
    else:
        raise AssertionError(key)
extra = dict(entitlements, unexpected=True)
try:
    module.validate(profile, extra, b'private fake certificate', now)
except ValueError:
    pass
else:
    raise AssertionError('every entitlement must be granted')
bad = dict(entitlements, **{'keychain-access-groups': ['9B2KKVM937.me.saffer.sill.mac']})
try:
    module.validate(profile, bad, b'private fake certificate', now)
except ValueError:
    pass
else:
    raise AssertionError('host group')
subprocess.run(['/bin/bash', '-n', str(root / 'Scripts/make-viewer.sh')], check=True)
for args in [ ['--install'], ['--developer-id', '-', 'missing'], ['--adhoc', 'extra'] ]:
    result = subprocess.run(['/bin/bash', str(root / 'Scripts/make-viewer.sh'), *args], capture_output=True)
    assert result.returncode == 2, args
script = (root / 'Scripts/make-viewer.sh').read_text()
assert "ARCHS='arm64 x86_64'" in script and '-jobs 4' in script
assert 'CODE_SIGNING_ALLOWED=NO' in script
assert 'Sill-Viewer.zip' in script and 'Sill.dmg' not in script
assert 'SILL_PROVISION_PROFILE' not in script
print('Viewer package: 16 profile, argument and static checks passed; bash -n passed.')
