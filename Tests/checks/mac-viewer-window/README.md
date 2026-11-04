# Viewer window checks

Run `Tests/checks/mac-viewer-window/run.sh`; add `--mutants` for 12 scratch behavioral mutations.

The wrapper compiles only `MacClient/ViewerWindow.swift` and this lane's fixture (Swift 5, at most four compiler jobs), then runs an **unshown** AppKit window. It never starts an app run loop, opens a connection, sends input, writes defaults or displays a window. Scratch binaries and mutations are removed on exit. A mutant compile failure is not counted as a kill.

Behavioral coverage: healthy video has no band; notice/no-source/no-video/slow-link recovery; original delegate forwarding and fullscreen-option preservation; explicit native toolbar auto-hide; close notification; transition input release; published fullscreen state; no geometry resize during transition; delegate restoration after detach.

Structural checks cover the three visible toolbar actions, invisible/non-hit-testing native remote-menu anchor, menu command coverage, local Escape safety, lifecycle boundaries and clipboard capability gating.

Not acceptance evidence for real native fullscreen animation/top-edge reveal, menu positioning from the invisible anchor, SwiftUI's live delegate lifecycle, toolbar overflow, VoiceOver, Dock reopening or real input routing. Parent owns integrated build and cross-area regression checks.
