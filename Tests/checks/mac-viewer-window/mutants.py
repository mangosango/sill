#!/usr/bin/env python3
"""Scratch-only behavioral mutations; compile failures are failures, not kills."""
from pathlib import Path
import resource
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'MacClient/ViewerWindow.swift').read_text()
fixture = root / 'Tests/checks/mac-viewer-window/main.swift'
mutations = [
    ('healthy-status-band', '        return nil\n', '        return "Streaming"\n'),
    ('discard-notice', 'if let notice { return notice }', 'if let notice { return "Ignored: " + notice }'),
    ('ignore-missing-source', 'if noSource {', 'if false {'),
    ('ignore-video-wait', 'if !hasVideo {', 'if false {'),
    ('ignore-slow-link', 'if slowLink {', 'if false {'),
    ('visible-fullscreen-toolbar', '.autoHideMenuBar, .autoHideToolbar', '.autoHideMenuBar'),
    ('discard-original-options', 'let options = original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions', 'let options = proposedOptions'),
    ('block-delegate-forwarding', 'if original?.responds(to: selector) == true { return original }', 'if false { return original }'),
    ('resize-during-transition', '!transitioning, !window.styleMask.contains(.fullScreen)', '!window.styleMask.contains(.fullScreen)'),
    ('entry-does-not-release', '            observe(NSWindow.willEnterFullScreenNotification, window: window) { [weak self] in\n                self?.release?()', '            observe(NSWindow.willEnterFullScreenNotification, window: window) { [weak self] in\n                _ = self'),
    ('stale-fullscreen-state', 'self?.state?.fullScreen = false', 'self?.state?.fullScreen = true'),
    ('close-does-not-disconnect', 'self?.close?()', '_ = self'),
]

def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

with tempfile.TemporaryDirectory(prefix='sill-window-mutants-') as directory:
    work = Path(directory)
    for name, old, new in mutations:
        assert source.count(old) == 1, f'{name}: stale or ambiguous pattern'
        path = work / 'ViewerWindow.swift'
        path.write_text(source.replace(old, new))
        binary = work / 'check'
        built = subprocess.run(['swiftc', '-swift-version', '5', '-j', '4', str(path), str(fixture), '-o', str(binary)], capture_output=True, text=True)
        if built.returncode:
            raise SystemExit(f'{name}: COMPILE FAILURE (not a kill)\n{built.stderr}')
        result = subprocess.run([str(binary)], capture_output=True, text=True, preexec_fn=no_core)
        if result.returncode == 0:
            raise SystemExit(f'{name}: SURVIVED\n{result.stdout}')
        print(f'{name}: killed')
print(f'mac-viewer-window: all {len(mutations)} behavioral mutants killed')
