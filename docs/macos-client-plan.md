# Sill Viewer for macOS

Status: native viewer implementation integrated on `macos-viewer`; unsigned builds and
all 66 check suites pass. Dedicated offline checks pass after two stale structural
expectations were corrected. The review's missing IME preedit presentation is fixed
in e32e97b, with focused checks and unsigned universal Mac builds passing again.
Live and release-signed acceptance gates remain open; nothing shipped.
The original foundation-only checkpoint is superseded by the integrated work below.

## Goal

Launch a client on one Mac, connect to another Mac running Sill, and control its
Desktop in a normal resizable or full-screen Mac window. Keep the option to pick
an individual remote window, as on the iPad.

Build on the iPad client's current connection and security code, not a second
implementation of the protocol. Apple frameworks only; no servers, subscriptions
or new dependencies.

## Recommendation

Ship a separate **Sill Viewer.app**, alongside the existing **Sill.app** host.
Use native SwiftUI/AppKit views and input, sharing the iPad client's session code.
Start with **one connected Mac and one stream window at a time**.

This separates receiving from sharing: opening the viewer must not start a host,
request Screen Recording or Accessibility, create a virtual display on this Mac,
or change the installed host's settings, identity or login item. The remote Mac
still needs the host's existing permissions.

Proposed defaults:

- macOS 14 or later, Apple silicon and Intel, subject to build and hardware tests.
- A regular Dock app, not another menu-bar-only app.
- A distinct bundle ID, provisionally `me.saffer.sill.viewer`, with its own
  preferences, keychain identity, caches and logs.
- Same marketing version as Sill's other apps; build number from the commit count.
- Developer ID distribution first. Mac App Store distribution is not part of this port.
- Connect opens the Desktop using the existing automatic Desktop request. Picking
  a window remains optional; do not remember and silently reopen remote apps.

A Catalyst build may reuse more UI initially, but would still need Mac-specific
keyboard routing, pointer handling, lifecycle, clipboard and window behavior.
Native views over shared session code are the recommended direction, not a claim
that Catalyst cannot work. Do not turn the iPad's touch layout into the Mac UI.

## What exists today

Inspected local main at `41e8cb8`, `docs/BRIEF.md`, the project instructions and the
current client/host sources. The brief is historical; current code is the basis
for the port.

- `iOSClient/StreamClient.swift` owns discovery, the session, input dispatch,
  reconnection, picture recovery and presentation state. It directly uses UIKit
  images, application/scene state and `HEVCDisplayView`; it is not already a
  platform-independent client library.
- `StreamClient+Home.swift` and `StreamClient+Remote.swift` implement pairing and
  remote connections. `SessionLink`, `MessageReader`, `DiscoveryPolicy`,
  `RemoteDialPolicy` and `SavedMacs` contain reusable transport and policy code.
- `DeviceIdentity.swift` uses Security APIs and checks key persistence. Its iOS
  keychain queries must not simply be assumed safe or equivalent on macOS.
- `HEVCDisplayView.swift` wraps `AVSampleBufferDisplayLayer`, including recovery
  callbacks, cursor presentation and frame geometry. The Mac view must preserve
  those behaviors, not just enqueue HEVC frames.
- `AudioDecoder` and `AudioPlayout` are reusable. `AudioOutput` also depends on
  UIKit lifecycle and `AVAudioSession`, which need a real Mac implementation.
- `StreamClient+Clipboard.swift` has iOS-specific pasteboard, activation and Paste
  UI behavior. In particular, local-only writes and expiration cannot be silently
  discarded by an AppKit shim.
- `Sources/SillHost/StreamCoordinator.swift` owns one active source and pipeline
  shared by connected devices. A new viewer does **not** give each device an
  independent remote desktop.
- The existing wire already supports Desktop/window selection, pointer input,
  keyboard/text input, scroll phases, settings, menus, text clipboard and sound.
  This first version should need no new message kinds or protocol version.

### Existing contributions

Both PRs were open when inspected:

