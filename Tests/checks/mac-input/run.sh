#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
if [ "${1:-}" = --mutants ]; then
  exec python3 Tests/checks/mac-input/mutants.py
fi
out=.build/checks/mac-input
mkdir -p "$out"
swiftc -swift-version 5 -emit-library -emit-module -module-name StreamProtocol Sources/StreamProtocol/*.swift -o "$out/libStreamProtocol.dylib" -emit-module-path "$out/StreamProtocol.swiftmodule"
for mode in debug release; do
  flags=(-Onone -D DEBUG)
  if [ "$mode" = release ]; then flags=(-O); fi
  swiftc -swift-version 5 "${flags[@]}" -D POINTER_POLICY_TEST -D MAC_INPUT_TEST -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$(pwd)/$out" MacClient/StreamInputView.swift MacClient/MacKeyboard.swift iOSClient/KeyChords.swift iOSClient/TextComposition.swift Tests/checks/mac-input/main.swift -o "$out/$mode"
  "$out/$mode"
  swiftc -swift-version 5 "${flags[@]}" -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$(pwd)/$out" MacClient/StreamInputView.swift MacClient/MacKeyboard.swift MacClient/MacClipboard.swift iOSClient/KeyChords.swift iOSClient/TextComposition.swift Tests/checks/mac-input/routing/{Fixture,main}.swift -o "$out/routing-$mode"
  "$out/routing-$mode"
done
# The detached label test above exercises rendering; retain the native callback wiring too.
python3 - <<'PY'
from pathlib import Path
source = Path('MacClient/StreamInputView.swift').read_text()
assert 'addSubview(preedit)' in source
assert 'preedit.update(composition, in: bounds)' in source
assert 'let anchor = preedit.isHidden ?' in source and ': preedit.frame' in source
assert 'composition = TextComposition()\n        updatePreedit()' in source
assert 'override func layout() {\n        super.layout()\n        updatePreedit()' in source
assert '        updatePreedit()\n    }\n    private func updatePreedit()' in source
print('mac-input: preedit callback, reset, layout and candidate-anchor wiring passed')
PY
