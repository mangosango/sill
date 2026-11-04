# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Where things are

- `docs/HISTORY.md`: the work log, newest first. Every feature's decisions, what was
  verified, and the "Untested, for Noah" lists. Read the entry for an area before you
  change it. Add a new entry there, not here.
- `docs/AGENT-REFERENCE.md`: the file map ("Layout"), every command, test hook and
  harness argument ("Build and run"), and the full compatibility floor.
- `docs/DEVELOPMENT.md`: building, running and testing from source, for people.
- `docs/*-plan.md`: one plan per feature, with its open questions and results.
- `docs/release-checklist.md`: release, TestFlight, nightlies, secrets.
- `Tests/checks/README.md`: what each pure check compiles.
- `~/Downloads/sill-handoff/`: triage reports, release status and device-test evidence.

## Current step

**Native Mac viewer (branch `macos-viewer`, UNRELEASED source preview).** The
integrated progress in `docs/macos-client-plan.md` is authoritative. Packaging
(universal DMG/ZIP/checksums), native input mutants and preview docs are done.
Signing takes viewer-only team/bundle overrides (Sang's team `RPKWZLZ8NN`, App ID
`com.sanglee.sill.viewer`, a Developer ID profile). Sang's signed two-Mac tests passed
pairing persistence, control, input release, reconnect, Korean input, clipboard and
sound. Still open: sleep/wake, VoiceOver, notarization, quarantine. Host/iOS shipped
instructions and public download links are unchanged. Details: `docs/HISTORY.md`.

**Release 0.6.0 (2026-11-02) is published. Still open:** App Store submission and
Public Beta (Noah's clicks); right after App Review approves, merge PR #286 (main to
0.6.1) before the next 09:17 UTC nightly; the Homebrew cask bump; #62. Details and
the untested device lists: `docs/HISTORY.md`, and sill-handoff's `release-060/`.

## Rules that bite

Machine and device safety:
- Noah may be streaming from Sill.app. Before any hardware-encoder run, check
  `Scripts/encoder-check/no-device.sh`. While he streams, do not run SillHost streams,
  `simctl io recordVideo`, ReelRenderer or encoder benchmarks: they share the one encode
  engine, and the Simulator recorder outranks Sill. The Claude iOS Simulator panel counts.
- Test hosts are `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1
  SILL_TEST_NO_ROUTER=1` (and `SILL_TEST_NO_SCREEN=1` when no real window is needed).
  Keep each run under 60 s. Never let a test binary take a connection from another machine.
- Send input (`-SillInputScript`, `-SillInputTest`, `sillclient.py --input/--tap/--key`)
  only to a `--synthetic` host. A real host posts it on this Mac.
- Never run a copy of Sill.app outside /Applications: it can register with LaunchServices
  and take the login item. Test Sill.app's behavior with the bare binary
  `.build/release/SillMenuBar` (defaults domain `SillMenuBar`; delete it after). Sill.app
  ignores the TEST ONLY hooks.
- Never test the update check against GitHub (`Scripts/sillfeed.py` serves a fake feed).
- AWDL tests: test service types only, under 20 s. Never measure latency with a simulator
  on the connect screen (it turns the Mac's AWDL on).
- Use private simulators of your own and delete them after. Others share the iPad Pro 13".
- Release days: never dispatch the mutants matrix; dispatch a release's nightly after
  09:17 UTC, or cancel the scheduled duplicate.

Code:
- Host core is `SillHostCore` (`Sources/SillHost`), reached with `package` access.
- Never `MainActor.assumeIsolated` in core code (under the CLI's `dispatchMain` it traps).
- The modal-loop rule (AppDelegate's doc comment): start NSMenu.popUp, runModal or a
  terminate that can answer `.terminateLater` only from AppKit target/action, SwiftUI
  Button actions or a run-loop Timer. Errors show inline, never in alerts.
- The CLI's stdout stays byte-identical to the base: core `print`s go through the shadow
  in HostLog.swift. Check a change with a masked, sorted diff against the base build.
- Never reconfigure a running SCStream.
- New iOS files need their four pbxproj entries by hand. Swift 5 language mode.
- A new required-reason API use goes in `iOSClient/PrivacyInfo.xcprivacy` before the next upload.
- A change to a file a pure check compiles updates that check and its mutant patterns in
  the same commit. `Tests/checks/run-all.sh` runs them all (as CI does).
- Sign Sill.app with the Apple Development identity (`Scripts/make-app.sh`), never ad hoc:
  TCC grants follow the signature.
- Versions: one version for both apps. The build number is the commit count, never
  committed, never `--bump`.

## Build and run (short)

```
swift build -c release
swift run -c release SillHost --synthetic       # test pattern, no Screen Recording
Tests/checks/run-all.sh                          # every pure check (~5 min; --mutants: over an hour)
Scripts/make-app.sh                              # .build/Sill.app, Apple Development signed
python3 Scripts/sillclient.py PORT 8 desktop     # wire-format test client
```
iOS: open `iOSClient/Sill.xcodeproj`. Everything else is in `docs/AGENT-REFERENCE.md`.

## Compatibility floor (summary; full text in docs/AGENT-REFERENCE.md)

The first public builds set it for good. Every later host serves every device from the
first public build on, and every later device works with every such Mac, or says why.
- Additive only: new fields optional; never rename or retype a field; never reuse a kind
  number; no new case in an enum an older peer decodes.
- Kept as they are: the TLS home door with pairing; ALPNs `sill/1` and `sill-pair/1`,
  offered for good (a later `sill/2` only beside them); the 14-byte header; kinds 0–28,
  32, 43 and 44 and their payloads. Kinds 29–31 and 33–42 are reserved for PR #66.
- Pairing as 1.0 does it: TXT keys `r` and `p`; one kind 19 and one kind 20 per
  `sill-pair/1` connection; a new method or proof format comes with a new `v`.
- A too-old device is refused with kind 22 "update" inside a `sill/1` session, never
  served wrong. `DeviceGate.minimumDeviceVersion` is "0".
- `SillProtocol.current` (1) rises only for a change an older peer cannot skip.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading is by hand: capture queue → VT callback thread → network queue. Keep it
  explicit and commented.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple silicon).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0.
- v1 out of scope: hole punching, multi-window, layout customization.
- Audio is in, as a beta. Send Audio is on by default in Sill.app (2026-10-27). The Mac's
  menu, its Settings and a device's Settings panel set it for every device; each device's
  Mute is its own; no Sound button in the bar.
