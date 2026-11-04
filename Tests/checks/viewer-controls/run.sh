#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 Tests/checks/viewer-controls/structural.py
python3 Scripts/mac-connect-ui-check.py
