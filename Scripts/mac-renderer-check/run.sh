#!/bin/bash
# Compiles the native renderer in isolation; no app launch, network, screen capture or decoder.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/.build/mac-renderer-check"
mkdir -p "$out"
cd "$root"
target="$(uname -m)-apple-macosx14.0"
swiftc -target "$target" -swift-version 5 -module-name StreamProtocol -emit-module -emit-library \
    Sources/StreamProtocol/*.swift -o "$out/libStreamProtocol.dylib" \
    -emit-module-path "$out/StreamProtocol.swiftmodule"
for mode in debug release; do
    flags=(-Onone -D DEBUG)
    if [ "$mode" = release ]; then flags=(-O); fi
    swiftc -target "$target" -swift-version 5 "${flags[@]}" -I "$out" -L "$out" -lStreamProtocol \
        -Xlinker -rpath -Xlinker "$out" MacClient/HEVCDisplayView.swift \
        Scripts/mac-renderer-check/main.swift -o "$out/$mode"
    "$out/$mode"
done
