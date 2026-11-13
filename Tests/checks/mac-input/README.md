# `mac-input`

**Checks:** the Mac viewer's input in an AppKit routing fixture of unshown windows, with a recording client and a
private pasteboard (no network, visible UI or desktop input injection): Command-modified key-up delivery,
window isolation, click-to-control without click-through or hover recapture, idempotent publication,
remote system and app shortcuts, the local escape chord, released Escape and Tab delivery, native menu
tracking, pointer, drag and focus cleanup, and a drag across a clipboard write. The real
keyboard-capture manager, dispatcher and watchdog run with an in-memory `MacKeyboardTap` boundary (no TCC
queries, permission prompts or event taps; synthetic CGEvents are converted, never posted): event
suppression and pass-through, permission, Secure Input and tap failure, active VoiceOver Control-Option
and Caps Lock, rebound modifiers and repeats, and ordinary text through `interpretKeyEvents`. Scrolling:
default and reversed directions on both axes, precise and coarse deltas, unphased wheel events and the
gesture and momentum boundaries. Dock swipe suppression and its host and switch gates. The full screen
pointer lock through a fake pointer boundary (no real pointer moves): locked deltas, clamping, locked
clicks, idempotent unlock and a failed detach. Debug and optimized builds; `--mutants` must kill every
mutant without compile errors. Not physical keyboard, IME, VoiceOver, live clipboard, system tap or
two-Mac acceptance.

**Compiles:** `MacClient/StreamInputView.swift`, `MacClient/MacKeyboardCapture.swift`, `MacClient/MacKeyboard.swift`,
`MacClient/ViewerInputState.swift`, `MacClient/MacClipboard.swift`, `iOSClient/KeyChords.swift`,
`iOSClient/TextComposition.swift`, `iOSClient/TrackpadGestures.swift` and `Sources/StreamProtocol`
