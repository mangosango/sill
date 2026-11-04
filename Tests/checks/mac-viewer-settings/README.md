# Viewer settings (offline)

Run `Tests/checks/mac-viewer-settings/run.sh` from any directory.

- Swift 5 typechecks the production AppKit/SwiftUI settings source against the real
  `HostSettings.swift` module and `HostSettingsLedger.swift`, with a compile-only
  client fixture. Nothing is instantiated or launched; no preferences are read or
  written and no clipboard, keychain or network API is exercised.
- 34 structural assertions cover the viewer-only reverse-scrolling toggle and
  pane/toolbar/window configuration (including
  fullscreen-auxiliary placement without minimize/zoom), host-reported home/away
  quality scope and mixed-session explanation, scope/privacy
  copy, retained pending/error/clipboard status, capability gates, input-release
  ordering, session identity checks in both binding types and no automatic transfer
  or host-core linkage.

These checks do not establish rendered layout, VoiceOver order, actual toolbar
selection behavior, screen changes or live remote settings acknowledgement. The
parent lane registers `MacClient/ViewerSettings.swift` and runs the real viewer
build/integration checks. Manual acceptance must cover all three panes, small
screens, long host/error names, keyboard navigation, disconnect/reconnect with an
open picker, locked/older hosts, and host refusals/timeouts.