- [#128 — Sill Viewer for Mac, and Rust hosts for Windows and Linux](https://github.com/Saffsanity/sill/pull/128),
  head `173843be`: a native Mac target in the iOS Xcode project, with Mac views,
  keyboard handling and UIKit-shaped shims. Its description reports builds and
  synthetic streaming, but leaves actual UI input and real-host pairing untested.
  Its shims predate today's scene/recovery requirements and ignore clipboard
  local-only/expiry options. Use selected Mac code as a reference; do not import
  the Windows/Linux hosts or regard the reported tests as verification of this plan.
- [#66 — Sill Viewer: a Mac controlling another Mac](https://github.com/Saffsanity/sill/pull/66),
  head `fe6c0010`: a much broader design with separate remote-app windows, side
  streams, Dock proxies, files and extensive host changes. Its description reports
  two-Mac testing. Those features are not required for this remote-desktop goal.

Inspect and credit any reused implementation against current main. Neither PR
should be merged wholesale for this task. This planning pass read their metadata
and descriptions, and #128's platform shims; it was not a full source review.

## First-version experience

### Connect

One window lists discovered and saved Macs, with the existing connection states
and failure messages. Reuse the saved-record and row-selection rules, including
pin refusal and no downgrade to a plain connection in Release.

- Select a nearby Mac, enter its pairing code, then connect.
- Add a Mac by address and code for Tailscale or another supported remote route.
- Offer an explicit Paste Pairing Link action with confirmation. Do not claim the
  existing `sill://` URL scheme initially: installing both Mac apps must not change
  which one handles links unexpectedly.
- Reconnect after a connection loss with today's bounded retries. Disconnect is
  deliberate and must not immediately reconnect.
- Use Mac-specific words and the local Mac's name in the hello and pairing request.
- No camera scanner or USB automatic-pairing claim for Mac-to-Mac connections.

### Remote desktop

The same window becomes the stream window, titled with the remote Mac's name.
A compact toolbar offers Macs/Disconnect, Desktop, Windows/Apps, Menus and Settings.
Use standard macOS resize, minimize and full-screen controls.

Fit the Desktop inside the available picture area without distortion; black bars
are expected when the displays have different shapes. Resizing the viewer must
not imply resizing the remote physical display. For individual windows, retain
Sill's existing Aa and Virtual Display behavior, including Aa disabled on Desktop.

Send the content viewport in points, not the entire window or its backing pixels.
Observe its actual screen's scale and refresh rate when moving between displays.
Coalesce continuous live-resize reports, always sending the final size, to avoid
unnecessary remote window fits and capture restarts. Keep `ViewportBounds` and
away-session frame-rate limits.

Closing the local stream window disconnects; it must not close the remote app.
Remote window Close remains an explicit window control or remote command.

### Input and cursor

Use an AppKit `NSView` as the input surface, active only while it owns keyboard
focus in the key window. No global event tap or input-monitoring permission.

- Left/right click, double click, drag, hover, wheel and trackpad scrolling.
- Convert coordinates through the exact rendered video rectangle, including
  AppKit's coordinate direction. Ignore clicks on black bars; a drag begun inside
  must still deliver its release when it ends outside.
- Forward native scroll phases and momentum once; do not also generate the iPad's
  synthetic coast. Preserve the local Mac's natural-scrolling interpretation.
- Map hardware keys to existing HID usages; keep left/right modifiers, key ups and
  Caps Lock correct. Map only what existing hosts support; unsupported keypad/ISO
  characters need text fallback rather than invented usages or enum cases.
- Use `NSTextInputClient` for composition and committed Unicode text. Pick one
  delivery path per press: raw keys or text, never both. Test non-US layouts, dead
  keys, Chinese/Japanese composition and Korean syllable replacement.
- For raw keys, a host advertising `keyRepeat` owns repetition: suppress local
  `isARepeat` duplicates. Older hosts need an explicitly tested fallback. Never
  repeat committed IME text independently.
- Send ordinary app shortcuts such as ⌘C, ⌘S and ⌘W remotely while the stream has
  focus. Text fields, pairing and Settings keep their keys locally. Keep ⌘Q local;
  remote Quit is available through remote Menus.
- Keep macOS-reserved shortcuts such as ⌘Tab local. Provide a visible Release
  Keyboard command and a reserved escape chord (proposed ⌃⌥⌘K), without taking
  VoiceOver's commands. Do not promise interception of every system shortcut.
- Release all tracked keys/buttons on focus loss, a panel opening, disconnect,
  sleep and window close. Clear local tracking if the connection is already gone;
  remote-side disconnect cleanup remains the last defense against stuck input.

Use the host's cursor shape as the local cursor over the stream. Retain the remote
pointer reports when the host or another client controls it, without showing two
arrows for the viewer's own input. Restore the normal cursor outside the picture.

### Settings, clipboard, sound and menus

Reuse `HostSettingsLedger` and all capability checks: controls must reflect what
this host accepts, including older-host refusal, pairing restrictions and locked
states. Clearly distinguish host-wide Send Audio from this viewer's Mute.

For the first version, retain the iPad's text-only clipboard model: remote copies
arrive while sharing is enabled, and local text goes through an explicit Paste on
Remote Mac action. Do not introduce continuous local clipboard polling. Make the
remote ⌘V shortcut and the local clipboard-transfer action distinguishable so a
normal remote paste is not silently replaced by unrelated local clipboard text.
Reuse the receipt and optional paste-right-away rules, including cancellation when
the session changes. Never report a transport receipt as proof the remote app
actually inserted text.

Implement Mac pasteboard writes with a provenance marker and local-only behavior;
if preserving the ten-minute expiry, clear only when the pasteboard still holds
that same write. Never clear a newer local copy. Test the Mac host and viewer
running together, including Universal Clipboard and a second device. Password
copies follow Sill's current policy; clipboard contents must never enter logs.

Use the current kind-43 AAC-ELD path, not #66's separate audio protocol. Adapt
AVAudioEngine output, route changes, buffer/latency measurement and cleanup to
macOS. Advertise an audio codec only once the viewer can actually play it. Keep
sound a beta, with local mute and no promise to mute the remote Mac's speakers.

Show remote menus behind the toolbar's Menus button, using `MacMenuState` and
existing version/title checks. Keep the local application's menu bar local in v1;
replacing it or creating per-remote-app Dock icons is unnecessary.

## Implementation boundaries

Add a native **Sill Viewer** target and shared scheme to
`iOSClient/Sill.xcodeproj`, with Mac-only views under `MacClient/`. Compile the
reused files from their existing locations into both targets. Do not copy the
session implementation or move every file into a new package just for this port.

Introduce only the platform boundaries the compiler and behavior require:

| Area | Existing sources to reuse/adapt | Mac-specific work |
| --- | --- | --- |
| Session and trust | `StreamClient*`, `SessionLink`, `MessageReader`, `DiscoveryPolicy`, `RemoteConnector`, `RemoteDialPolicy`, `SavedMacs` | Device name, lifecycle, UI notices and image representation |
| Identity | `DeviceIdentity`, `DeviceKeyPolicy` | Viewer-only key tag/access group and macOS data-protection queries |
| Picture | `HEVCDisplayView`, `KeyframeRecovery`, `KeyframePicture`, `PointerPresence` | `NSView` wrapper, cursor, geometry and visibility |
| Input | `KeyChords`, `TextComposition`, wire input types | Native keyboard/IME and mouse/scroll bridge, small tested policies |
| Settings/menus | `HostSettingsLedger`, `MacMenuState`, `AwayCopy` | Native toolbar, popovers and menu presentation |
| Clipboard | `ClipboardPolicy`, current subscription/receipt logic | `NSPasteboard` access, explicit transfer UI and write ownership |
| Audio | `AudioDecoder`, `AudioPlayout`, reusable engine scheduling | Mac output device and lifecycle integration |
| Distribution | Existing signing/release conventions | Viewer plist, icon, entitlements/profile, build/package and release assets |

Prefer small explicitly named platform helpers and compile-time branches over
fake `UIApplication`/`UIScene` implementations that silently approximate behavior.
Extract shared HEVC sample/recovery code only where both view wrappers need it.
Keep queue ownership and callback order unchanged.

On macOS, loss of key-window status is **input focus loss**, not iOS suspension.
A visible inactive viewer should keep its session, picture and chosen audio state.
Sleep/wake, hidden/minimized windows and decoder recovery need separate handling;
never rebuild browsers on every click into another app by accident.

The viewer's identity must use an explicitly scoped data-protection keychain store
with the correct signing/profile setup, not a silent legacy-keychain fallback.
Reuse the read-back and fail-closed policy; retain saved Macs on a transient
keychain error. Verify signed release behavior across rebuilds and relaunches,
not just an ad hoc development launch. Do not migrate the host's identity.

Update test compile lists and mutation patterns whenever shared files change.
The macOS target must not pull in iPad-only Duo APIs, camera UI or touch controls;
the iOS target must not pull in AppKit. Preserve Debug-only harness isolation.

## Delivery plan and acceptance gates

### 1. Prove the platform boundary

Add the Mac target, minimal window, platform seams and renderer. Connect a Debug
viewer to a synthetic loopback host and display the Desktop test pattern. Keep
clipboard off and omit audio advertisement until those implementations exist.

**Gate:** Mac Debug/Release and iOS Debug/Release build; current shared checks pass;
parameter sets, frames, cursor shape and forced decoder recovery work. No host or
wire changes, no permissions requested for viewing.

### 2. Make it a usable remote desktop

Implement the native input bridge, focus/release rules, resize/full-screen behavior,
source picker and host settings. Add small pure checks for key mapping/repeat,
pointer geometry, scroll phases and focus transitions, with mutants for new rules.

**Gate:** on a second Mac, use TextEdit, Finder and a terminal: click, select, drag,
scroll, type, compose text, use shortcuts, hold/release keys, resize and go full
screen. No input reaches the remote Mac while local UI has focus; no key/button
stays down after switching apps or losing the connection.

### 3. Finish real pairing and reconnection

Ship discovery, typed code/address pairing, confirmed pasted links, saved Macs and
release-signed identity storage. Adapt sleep/wake and all Mac-specific words.

**Gate:** pair once and reconnect pinned after relaunch/rebuild; reject another
key and plain-door downgrade; handle removal, unreachable host, local-network
permission denial, sleep/wake and a locked/off-console host. Verify LAN and
Tailscale with two real Macs. A keychain read error must not erase pairings.

### 4. Complete daily-use features

Add text clipboard transfer, audio output, remote Menus and accessible status/error
UI. Every feature follows the current host's capability fields.

**Gate:** clipboard moves once with no echo and never clears a newer copy; sound
plays/mutes and survives an output-device change; menus fetch and act on the right
version; keyboard-only navigation and VoiceOver can connect, change settings and
disconnect. The remote desktop itself is a video, not an exported accessibility
tree: do not claim VoiceOver can inspect its pixels as remote UI elements.

### 5. Package and validate

Add a Mac viewer build to CI and a packaging script using the repository's signing
checks. Publish separately named viewer DMG/ZIP assets and checksums, without
replacing `Sill.dmg` or changing the current host's update destination. Verify the
viewer release profile and entitlements in CI before enabling publication.

Update `README.md`, `docs/DEVELOPMENT.md`, release checklist, security/privacy and
support/download pages for the new client, its permissions and limits. Update the
project's current-step entry when implementation starts, not as if it shipped now.

**Gate:** universal build verified per slice; notarized/stapled download launches
from quarantine on another Mac; pairing survives an update; host and viewer
coexist. Run all pure checks, affected mutants, all three existing iOS build modes
and Mac Debug/Release. Complete a one-hour real desktop session plus reconnect,
network loss and sleep/wake tests. Compare latency/frame drops against the iPad
baseline on the same host and network; do not promise an unmeasured latency number.

Test hosts use loopback, synthetic content, software encoding, no screen/router
access and private test pasteboards. Never run screen capture, hardware encoder
loads or input injection on the developer's working desktop without permission.
Real interaction tests require a designated second Mac and explicit operator go.

## Limits to make explicit

- The existing host has one active source shared across clients. An iPad and a Mac
  viewer connected together can change what each other sees and the host-wide
  settings. Independent desktops would require a separate host/protocol project.
- Desktop means the display today's host selects, not a new multi-monitor picker.
- The host's user session must already be running Sill. This is not a boot-time,
  FileVault-unlock or login-window remote-management service. Existing screen-lock
  behavior is inherited, not bypassed; password input needs a real-host test.
- Whole-desktop capture sees the host's desk; it is not a private second login.
- Only one viewer session is in scope. Use one session owner for browsing, pairing
  and streaming so duplicate clients cannot overwrite saved records. Concurrent
  viewers need a deliberate shared persistence model before being added.
- Self-connections and two Macs viewing each other can create recursive pictures
  and input/clipboard feedback. Warn against those configurations in the preview;
  do not claim them supported. Safe mutual viewing requires explicit loop defenses
  and likely a small, separately reviewed host change.

Deferred: multiple simultaneous remote Macs/windows, side streams, monitor selection,
file transfer, image clipboard, remote Dock integration, global shortcut capture,
host speaker muting, new virtual-display behavior, Windows/Linux hosts and CloudKit
pairing. None is necessary to deliver the requested Mac-to-Mac remote desktop.

## Implementation progress: integrated viewer

The native `Sill Viewer` target in `iOSClient/Sill.xcodeproj` now compiles the shared
client with explicit AppKit platform boundaries. `MacClient/` contains the renderer,
connection/pairing UI, pointer and keyboard/IME bridge, viewport reporting, stream
controls, clipboard and audio adapters, and remote menu UI. One app-owned client
serves one window. Existing host and wire sources are unchanged. Selected renderer
and input code credits Alexander Deutsch's PR #128; unrelated cross-platform hosts
and PR #66's protocol changes are not imported.

Viewer identity uses `me.saffer.sill.viewer` and an explicitly scoped data-protection
Keychain, with no login-keychain fallback or host-identity migration. Persistent
pairing needs a matching viewer provisioning profile and signing entitlements;
unsigned and ad-hoc builds do not establish that acceptance gate.

`Scripts/make-viewer.sh` builds a universal `Sill Viewer.app` and separately named
`Sill-Viewer.dmg`, `Sill-Viewer.zip` and both `.sha256` files under `.build/viewer/`.
CI keeps those four unsigned artifacts separate from host release assets. Developer
ID execution, notarization, stapling, quarantine acceptance and publication remain
operator gates; the scripts do not perform them.

### Verified at a4ce755, with test-only corrections a0790f1 and a0156cd

- Xcode 27.2 (27B52): unsigned universal Mac Debug and Release; both executables
  contain arm64 and x86_64. iOS Debug and Release for the generic simulator, and
  Debug for a generic device, passed. `swift build -c release --jobs 4` passed.
- `Tests/checks/run-all.sh`: all 66 suites passed sequentially in 556 seconds.
  Renderer geometry/attachment, platform helpers and assembly checks also passed.
- The connect-UI structural check stopped the verification run: it still expected
  disconnect alone. a0790f1 requires input release before disconnect and passes.
  Dedicated identity checks, pointer/viewport (28 assertions) and remote menus
  (12 assertions) then passed. A second stale literal expected earlier clipboard
  wording; a0156cd aligns it with the explicit remote/local distinction. Controls
  and surface structural checks and the 16 packaging checks pass. The full mutant
  matrix and signed packaging were not run.
- The first independent reviews lacked the committed diff and left paths unread.
  Bounded follow-up reviews used diff artifacts: no trust/media finding; one input
  blocker, invisible IME preedit, subsequently fixed below. Those reviews are not
  exhaustive or live approval.

### IME presentation fix at e32e97b

- `StreamInputView` now displays marked text in a native, non-intercepting label,
  with underlining and UTF-16 selection highlighting. It shares the candidate-window
  anchor, updates on resize and composition changes, and clears on reset. No new
  text-sending path was added; existing commit/forget semantics remain unchanged.
- `Tests/checks/mac-input/run.sh` passed in Debug and optimized Release, including
  detached label assertions for Chinese/emoji selection, clearing, focus and hit
  testing. Pointer/viewport (28 assertions) and viewer-controls structural checks
  passed. Unsigned universal Mac Debug/Release builds passed again (both slices).
  Logs: `/tmp/sill-ime-v7/`. The earlier iOS/package/full-suite gates were not rerun
  for this Mac-only slice.
- Independent current-source review found no issues, with live candidate-panel,
  VoiceOver and long-composition behavior explicitly unverified. The supervisor
  separately inspected `7440a61..e32e97b`: only the native input view and its two
  focused test files changed, with no shared iOS, host or wire changes.

### Packaging, native mutants and documentation follow-up

- f0632a2: real unsigned universal Release build and separate DMG/ZIP packaging
  passed with four compile jobs and LaunchServices registration disabled. Bundle
  0.6.1 (1303), `me.saffer.sill.viewer`, arm64 and x86_64; both checksums passed.
  Read-only private DMG inspection reported exactly the app and Applications link,
  with bundle comparison passing and the mount detached; no application launched.
  `Tests/viewer-package/check.py` passed profile/argument and behavioral failure,
  cleanup and prior-output isolation checks. CI was inspected, not run on GitHub.
  Packaging promotes validated outputs by sequential moves, not an atomic swap.
- 4927b32: focused sequential scratch-copy native input mutation checks passed:
  attempted 18, killed 18, survived 0, not-applied 0, compile-error 0, runtime-error 0.
  Both harness baselines passed first. Compile failures are not kills; behavioral
  assertion traps are. Normal mac-input Debug/optimized Release and pointer tests
  (28 assertions) passed. Logs: `/tmp/sill-input-mutants-v8.log`,
  `/tmp/sill-input-normal-v8.log`, `/tmp/sill-pointer-normal-v8.log`.
  Direct pointer-script execution was permission denied; invoking it with bash passed.
  Coverage excludes full responder callbacks/client sends: focus notification
  release, raw/text double emission, reset wiring and marked-text network silence
  are not mutation-proven. Source-wiring greps are not behavioral kills.
- Documentation now records preview usage/builds and manual release gates in
  DEVELOPMENT, README, SECURITY and the release checklist. Public site pages remain
  about shipped apps; no viewer download link or release promise was added.
  This documentation pass ran offline syntax/link/consistency checks only, not new
  builds or live acceptance. Reported free disk for both implementation slices and
  this pass: 128 GiB.
- Independent read-only review inspected the committed `e40d8d8..88347ab` diff and
  connected sources: no issues found, OK with notes for packaging, mutation tests
  and preview documentation. It did not independently run the reported tests or
  inspect built artifacts; this is not live or signed release acceptance. The
  supervisor confirmed the committed file scope and clean tree, with `git diff
  --check` passing.

### Still required before calling it ready

No viewer application has been launched during this implementation. Compilers and
isolated tests do not prove synthetic-loopback rendering, actual AppKit key delivery,
IME/candidate behavior, menu tracking, VoiceOver, audio output/device changes,
sleep/wake, real TLS pairing or a one-hour remote session. The two-Mac and signed
acceptance gates above still apply. Builds retain the known shared-client and
CaptureProbe warnings, plus the viewer's deprecated `onChange` overload and missing
app-category warning.

Co-resident clipboard forwarding is **unsupported**, not merely untested: a local
Sill host can forward text received by the viewer to its own subscribers. The viewer
warns beside Share Clipboard and permits disabling it; no host-side loop defense was
added. Do not claim the no-echo or host/viewer coexistence gate passed. Public download
and marketing pages still describe the shipped apps, not this unvalidated viewer.

## Historical implementation progress: renderer checkpoint

The following records the first checkpoint only; its missing-target and ownership
notes were superseded by the integrated implementation above.

The implementation supervisor narrowed this worker first to phase 1, then to an
independently compiled native renderer because the worker's remaining execution
context could not safely complete the shared-client port. This is **not** a
completed foundation or permission to begin dependent feature lanes against a
working viewer. Resume the foundation before integrating them.

Implemented `MacClient/HEVCDisplayView.swift`: an AppKit NSView backed by
AVSampleBufferDisplayLayer. Its AppKit geometry and cursor surface are selectively
adapted from Alexander Deutsch's PR #128, `173843be`; parameter-set caching,
frame/sample construction, lock blanking, format reset, decoder notifications,
stale-notification filtering and ordered recovery callbacks follow current main's
iPad renderer. No #66 source, host, wire, shared runtime or identity code changed.
The iPad DEBUG decoder-fault injector and HUD were not ported.

Validation: `Scripts/mac-renderer-check/run.sh` builds the real StreamProtocol
sources and renderer in Swift 5 Debug/Release modes with a compile-only
`StreamClient.CursorShape` fixture, and runs five letterbox geometry checks.
It never constructs a view, opens a window, decodes video or accesses network,
preferences, keychain or pasteboard. On Xcode 27.2 both modes passed targeting
macOS 14. An initial build at the compiler's default deployment target emitted
macOS-15 deprecation warnings for AVSampleBufferDisplayLayer's APIs; the final
macOS-14 build is clean (those APIs are retained for macOS 14 compatibility). `Tests/checks/keyframe-recovery/run.sh`: 95 checks passed.
This proves neither actual frame rendering nor recovery under a live decoder.
No Mac app build or iOS app build was run at this checkpoint.

### Resume foundation first (integration owner)

- Add the native target and shared scheme; the renderer needs a **Mac target only**
  PBXFileReference, PBXBuildFile, MacClient group entry and PBXSourcesBuildPhase
  entry for `MacClient/HEVCDisplayView.swift`. Do not add the check's fixture to
  either target. No Xcode project entries have been added yet.
- Compile current StreamClient/Home/Remote/Viewport and their actual policy
  dependencies through explicit image/device/lifecycle boundaries, not fake
  UIApplication/UIScene types. The eventual Mac `StreamClient.CursorShape.image`
  must be NSImage; the renderer otherwise keeps today's method signatures.
- Assign `renderQueue` before receiving data; call apply/enqueue/blank/clear and
  checkLayer on that queue. Wire onNeedsKeyframe/onPictureBack to the current
  KeyframeRecovery path, onVideoSize to client.videoSize, and
  onVideoSizeForPointer to pointerFrameChanged. On main wire cursor/pointer
  callbacks to setCursorShape/setPointer and attach the single view beneath the
  native input surface. The view intentionally takes no hit tests.
- Own real Mac sleep/visibility recovery separately from input focus. Inactive
  visible windows must keep receiving/rendering. No lifecycle adapter exists yet.
- Retain current trust/reconnect/pairing rules, fail-closed identity read-back and
  transient-error retention. Add viewer-only tags and explicit data-protection
  queries on macOS; never import #128's clipboard or application-state shims.
- Omit codec advertisement and clipboard subscription until the media lane has
  real adapters. No unavailable-feature stubs were added by this checkpoint.
- Pass unsigned Mac Debug/Release and iOS simulator Debug builds before calling
  this foundation ready. Real synthetic-loopback rendering remains untested.

### Following lane ownership (after resumed foundation)

1. **Native input/UI:** own new MacClient app/connect/stream/input views and Mac
   input policies/checks. Implement attachment, focus/release, viewport reporting,
   source/settings/menus UI and polished typed/confirmed-link pairing. Do not
   alter shared transport/trust or media adapters without integration review.
2. **Clipboard/audio:** own MacClient media adapters and shared
   StreamClient+Clipboard/Audio boundaries. Preserve receipt, provenance,
   local-only/owned-expiry and current AAC-ELD rules. Advertise capabilities only
   after real implementations; no preferences/keychain/pasteboard smoke tests on
   this working Mac. Coordinate shared StreamClient property changes with the
   integration owner rather than overlapping native UI edits.
3. **Packaging/CI/docs/tests:** own viewer plist, signing/profile checks, package
   scripts, workflows and public documentation. Own Xcode source registration:
   each new Swift file from either lane needs its file reference, build file,
   MacClient group and Mac Sources entry, and shared files need a Mac build file
   referring to their existing iOS file reference. Mac-only files never enter the
   iOS Sources phase. Lane authors must supply exact new filenames in handoffs;
   no speculative source entries or target file lists are established here.

Only the integration owner edits shared StreamClient lifecycle/trust and the
project while foundation resumes. This ownership list is a handoff boundary,
not a claim that the three lanes can start independently at this checkpoint.

## Approved implementation defaults

The operator approved proceeding with the plan and a Pi subagent swarm. The
implementation uses these defaults:

1. Separate Sill Viewer app rather than adding a viewer window to the existing host.
2. Native Mac UI, macOS 14+, universal binary, Developer ID distribution first.
3. One session, Desktop first, existing individual-window selection available.
4. Local system shortcuts and ⌘Q stay local; no global input capture permission.
5. Text clipboard uses an explicit local-to-remote transfer action, not continuous sync.

The plan-only commit changed no application behavior. Subsequent implementation
changes shared client code as well as adding the viewer; the build/check results
above cover those changes, not live acceptance. Native input/IME, signed keychain
persistence and real Mac lifecycle still need the acceptance gates before release.
