# Native Mac viewer UX

Status: implemented and offline-verified; manual UX acceptance pending. This is a
viewer-only follow-up to [macos-client-plan.md](macos-client-plan.md), not a host/iOS
redesign or release approval.

## Goal

Another Mac, in a window. Replace the development control panel with a native Mac chooser,
a content-first unified titlebar/toolbar session, native fullscreen with dependable input
release, and classic icon-toolbar settings. Keep one app-owned StreamClient and one active
session. Preserve pairing identity, protocol compatibility, clipboard provenance, IME and
key-release safeguards, media recovery, and visible-inactive streaming.

## Approved experience

- Start view: Paired Macs and Available to Pair in a native list. Deduplicate by recognized
  identity, never name. Nearby Connect and saved Connect Remotely are distinct routes;
  absence from discovery does not mean offline. Add Mac/Pair opens one cancellable sheet
  with labelled fields, explicit paste-link confirmation, inline errors and progress.
- Session: standard resizable window and compact unified toolbar; picture fills content
  area, preserves aspect ratio and never crops remote controls. Source, input ownership,
  and secondary session actions replace the bottom control panel and permanent warnings.
  All commands remain reachable through menus. No audio button in the main toolbar.
- Fullscreen: native NSWindow fullscreen, green control/View menu/Control-Command-F
  (release input before using local keyboard shortcuts).
  Toolbar reveals at top. Explicitly released input shows persistent resume/exit controls;
  a picture click takes control without forwarding that initial click (Sang's subsequent
  click-to-control request supersedes the original toolbar-only policy). Hovering never
  takes control. Control-Option-Command-K stays the release chord,
  with a clickable alternative. Escape goes remote while controlling; local UI owns Escape
  when released. Local menus/settings/focus loss/close release tracked input safely.
- Settings: classic noncustomizable icon-label toolbar, grouped SwiftUI forms, last selected
  pane, screen-bounded height. General (local mute/input explanation), Sharing (clipboard
  preference, explicit transfer explanation and coexistence warning), Remote Mac (existing
  host settings with scope/all-device warning and capability/error handling). No host
  permissions or listener settings; no new unnecessary preferences.
- Appearance: system typography/colors/controls and native transitions. No custom glass,
  decorative dashboard, duplicate devices, or crop-to-fill streaming. Keyboard focus,
  labels, increased contrast, reduced transparency/motion and long names must work.

## Implementation lanes

1. Input ownership and reserved local commands: ViewerInputState, StreamInputView,
   MacKeyboard, real AppKit recording-fixture regression coverage and input mutants.
2. Chooser/pairing: ViewerConnectView and bounded checks.
3. Settings: ViewerSettings controller/panes and bounded checks; no SillHostCore link.
4. Session/window: SillViewerApp, native window integration/menus/fullscreen and checks.
5. Parent integration: viewer-only Xcode registration, existing cross-area wiring checks,
   builds, independent review and acceptance documentation.

The four implementation lanes run as openai/gpt-6.1-sol with low reasoning, per the user.
File ownership is disjoint. No launch, signing, installation, device/network connection,
real capture, hardware encoding, desktop input or user clipboard/keychain changes are
part of this implementation pass. Skill installation files are unrelated and left alone.

## System input-capture follow-up

Sang subsequently requested routing system keyboard shortcuts and trackpad gestures
while controlling, with pointer-out and Control–Option–Command–K as local exits.
Pointer-out release is implemented, including drag exit and no hover recapture.
Click-to-control is implemented: the activation click is consumed; later clicks
forward normally. Sang approved Accessibility permission for system-key capture and
deferred Mission Control/Exposé gestures. The original local-shortcut/no-global-hook
policy is superseded by the following implementation:

- A public `CGEventTap` intercepts keyboard downs/ups/modifiers only while the viewer
  owns focus and explicit remote control. All events use the same synchronous path
  into existing HID/text/IME handlers, preventing reordering and double delivery.
- Command-Tab, Command-Q, Command-Space and app shortcuts route remotely. Release
  first for local Settings/fullscreen/quit/disconnect shortcuts. The release chord
  stays local; active VoiceOver Control-Option and Caps Lock navigation releases
  capture and passes through. Media/power keys and system gestures are not captured.
- Inline errors keep denied/failed capture view-only. An explicit Allow Keyboard
  Capture action opens the system permission flow. No startup prompt or automatic
  recapture. Focus/pointer/menu/session loss and tap timeout release input. A main-loop
  watchdog also detects Secure Input, lost permission and a disabled tap.
- Moonlight's pinned SDL uses private `CGSSetGlobalHotKeyOperatingMode`; Sill instead
  uses the public, permission-gated API and adds no SDL/third-party dependency.
