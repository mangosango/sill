#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
work=$(mktemp -d "${TMPDIR:-/tmp}/sill-viewer-window.XXXXXX")
trap 'rm -rf "$work"' EXIT
python3 Tests/checks/mac-viewer-window/structural.py
swiftc -swift-version 5 -j 4 MacClient/ViewerWindow.swift Tests/checks/mac-viewer-window/main.swift -o "$work/check"
"$work/check"
if [[ "${1:-}" == "--mutants" ]]; then
    python3 Tests/checks/mac-viewer-window/mutants.py
fi
