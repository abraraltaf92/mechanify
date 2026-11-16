# Keyboard Sounds

A small macOS menu-bar app that plays a keyboard click every time you press a key,
in any app.

- Sounds on/off toggle, volume slider, three sound profiles (Natural, Deep, Crisp)
- Launch at login
- No Dock icon; lives in the menu bar
- Private by design: listen-only event tap, never reads *which* key was pressed,
  logs and stores nothing

## Build and run

Requires macOS 14+ and the Swift toolchain (Xcode or just the Command Line Tools).

```bash
scripts/build-app.sh            # builds build/Keyboard Sounds.app
open "build/Keyboard Sounds.app"
```

`scripts/build-app.sh --install` also copies the app to `~/Applications`, which is the
best place for it if you turn on **Launch at login**.

### Permission

On first launch macOS asks for **Input Monitoring** access. Turn on *Keyboard Sounds* in
System Settings → Privacy & Security → Input Monitoring (the menu has a button that opens
that page). Sounds start within a couple of seconds; no relaunch needed.

The app is ad-hoc signed, and macOS ties the permission to the signature. After a
rebuild, if sounds stop, remove the old entry from the Input Monitoring list (or toggle it
off and on) and allow it again.

## Tests

```bash
scripts/test.sh
```

## How it works

| Piece | File | Job |
| --- | --- | --- |
| `KeyListener` | `Sources/KeyboardSoundsCore/KeyListener.swift` | Listen-only `CGEventTap` for key-down; skips auto-repeat; re-enables itself if macOS disables the tap |
| `SoundEngine` | `Sources/KeyboardSoundsCore/SoundEngine.swift` | `AVAudioEngine` with all samples preloaded and a pool of 12 player nodes used in rotation, so fast typing overlaps cleanly |
| `RoundRobin`, `SamplePicker` | `Sources/KeyboardSoundsCore/Selection.swift` | Voice rotation and random sample choice (never the same sample twice in a row) |
| `SoundProfile` | `Sources/KeyboardSoundsCore/SoundProfile.swift` | A profile is a folder of WAVs under `Resources/Profiles` |
| `AppState`, menu | `Sources/KeyboardSounds/` | Settings, permission flow, launch at login, SwiftUI `MenuBarExtra` |

### Adding a profile

Drop a folder of mono WAV files (all the same sample rate) into `Resources/Profiles/<name>`
and rebuild. Trim leading silence from each file, or the click will lag behind the key.

## Sound credits

All three profiles are derived from
[Keyboard Soundpack #1](https://opengameart.org/node/122745) by **unicaegames**
(32 single keypresses, Cherry KC 1000), released under
[CC0](https://creativecommons.org/publicdomain/zero/1.0/). `scripts/make-profiles.sh`
regenerates them from the pack's `Single Keys` folder (needs `ffmpeg`).
