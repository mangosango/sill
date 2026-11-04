#!/bin/bash
# Isolated NSMenu objects only: no app, windows, transport or user data.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
cp "$root"/Sources/StreamProtocol/*.swift "$t/"
sed '/^import StreamProtocol$/d' "$root/iOSClient/MacMenuState.swift" > "$t/MacMenuState.swift"
cp "$root/MacClient/RemoteMenus.swift" "$t/"
cp "$root/Tests/remote-menus/main.swift" "$t/main.swift"
swiftc "$t/"*.swift -o "$t/check"
"$t/check"
