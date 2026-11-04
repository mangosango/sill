#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/mac-pointer
# Wire types only: no client runtime, UI launch or machine data.
swiftc -emit-module -module-name StreamProtocol Sources/StreamProtocol/Input.swift -emit-module-path .build/mac-pointer/StreamProtocol.swiftmodule
swiftc -D POINTER_POLICY_TEST -I .build/mac-pointer Sources/StreamProtocol/Input.swift MacClient/StreamInputView.swift Tests/mac-pointer/main.swift -o .build/mac-pointer/check
.build/mac-pointer/check
