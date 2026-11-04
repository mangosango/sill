#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p .build/checks/mac-clipboard-adapter
swiftc MacClient/MacClipboard.swift Tests/checks/mac-clipboard-adapter/main.swift -o .build/checks/mac-clipboard-adapter/check
.build/checks/mac-clipboard-adapter/check
