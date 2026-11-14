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
    ('fullscreen-chrome-while-controlling', 'connected && (fullScreen ? !controlling : hover)', 'connected && (fullScreen ? true : hover)'),
    ('fullscreen-chrome-needs-hover', 'connected && (fullScreen ? !controlling : hover)', 'connected && (fullScreen ? !controlling && hover : hover)'),
    ('window-chrome-hides-while-controlling', 'connected && (fullScreen ? !controlling : hover)', 'connected && !controlling && hover'),
    ('chrome-without-hover', 'connected && (fullScreen ? !controlling : hover)', 'connected && (fullScreen ? !controlling : true)'),
    ('session-window-opaque', 'window.isOpaque = !floating', 'window.isOpaque = true'),
    ('session-window-background', 'window.backgroundColor = floating ? .clear : connected ? .black : .windowBackgroundColor', 'window.backgroundColor = .windowBackgroundColor'),
    ('hover-lingers', 'guard focused else { return publish(hover: false) }', ''),
    ('focus-never-ends', '                    self?.focused = false\n', ''),
    ('click-anywhere-focuses', 'guard clicked === window, connected, bandRect.contains(convert(point, from: nil)) else { return }', 'guard clicked === window, connected else { return }'),
    ('other-window-focuses', 'guard clicked === window, connected, bandRect.contains(convert(point, from: nil)) else { return }', 'guard connected, bandRect.contains(convert(point, from: nil)) else { return }'),
    ('focus-ignored', '            focused = true\n', ''),
    ('chooser-stays-clear', 'window.isOpaque = !floating', 'window.isOpaque = false'),
    ('lights-always-shown', '!session || fullScreen || chrome', 'true'),
    ('fullscreen-hides-lights', '!session || fullScreen || chrome', '!session || chrome'),
    ('session-opaque-titlebar', 'window.titlebarAppearsTransparent = connected', 'window.titlebarAppearsTransparent = false'),
    ('chooser-keeps-full-size', 'else { window.styleMask.remove(.fullSizeContentView) }', 'else { }'),
    ('restyle-reentered', 'guard let window, !restyling else { return }', 'guard let window else { return }'),
    ('chooser-loses-toolbar', '            if window.toolbar == nil, let installed { window.toolbar = installed }\n', ''),
    ('style-change-moves-frame', 'else { window.styleMask.remove(.fullSizeContentView) }\n            if window.frame != frame { window.setFrame(frame, display: true) }', 'else { window.styleMask.remove(.fullSizeContentView) }'),
    ('floating-keeps-title', 'if floating { window.styleMask.remove(.titled) } else { window.styleMask.insert(.titled) }', 'window.styleMask.insert(.titled)'),
    ('chooser-loses-title', 'if floating { window.styleMask.remove(.titled) } else { window.styleMask.insert(.titled) }', 'if floating { window.styleMask.remove(.titled) }'),
    ('floating-not-adopted', 'if floating { ViewerFloatingWindow.adopt(window) }', ''),
    ('floating-not-keyable', 'floats(window) || inherited(window, selector)', 'inherited(window, selector)'),
    ('patches-every-window', 'objc_getAssociatedObject(window, &key) != nil && !window.styleMask.contains(.titled)', '!window.styleMask.contains(.titled)'),
    ('borderless-close-skips-swiftui', 'if window.delegate?.windowShouldClose?(window) == false { return }', ''),
    ('floating-without-shadow', 'window.hasShadow = true', 'window.hasShadow = false'),
    ('resize-ignores-aspect', 'guard let aspect, !sender.styleMask.contains(.fullScreen) else { return size }', 'guard let aspect, aspect == .zero else { return size }'),
    ('resize-always-keeps-width', 'keepWidth = size.width != sender.frame.width', 'keepWidth = true'),
    ('resize-flips-dimension', 'if keepWidth == nil {', 'if true {'),
    ('resize-mode-sticks', '        keepWidth = nil\n        original?.windowDidEndLiveResize?(notification)', '        original?.windowDidEndLiveResize?(notification)'),
    ('menu-closes-bar', 'if !menuTracking, window?.inLiveResize != true { leave() }', 'if window?.inLiveResize != true { leave() }'),
    ('aspect-not-forwarded', 'fullScreenDelegate?.aspect = next', '_ = next'),
    ('fit-wrong-height', 'let vertical = expanded ? titlebar + margin : 0', 'let vertical = titlebar + margin'),
    ('fit-ignores-expansion', 'fitted(size, aspect: aspect, keepWidth: keepWidth ?? true, expanded: expanded)', 'fitted(size, aspect: aspect, keepWidth: keepWidth ?? true, expanded: true)'),
    ('window-never-grows', 'if !expanded, ViewerFloatingWindow.floats(window) { setExpanded(true) }', ''),
    ('window-stays-grown', 'if self?.state?.chromeHover == false { self?.setExpanded(false) }', ''),
    ('window-shrinks-before-frame-hides', 'let timer = Timer(timeInterval: collapseDelay, repeats: false)', 'let timer = Timer(timeInterval: 0, repeats: false)'),
    ('expansion-moves-nothing', '                window.setFrame(frame, display: true)\n            }\n            updateTrackingAreas()', '            }\n            updateTrackingAreas()'),
    ('header-covers-top-edge', 'CGRect(x: picture.minX - margin, y: picture.maxY + resizeEdge,', 'CGRect(x: picture.minX - margin, y: picture.maxY,'),
    ('picture-top-shows-bar', 'guard expanded else { return nil }', 'guard expanded else { return CGRect(x: 0, y: size.height - titlebar, width: size.width, height: titlebar) }'),
    ('hidden-bar-ignores-pointer', 'ViewerChromePolicy.header(above: window.frame).contains(point) else { return }', 'false else { return }'),
    ('pointer-anywhere-shows-bar', 'ViewerChromePolicy.header(above: window.frame).contains(point) else { return }', 'true else { return }'),
    ('chooser-keeps-expansion', 'if !next { setExpanded(false, moveWindow: false) }', ''),
    ('title-not-held', '&& !ViewerFloatingWindow.holdsTitle(window)', ''),
    ('title-held-forever', 'objc_setAssociatedObject(window, &holdKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)', ''),
    ('lights-ignore-chrome', 'window.standardWindowButton(kind)?.isHidden = !visible', 'window.standardWindowButton(kind)?.isHidden = false'),
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
