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
  swiftc -swift-version 5 "${flags[@]}" -D MAC_CAPTURE_POLICY_TEST -D POINTER_POLICY_TEST -D MAC_INPUT_TEST -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$(pwd)/$out" MacClient/StreamInputView.swift MacClient/MacKeyboard.swift MacClient/MacKeyboardCapture.swift iOSClient/KeyChords.swift iOSClient/TextComposition.swift Tests/checks/mac-input/main.swift -o "$out/$mode"
  "$out/$mode"
  swiftc -swift-version 5 "${flags[@]}" -I "$out" -L "$out" -lStreamProtocol -Xlinker -rpath -Xlinker "$(pwd)/$out" MacClient/StreamInputView.swift MacClient/MacKeyboard.swift MacClient/MacKeyboardCapture.swift MacClient/ViewerInputState.swift MacClient/MacClipboard.swift iOSClient/KeyChords.swift iOSClient/TextComposition.swift Tests/checks/mac-input/routing/{Fixture,main}.swift -o "$out/routing-$mode"
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
assert 'window?.frame.contains(NSEvent.mouseLocation) == true' in source
capture = Path('MacClient/MacKeyboardCapture.swift').read_text()
assert 'tap: .cgSessionEventTap, place: .headInsertEventTap' in capture
assert 'CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)' in capture
assert 'CFMachPortInvalidate(tap)' in capture and 'CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)' in capture
assert 'Timer(timeInterval: 0.5, repeats: true)' in capture and 'RunLoop.main.add(timer, forMode: .common)' in capture
assert '.post(' not in capture and 'CGSSet' not in capture
print('mac-input: preedit and main-run-loop tap/watchdog/teardown wiring passed; no real tap installed')
PY
