# `viewer-controls`

**Checks:** the Mac viewer's cross-file wiring: each session action releases input first, settings scope and
clipboard safeguards, the picture surface's renderer and input attachment, viewport reporting and detach,
and the chooser's single owner and window, confirmed links, nearby discovery and lifecycle
(`Scripts/mac-connect-ui-check.py`). Structural: nothing is compiled or launched.

**Compiles:** nothing; reads `MacClient/SillViewerApp.swift`, `ViewerWindow.swift`, `ViewerSettings.swift`,
`StreamInputView.swift`, `HEVCDisplayView.swift` and `ViewerConnectView.swift` as source