- Debug/optimized tests now run the real capture manager/dispatcher/watchdog with only
  the system tap boundary replaced. They cover pass/suppress results, exactly-once
  release, denied access, interruption, VoiceOver, and ordinary captured text through
  `interpretKeyEvents`. All **52 input mutants** were killed; focused settings/window/
  controls checks and 12 window mutants pass. Follow-up independent review approved
  both VoiceOver and production-path coverage fixes. Actual taps and TCC transitions
  were not exercised; see HISTORY and DEVELOPMENT for operator acceptance.

## Floating window and immersive full screen (2026-11-12 to 13)

Sang's later request supersedes the toolbar and persistent released-controls policy above.
The session window works like iPhone Mirroring's: a borderless window that is just the
picture until the pointer goes to where the title bar would be. Then the window grows by a
material frame with the traffic lights, the title and the controls, and shrinks back when
the pointer leaves (3 seconds later after a click in the title bar). For the Desktop, the
window keeps the remote display's shape. In full screen the controls float as a glass
capsule over a dimmed picture while input is released, and control locks the pointer to
the picture until Control-Option-Command-K. Notices sit on glass at the bottom. Dock swipes
go to the remote Mac as kind 28 gestures. Details and the untested list: HISTORY.md,
2026-11-12 to 13.

## Verification and remaining acceptance

Original redesign verification (2026-11-04; before the capture follow-up above):

- Unsigned universal Mac Debug and Release builds passed (arm64/x86_64, four jobs,
  LaunchServices registration disabled); iOS simulator Debug build passed without
  launching a simulator. Build output is isolated in `/tmp/sill-viewer-ux-build` and
  `/tmp/sill-viewer-ux-ios`, not the user's signed `.build/viewer` app.
- All **70** `Tests/checks/run-all.sh` suites passed in 612 seconds.
- Parent reran affected mutants: **31/31 input** and **12/12 window** behavioral
  mutants killed; **8/8 chooser** mutations rejected by source/policy checks.
  Input mutations had zero survivors, unapplied edits, compile or runtime errors.
- Pointer/viewport: 28 assertions; native remote menus: 12 asynchronous assertions.
  Viewer assembly, identity and package/profile/failure-path guards passed. No
  distribution app/DMG was rebuilt, signed, notarized, installed or launched.
- Independent chooser/settings and window integration review found no remaining
  blocking issues. Follow-up input review confirmed both discovered regressions
  fixed: released Escape/Tab now reach local responders, and native menu tracking
  releases held input only in the owning key window. The first review also caught
  missing Search Nearby; the explicit action and fresh-viewer policy check now exist.
- Parent caught redundant `@Published` ownership writes during refresh; publication
  is now transition-only, with recorded-publisher tests and two dedicated mutants.
- Logs: `/tmp/sill-viewer-ux-gate/`; per-suite logs remain in `.build/checks/`.
  Existing shared-client weak-capture, metadata and missing app-category warnings
  remain; there were no build errors.

The native toolbar's fullscreen auto-hide uses a narrow NSWindowDelegate proxy that
forwards SwiftUI's other delegate messages and restores the original on detach. A
hidden native anchor opens Remote Menus synchronously from local UI actions. Hidden
window fixtures exercise policies/delegation/responder dispatch, not actual fullscreen
presentation or the user's remote session. Review is source/offline approval, not
visual, accessibility, signed or live acceptance.

Manual acceptance after an explicit operator launch:

- Pairing, available/paired row grouping, connection failure/cancel and forgetting a Mac.
- Narrow windows, long names, source selection, and settings error/capability states.
- Native fullscreen on notched/non-notched displays, toolbar reveal and Dock/Space access.
- Release during held key, drag, scroll and IME; no hover recapture after release.
  Click the picture to resume; activation clicks must not click through to the remote Mac.
- Grant/revoke Accessibility on the signed viewer; denied access must remain view-only.
- Captured Command-Tab/Q/Space, Escape/V/W and modifier release; use the release chord
  before local fullscreen/settings commands. Physical Korean/IME and dead-key input.
- Secure Input/timeout interruption, both VoiceOver modifiers, and no local shortcut
  side effects while controlling. Test the actual tap, not only its offline stand-in.
- Settings opened from fullscreen; correct local mute versus host Send Audio scope.
- Network loss/reconnect, sleep/wake and closing/reopening; no stuck remote input.
- Keyboard-only access, VoiceOver for local UI, light/dark, increased contrast, reduced
  motion/transparency and enlarged text. Remote streamed pixels do not expose the remote
  accessibility tree merely because local viewer controls are accessible.
- Signing, notarization and quarantined launch remain separate release gates.

## Design basis

Reviewed supplied Quick Look and Sill host Settings images plus current SwiftUI/AppKit
sources. Local apple-design references consulted: accessibility, layout, typography, color,
designing-for-macos, windows, toolbars, going-full-screen, settings, keyboards and menu bar.
Key rules: progressive disclosure; no essential bottom-bar controls; native window/fullscreen
behavior; toolbar commands also in menus; explicit setting scope; stable toolbar settings
panes. Review/proposal did not constitute runtime visual or accessibility acceptance.
