#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
work=$(mktemp -d /tmp/sill-viewer-settings.XXXXXX)
trap 'rm -rf "$work"' EXIT
swiftc -swift-version 5 -emit-module -module-name StreamProtocol Sources/StreamProtocol/HostSettings.swift -emit-module-path "$work/StreamProtocol.swiftmodule"
swiftc -swift-version 5 -typecheck -I "$work" iOSClient/HostSettingsLedger.swift Tests/checks/mac-viewer-settings/ClientFixture.swift MacClient/ViewerSettings.swift
python3 Tests/checks/mac-viewer-settings/structure.py
printf '%s\n' 'mac-viewer-settings: Swift 5 typecheck passed (real HostSettings + ledger, compile-only client fixture)'
