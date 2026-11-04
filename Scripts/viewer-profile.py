#!/usr/bin/env python3
"""Validate a decoded macOS viewer profile and the actual signing certificate (DER)."""
import datetime
import plistlib
import sys

IDENTIFIER = '9B2KKVM937.me.saffer.sill.viewer'
TEAM = '9B2KKVM937'


def validate(profile, entitlements, certificate, now):
    required = {
        'com.apple.application-identifier': IDENTIFIER,
        'com.apple.developer.team-identifier': TEAM,
        'keychain-access-groups': [IDENTIFIER],
    }
    if any(entitlements.get(key) != value for key, value in required.items()):
        raise ValueError('viewer identity entitlements do not match')
    if profile.get('Platform') != ['OSX']:
        raise ValueError('a macOS profile is required')
    if profile.get('TeamIdentifier') != [TEAM]:
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
        elif isinstance(wanted, (str, bool, int)) and type(wanted) is type(allowed) and wanted == allowed:
            continue
        raise ValueError('profile does not grant entitlement: ' + key)


if __name__ == '__main__':
    try:
        with open(sys.argv[1], 'rb') as file:
            profile = plistlib.load(file)
        with open(sys.argv[2], 'rb') as file:
            entitlements = plistlib.load(file)
        if len(sys.argv) == 4:
            with open(sys.argv[3], 'rb') as file:
                certificate = file.read()
        else:
            certificate = profile.get('DeveloperCertificates', [b''])[0]
        validate(profile, entitlements, certificate, datetime.datetime.utcnow())
    except (ValueError, OSError, IndexError, plistlib.InvalidFileException) as error:
        sys.exit('error: viewer profile: ' + str(error))
