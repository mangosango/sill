"""Sequential behavioral mutations of native input code, always in scratch copies.
Compile failures and unapplied edits fail the run; neither counts as a kill.
The policy harness does not compile StreamInputView's client/responder callbacks.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / '.build/checks/mac-input/mutants'
OUT.mkdir(parents=True, exist_ok=True)
KEY = 'MacClient/MacKeyboard.swift'
VIEW = 'MacClient/StreamInputView.swift'
# name, harness, source, unique old text, replacement
MUTANTS = [
    ('K1 local Command-Q', 'input', KEY, 'UInt16(kVK_ANSI_Q), ', ''),
    ('K2 accessibility chord', 'input', KEY, 'flags.isSuperset(of: [.control, .option])', 'false'),
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
    for relative in (KEY, VIEW):
        text = (ROOT / relative).read_text()
        if relative == source:
            if text.count(old) != 1:
                return 'not-applied'
            text = text.replace(old, new, 1)
        paths[relative] = folder / Path(relative).name
        paths[relative].write_text(text)
    args = ['swiftc', '-swift-version', '5', '-Onone', '-D', 'POINTER_POLICY_TEST',
            '-I', OUT, '-L', OUT, '-lStreamProtocol', '-Xlinker', '-rpath', '-Xlinker', OUT]
    if harness == 'input':
        args += ['-D', 'MAC_INPUT_TEST', '-D', 'DEBUG', paths[KEY],
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


for harness in ('input', 'pointer'):
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
