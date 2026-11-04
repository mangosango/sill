#!/bin/bash
# Native helpers are compiled and exercised; shared client files are syntax-checked on both platforms.
# Full shared-client typechecking requires assembly with the identity and media lanes.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
out="$root/.build/mac-client-platform-check"
mkdir -p "$out"
swiftc -swift-version 5 -module-name StreamProtocol -emit-module Sources/StreamProtocol/*.swift \
    -emit-module-path "$out/StreamProtocol.swiftmodule"
shared=(iOSClient/StreamClient.swift iOSClient/StreamClient+Home.swift iOSClient/StreamClient+Remote.swift
        iOSClient/StreamClient+Viewport.swift iOSClient/DiagnosticsHUD.swift)
for mode in debug release; do
    flags=(-Onone -D DEBUG)
    if [ "$mode" = release ]; then flags=(-O); fi
    swiftc -swift-version 5 "${flags[@]}" MacClient/ClientPlatform.swift MacClient/ClientLifecycle.swift \
        Scripts/mac-client-platform-check/main.swift -o "$out/$mode"
    "$out/$mode"
    swiftc -swift-version 5 -typecheck "${flags[@]}" -I "$out" \
        Scripts/mac-client-platform-check/StatsCompileFixture.swift iOSClient/DiagnosticsHUD.swift
    swiftc -frontend -parse "${flags[@]}" "${shared[@]}"
    # Parsing only: no iOS SDK or simulator runtime is needed for this guard/syntax check.
    swiftc -frontend -parse -target arm64-apple-ios17.0-simulator "${flags[@]}" "${shared[@]}"
done
