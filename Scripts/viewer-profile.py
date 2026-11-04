#!/usr/bin/env python3
"""Validate a decoded macOS viewer profile and the actual signing certificate (DER)."""
import datetime
import plistlib
import re
import sys

TEAM = '9B2KKVM937'
BUNDLE = 'me.saffer.sill.viewer'


def configuration(team, bundle):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('team must be ten uppercase letters or digits')
    if (not re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+', bundle)
            or bundle.lower() in ('me.saffer.sill.mac', 'me.saffer.sill')):
        raise ValueError('use a distinct viewer bundle identifier, not the host or iOS ID')
    group = team + '.' + bundle
    return {
        'com.apple.application-identifier': group,
        'com.apple.developer.team-identifier': team,
        'keychain-access-groups': [group],
    }


def validate(profile, entitlements, certificate, now, team=TEAM, bundle=BUNDLE):
    required = configuration(team, bundle)
    if entitlements != required:
        raise ValueError('viewer identity entitlements do not match')
    if profile.get('Platform') != ['OSX']:
        raise ValueError('a macOS profile is required')
    if profile.get('TeamIdentifier') != [team]:
        raise ValueError('profile team does not match')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime.datetime) or expiry <= now:
        raise ValueError('profile has expired or has no expiry')
    if certificate not in profile.get('DeveloperCertificates', []):
        raise ValueError('signing certificate is not in the profile')
    granted = profile.get('Entitlements', {})
    for key, wanted in entitlements.items():
        allowed = granted.get(key)
        if isinstance(wanted, list) and wanted and isinstance(allowed, list):
            # As in make-app.sh: profile list grants may end in a wildcard.
            if all(isinstance(item, str) and any(
                    isinstance(pattern, str) and (item == pattern or
                    (pattern.endswith('*') and item.startswith(pattern[:-1])))
                    for pattern in allowed) for item in wanted):
                continue
        elif key == 'com.apple.application-identifier' and isinstance(allowed, str) and (wanted == allowed or (allowed.endswith('*') and wanted.startswith(allowed[:-1]))):
            continue
        elif isinstance(wanted, (str, bool, int)) and type(wanted) is type(allowed) and wanted == allowed:
            continue
        raise ValueError('profile does not grant entitlement: ' + key)


if __name__ == '__main__':
    try:
        if sys.argv[1] == '--resolve':
            with open(sys.argv[4], 'wb') as file:
                plistlib.dump(configuration(sys.argv[2], sys.argv[3]), file)
            sys.exit(0)
        team, bundle = sys.argv[1:3]
        with open(sys.argv[3], 'rb') as file:
            profile = plistlib.load(file)
        with open(sys.argv[4], 'rb') as file:
            entitlements = plistlib.load(file)
        if len(sys.argv) == 6:
            with open(sys.argv[5], 'rb') as file:
                certificate = file.read()
        else:
            certificate = profile.get('DeveloperCertificates', [b''])[0]
        validate(profile, entitlements, certificate, datetime.datetime.utcnow(), team, bundle)
    except (ValueError, OSError, IndexError, plistlib.InvalidFileException) as error:
        sys.exit('error: viewer profile: ' + str(error))
