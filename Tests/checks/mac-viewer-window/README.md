# `mac-viewer-window`

**Checks:** the Mac viewer's floating session window in an unshown AppKit window: recovery
notices, the frame's show and hide policy, the borderless overrides (key status, Close asking SwiftUI first,
Minimize, full screen getting its title bar back), growing and shrinking the window around the picture, the
hover band where the title bar is or would be, the 3 s linger after a click, open menus holding the bar,
the remote display's shape on resize, and the fullscreen delegate and lifecycle; with `--mutants`,
behavioral mutations it must kill. Not live appearance, fullscreen animation or VoiceOver.

**Compiles:** `MacClient/ViewerWindow.swift`; `structural.py` reads `MacClient/SillViewerApp.swift` as source

Run `Tests/checks/mac-viewer-window/run.sh`; add `--mutants` for its scratch behavioral mutations.

The wrapper compiles only `MacClient/ViewerWindow.swift` and this lane's fixture (Swift 5, at most four compiler jobs), then runs an **unshown** AppKit window. It never starts an app run loop, opens a connection, sends input, writes defaults or displays a window. Scratch binaries and mutations are removed on exit. A mutant compile failure is not counted as a kill.

Structural checks cover the frame's material, its controls and title, the picture's corners and inset, the menus' snapshot model, the invisible remote-menu anchor, menu command coverage, local Escape safety, lifecycle boundaries and clipboard capability gating.

Not acceptance evidence for real native fullscreen animation, menu positioning from the invisible anchor, SwiftUI's live delegate lifecycle, VoiceOver, Dock reopening or real input routing. Parent owns integrated build and cross-area regression checks.
