# Design — Mechanify (v1)

Date: 2026-11-16

## Goal

A menu-bar app that plays a key click on every global key press with no noticeable lag,
with an on/off toggle, volume, a choice of sound profiles and launch at login.

## Decisions

- **Stack:** Swift + SwiftUI `MenuBarExtra`, built with Swift Package Manager.
  `scripts/build-app.sh` assembles and ad-hoc signs the `.app` (`LSUIElement`, no Dock icon),
  so the project builds without Xcode.
- **Key capture:** listen-only `CGEventTap` on key-down. Needs Input Monitoring only (not
  Accessibility), cannot modify input. The callback reads only the auto-repeat flag, never the
  key code or characters. Nothing is logged or persisted.
- **Permission flow:** `CGPreflightListenEventAccess` at launch; if missing, call
  `CGRequestListenEventAccess`, show a notice with a link to the Input Monitoring settings
  pane, and poll every 2 s until granted, then start the tap without a relaunch.
- **Playback:** `AVAudioEngine`, all samples of the active profile decoded into
  `AVAudioPCMBuffer`s up front, 12 always-running `AVAudioPlayerNode`s used round-robin.
  A random sample per press (never the same twice in a row), slight random gain. Engine restarts
  on `AVAudioEngineConfigurationChange` (output device change).
- **Sounds:** CC0 recordings of real switches from Freesound (Cherry MX Clear, Cherry MX Red,
  Gateron Black, Cherry MX Blue) plus the CC0 unicaegames pack (Classic). Typing recordings are
  cut into single presses by `scripts/slice-hits.py`. Leading silence (up to ~55 ms in raw
  files) is trimmed to keep latency low. The v1 synthetic Deep/Crisp variants were dropped
  in favour of real switches. Commercial apps' sounds are deliberately not used.
- **Settings:** `UserDefaults` via `@AppStorage`: enabled, volume, profile.
- **Launch at login:** `SMAppService.mainApp`.

## Out of scope for v1

Separate key-up sounds, distinct sounds for space/return/backspace, a global mute hotkey.
The profile format (a folder of WAVs) leaves room to add these later.

## Testing

Unit tests (Swift Testing) for voice rotation, sample picking, profile discovery, and decoding
and playing every bundled profile. A manual check that typing in other apps clicks with no lag.
