# `mac-clipboard-adapter`

**Checks:** the Mac viewer's clipboard adapter on a private pasteboard: a remote copy is not read back for
transfer, a local copy after it is, an owned write expires without touching a newer local copy, reset
clears only the viewer's own write, and transfers keep to their byte limit.

**Compiles:** `MacClient/MacClipboard.swift`
