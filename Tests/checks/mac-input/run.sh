#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
out=.build/checks/mac-input
mkdir -p "$out"
swiftc -swift-version 5 -emit-library -emit-module -module-name StreamProtocol Sources/StreamProtocol/*.swift -o "$out/libStreamProtocol.dylib" -emit-module-path "$out/StreamProtocol.swiftmodule"
for mode in debug release; do
  flags=(-Onone -D DEBUG)
  if [ "$mode" = release ]; then flags=(-O); fi
  swiftc -swift-version 5 "${flags[@]}" -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$(pwd)/$out" MacClient/MacKeyboard.swift iOSClient/KeyChords.swift iOSClient/TextComposition.swift Tests/checks/mac-input/main.swift -o "$out/$mode"
  "$out/$mode"
done
