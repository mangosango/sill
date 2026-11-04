#!/usr/bin/env python3
"""Private profile fixtures; no credentials or app execution."""
import copy
import datetime
import importlib.util
from pathlib import Path
import plistlib
import os
import subprocess

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('viewer_profile', root / 'Scripts/viewer-profile.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
entitlements = module.configuration(module.TEAM, module.BUNDLE)
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
for team, bundle in [(module.TEAM, module.BUNDLE), ('RPKWZLZ8NN', 'com.sangjinlee.sill.viewer')]:
    wanted = module.configuration(team, bundle)
    template = (root / 'Packaging/SillViewer.entitlements').read_text()
    resolved = plistlib.loads(template.replace('$(SILL_VIEWER_TEAM)', team).replace('$(SILL_VIEWER_BUNDLE_ID)', bundle).encode())
    assert resolved == wanted
    custom = dict(profile, TeamIdentifier=[team], Entitlements=wanted)
    module.validate(custom, wanted, b'private fake certificate', now, team, bundle)
    wildcard = copy.deepcopy(custom)
    wildcard['Entitlements']['keychain-access-groups'] = [team + '.*']
    wildcard['Entitlements']['com.apple.application-identifier'] = team + '.*'
    module.validate(wildcard, wanted, b'private fake certificate', now, team, bundle)
    for key, value in [('com.apple.application-identifier', team + '.me.saffer.sill.mac'),
                       ('keychain-access-groups', [team + '.me.saffer.sill.mac']),
                       ('com.apple.developer.team-identifier', 'OTHER')]:
        bad = copy.deepcopy(custom)
        bad['Entitlements'][key] = value
        try:
            module.validate(bad, wanted, b'private fake certificate', now, team, bundle)
        except ValueError:
            pass
        else:
            raise AssertionError(key)
for team, bundle in [('bad', module.BUNDLE), (module.TEAM, ''), (module.TEAM, 'a..b'),
                     (module.TEAM, 'me.saffer.sill.mac'), (module.TEAM, 'me.saffer.sill'),
                     (module.TEAM, 'ME.SAFFER.SILL.MAC'), (module.TEAM, 'com.example.*'), (module.TEAM, '$(BAD)')]:
    try:
        module.configuration(team, bundle)
    except ValueError:
        pass
    else:
        raise AssertionError((team, bundle))
subprocess.run(['/bin/bash', '-n' , str(root / 'Scripts/make-viewer.sh')], check=True)
for args in [ ['--install'], ['--developer-id', '-', 'missing'], ['--adhoc', 'extra'] ]:
    result = subprocess.run(['/bin/bash', str(root / 'Scripts/make-viewer.sh'), *args], capture_output=True)
    assert result.returncode == 2, args
for key, value in [('SILL_VIEWER_TEAM', 'bad'), ('SILL_VIEWER_BUNDLE_ID', 'me.saffer.sill.mac')]:
    result = subprocess.run(['/bin/bash', str(root / 'Scripts/make-viewer.sh')],
                            env=dict(os.environ, **{key: value}), capture_output=True)
    assert result.returncode == 1 and b'error: viewer profile:' in result.stderr
    assert b'xcodebuild' not in result.stdout
script = (root / 'Scripts/make-viewer.sh').read_text()
assert "ARCHS='arm64 x86_64'" in script and '-jobs 4' in script
assert 'CODE_SIGNING_ALLOWED=NO' in script
assert 'Sill-Viewer.zip' in script and 'Sill.dmg' not in script
assert 'SILL_PROVISION_PROFILE' not in script
print('Viewer package: default/custom profile, configuration, argument and static checks passed; bash -n passed.')
assert 'REGISTER_APP_WITH_LAUNCH_SERVICES=NO' in script
developer, adhoc = script.split('if [ "$mode" = developer ]; then', 1)[1].split('elif [ "$mode" = adhoc ]; then', 1)
assert '--entitlements "$work/entitlements.plist"' in developer
assert '--entitlements' not in adhoc and 'embedded.provisionprofile' not in adhoc
assert 'SILL_VIEWER_TEAM="$team" SILL_VIEWER_BUNDLE_ID="$bundle"' in script
assert 'Print :SillViewerKeychainGroup' in script
subprocess.run(['python3', str(root / 'Tests/viewer-package/artifacts.py')], check=True)
