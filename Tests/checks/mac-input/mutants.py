"""Sequential behavioral mutations of native input code, always in scratch copies.
Compile failures and unapplied edits fail the run; neither counts as a kill.
The routing harness compiles the real input view with a recording client and hidden windows.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / '.build/checks/mac-input/mutants'
OUT.mkdir(parents=True, exist_ok=True)
KEY = 'MacClient/MacKeyboard.swift'
VIEW = 'MacClient/StreamInputView.swift'
STATE = 'MacClient/ViewerInputState.swift'
CAPTURE = 'MacClient/MacKeyboardCapture.swift'
# name, harness, source, unique old text, replacement
MUTANTS = [
    ('K1 Command-Q wrongly local', 'input', KEY, 'releasesKeyboard(keyCode: keyCode, modifiers: modifiers)', 'keyCode == 12 || releasesKeyboard(keyCode: keyCode, modifiers: modifiers)'),
    ('K2 accessibility chord', 'input', KEY, 'modifiers.isSuperset(of: [.control, .option])', 'false'),
    ('V1 VoiceOver Caps Lock press captured', 'input', KEY, 'keyCode == UInt16(kVK_CapsLock) || ', ''),
    ('V2 VoiceOver Caps Lock navigation captured', 'input', KEY, '|| modifiers.contains(.capsLock)', ''),
    ('K3 release chord', 'input', KEY, 'keyCode == UInt16(kVK_ANSI_K)', 'keyCode == UInt16(kVK_ANSI_J)'),
    ('K4 release held keys', 'input', KEY, 'while let usage = down.last, let up = ended(usage) { ups.append(up) }', 'down.removeAll()'),
    ('K5 repeated down dedup', 'input', KEY, 'if !down.contains(usage) { down.append(usage) }', 'down.append(usage)'),
    ('K6 host repeat capability', 'input', KEY, 'if event.isARepeat, (hostKeyRepeat ?? 0) >= 1 { return [] }', 'if event.isARepeat { return [] }'),
    ('K7 native repeat suppressed', 'input', KEY, 'if event.isARepeat, (hostKeyRepeat ?? 0) >= 1 { return [] }', 'if false { return [] }'),
    ('K8 composing shortcut stays text', 'input', KEY, 'guard !composing, let usage', 'guard let usage'),
    ('K9 raw command falls through', 'input', KEY, 'if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return true }', 'if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return false }'),
    ('I1 UTF-16 selection offset', 'input', VIEW, 'NSRange(location: start, length:', 'NSRange(location: 0, length:'),
    ('I2 selection highlight absent', 'input', VIEW, 'if selection.length > 0 {', 'if false {'),
    ('I3 cleared label retains text', 'input', VIEW, 'attributedStringValue = NSAttributedString(string: "")', '// retain stale text'),
    ('I4 preedit takes focus', 'input', VIEW, 'override var acceptsFirstResponder: Bool { false }', 'override var acceptsFirstResponder: Bool { true }'),
    ('L1 released local keys swallowed', 'routing', VIEW, 'guard enabled else { super.keyDown(with: event); return }', 'guard enabled else { return }'),
    ('L2 native menu tracking ignored', 'routing', VIEW, 'forName: NSMenu.didBeginTrackingNotification', 'forName: NSMenu.didEndTrackingNotification'),
    ('L3 menu other-window isolation lost', 'routing', VIEW, 'window?.isKeyWindow == true, window?.firstResponder === self', 'window?.firstResponder === self'),
    ('O1 ownership gate missing', 'routing', VIEW, 'inputState?.controlling == true && MacPointerGeometry', 'MacPointerGeometry'),
    ('O2 click fails to acquire', 'routing', VIEW, 'inputState?.takeControl()', '// do not acquire'),
    ('C1 activation clicks through', 'routing', VIEW, 'return // The activation click must not also act on the remote Mac.', '// allow click through'),
    ('C2 activation click discarded', 'routing', VIEW, 'override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }', 'override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }'),
    ('C3 outside picture acquires', 'routing', VIEW, 'guard let point = location(event) else { return }', 'guard let point = location(event, clamp: true) else { return }'),
    ('O3 release leaves ownership', 'routing', STATE, 'if controlling { controlling = false }', 'if controlling { controlling = true }'),
    ('O7 redundant release publication', 'routing', STATE, 'if controlling { controlling = false }', 'controlling = false'),
    ('O8 redundant control publication', 'routing', STATE, 'guard !controlling else { return }', 'if controlling { controlling = true; return }'),
    ('O4 settings shortcut wrongly local', 'routing', KEY, 'releasesKeyboard(keyCode: keyCode, modifiers: modifiers)', 'keyCode == 43 || releasesKeyboard(keyCode: keyCode, modifiers: modifiers)'),
    ('O5 fullscreen shortcut wrongly local', 'routing', KEY, 'releasesKeyboard(keyCode: keyCode, modifiers: modifiers)', 'keyCode == 3 || releasesKeyboard(keyCode: keyCode, modifiers: modifiers)'),
    ('O6 disconnect shortcut wrongly local', 'routing', KEY, 'releasesKeyboard(keyCode: keyCode, modifiers: modifiers)', 'keyCode == 2 || releasesKeyboard(keyCode: keyCode, modifiers: modifiers)'),
    ('T1 permission bypass', 'input', CAPTURE, 'if !trusted { return .permission }', 'if false { return .permission }'),
    ('T2 secure-input bypass', 'input', CAPTURE, 'if secureInput { return .secureInput }', 'if false { return .secureInput }'),
    ('T3 disabled tap ignored', 'input', CAPTURE, 'if !tapEnabled { return .interrupted }', 'if false { return .interrupted }'),
    ('T4 ownership ignored', 'input', CAPTURE, 'guard owning,', 'guard true,'),
    ('T5 escape captured remotely', 'input', CAPTURE, '{ return .release }', '{ return .deliver }'),
    ('T6 VoiceOver captured remotely', 'input', CAPTURE, 'if MacKeyForwarder.voiceOverOwns(keyCode: keyCode, modifiers: modifiers, enabled: voiceOver)', 'if false'),
    ('T7 text bypasses ordered capture', 'input', CAPTURE, 'return .deliver\n', 'return .releaseToLocal\n'),
    ('T8 no capture stop on release', 'routing', STATE, '        capture.stop()', '        // leave capture running'),
    ('T9 failure retains ownership', 'routing', STATE, '            self?.release()', '            // retain ownership'),
    ('T10 capture bridge loses window', 'routing', CAPTURE, 'windowNumber: window.windowNumber', 'windowNumber: 0'),
    ('T11 captured event also delivered locally', 'routing', CAPTURE, 'view.handleCapturedKeyboard(rebound)\n            return nil', 'view.handleCapturedKeyboard(rebound)\n            return Unmanaged.passUnretained(event)'),
    ('T12 watchdog fails to release ownership', 'routing', CAPTURE, 'owner?.release()\n            return\n', '// retain ownership\n            return\n'),
    ('T13 lost capture not reported', 'routing', CAPTURE, 'notify?(failure)', '// swallow failure'),
    ('R1 swallowed Command keyUp', 'routing', VIEW, 'let ups = self.keys.keyUp(event)', 'let ups: [InputEvent] = []'),
    ('R2 other window keyUp', 'routing', VIEW, 'event.window === window else { return event }', 'true else { return event }'),
    ('E1 pointer exit keeps control', 'routing', VIEW, 'override func mouseExited(with event: NSEvent) { releaseInput() }', 'override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }'),
    ('E2 drag exit keeps control', 'routing', VIEW, 'guard bounds.contains(convert(event.locationInWindow, from: nil)) else { releaseInput(); return }', 'guard true else { releaseInput(); return }'),
    ('E3 drag tracking disabled', 'routing', VIEW, '.mouseEnteredAndExited, .enabledDuringMouseDrag,', '.mouseEnteredAndExited,'),
    ('S1 scroll reversal ignored', 'routing', VIEW, 'reverseScrolling ? -1 : 1', '1'),
    ('S2 scroll always reversed', 'routing', VIEW, 'reverseScrolling ? -1 : 1', '-1'),
    ('S3 horizontal scroll not reversed', 'routing', VIEW, 'dx: event.scrollingDeltaX * unit', 'dx: event.scrollingDeltaX * abs(unit)'),
    ('S4 vertical scroll not reversed', 'routing', VIEW, 'dy: event.scrollingDeltaY * unit', 'dy: event.scrollingDeltaY * abs(unit)'),
    ('S5 scroll reversal on by default', 'routing', VIEW, 'var reverseScrolling = false', 'var reverseScrolling = true'),
    ('P1 letterbox accepts pointer', 'pointer', VIEW, 'clamp || rect.contains(point)', 'true'),
    ('P2 horizontal origin ignored', 'pointer', VIEW, '(point.x - rect.minX) / rect.width', 'point.x / rect.width'),
    ('P3 vertical fraction inverted', 'pointer', VIEW, '(point.y - rect.minY) / rect.height', '1 - (point.y - rect.minY) / rect.height'),
    ('P4 focus gate missing', 'pointer', VIEW, 'keyWindow && firstResponder && connected && !paused', 'keyWindow && connected && !paused'),
    ('P5 cancelled scroll left open', 'pointer', VIEW, 'phase.contains(.ended) || phase.contains(.cancelled)', 'phase.contains(.ended)'),
]


def run(command, log):
    with log.open('w') as stream:
        return subprocess.run([str(x) for x in command], cwd=ROOT, stdout=stream,
                              stderr=subprocess.STDOUT, timeout=600).returncode


module = OUT / 'libStreamProtocol.dylib'
if run(['swiftc', '-swift-version', '5', '-emit-library', '-emit-module', '-module-name',
        'StreamProtocol', *sorted((ROOT / 'Sources/StreamProtocol').glob('*.swift')),
        '-o', module, '-emit-module-path', OUT / 'StreamProtocol.swiftmodule'], OUT / 'module.log'):
    sys.exit('module compilation failed (module.log)')


def check(name, harness, source=None, old=None, new=None):
    folder = OUT / name
    folder.mkdir(exist_ok=True)
    paths = {}
    for relative in (KEY, VIEW, STATE, CAPTURE):
        text = (ROOT / relative).read_text()
        if relative == source:
            if text.count(old) != 1:
                return 'not-applied'
            text = text.replace(old, new, 1)
        paths[relative] = folder / Path(relative).name
        paths[relative].write_text(text)
    args = ['swiftc', '-swift-version', '5', '-Onone',
            '-I', OUT, '-L', OUT, '-lStreamProtocol', '-Xlinker', '-rpath', '-Xlinker', OUT]
    if harness != 'routing':
        args += ['-D', 'POINTER_POLICY_TEST']
    if harness == 'routing':
        args += [paths[KEY], paths[STATE], paths[CAPTURE], ROOT / 'MacClient/MacClipboard.swift',
                 ROOT / 'iOSClient/KeyChords.swift', ROOT / 'iOSClient/TextComposition.swift',
                 ROOT / 'Tests/checks/mac-input/routing/Fixture.swift',
                 ROOT / 'Tests/checks/mac-input/routing/main.swift']
    elif harness == 'input':
        args += ['-D', 'MAC_CAPTURE_POLICY_TEST', '-D', 'MAC_INPUT_TEST', '-D', 'DEBUG', paths[KEY], paths[CAPTURE],
                 ROOT / 'iOSClient/KeyChords.swift', ROOT / 'iOSClient/TextComposition.swift',
                 ROOT / 'Tests/checks/mac-input/main.swift']
    else:
        args += [ROOT / 'Tests/mac-pointer/main.swift']
    args += [paths[VIEW], '-o', folder / 'check']
    if run(args, folder / 'compile.log'):
        return 'compile-error'
    code = run([folder / 'check'], folder / 'run.log')
    # Swift assertion/precondition failures trap. Other failures are not behavioral kills.
    return 'killed' if code in (-4, -5, -6) else ('survived' if code == 0 else 'runtime-error')


for harness in ('input', 'pointer', 'routing'):
    if check('baseline-' + harness, harness) != 'survived':
        sys.exit('baseline failed: ' + harness)
counts = dict.fromkeys(['attempted', 'killed', 'survived', 'not-applied', 'compile-error', 'runtime-error'], 0)
for name, harness, source, old, new in MUTANTS:
    counts['attempted'] += 1
    result = check(name.split()[0], harness, source, old, new)
    counts[result] += 1
    print(f'{name}: {result}', flush=True)
print(counts)
print(f'Logs and scratch sources: {OUT}')
sys.exit(0 if counts['killed'] == counts['attempted'] else 1)
