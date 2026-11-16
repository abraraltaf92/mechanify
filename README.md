# Mechanify

A small macOS menu-bar app that plays a keyboard click every time you press a key,
in any app.

- Sounds on/off toggle, volume slider, five switch profiles recorded from real keyboards
  (Cherry MX Clear, Cherry MX Red, Gateron Black, Cherry MX Blue, Classic)
- Launch at login
- No Dock icon; lives in the menu bar
- Private by design: listen-only event tap, never reads *which* key was pressed,
  logs and stores nothing

## Install

1. Download `Mechanify-<version>.dmg` from the
   [latest release](../../releases/latest), open it and drag **Mechanify** into
   **Applications**.
2. Open Mechanify. It isn't signed with an Apple Developer ID, so macOS blocks the first
   launch: click **Done**, then go to **System Settings → Privacy & Security**, scroll down
   and click **Open Anyway** next to Mechanify. You only do this once.
3. Allow **Input Monitoring** when asked (or turn on Mechanify under System Settings →
   Privacy & Security → Input Monitoring). Clicks start within a couple of seconds.

Mechanify lives in the menu bar (the keycap icon), not the Dock. Requires macOS 14 or later.

## Build and run

Requires macOS 14+ and the Swift toolchain (Xcode or just the Command Line Tools).

```bash
scripts/build-app.sh            # builds build/Mechanify.app
open "build/Mechanify.app"
```

`scripts/build-app.sh --install` also copies the app to `~/Applications`, which is the
best place for it if you turn on **Launch at login**.

### Permission

On first launch macOS asks for **Input Monitoring** access. Turn on *Mechanify* in
System Settings → Privacy & Security → Input Monitoring (the menu has a button that opens
that page). Sounds start within a couple of seconds; no relaunch needed.

macOS ties the permission to the app's signature. Run this once so every build is signed
with the same local certificate and the permission survives rebuilds:

```bash
scripts/setup-signing.sh   # adds "Keyboard Sounds Local Signing" to your login keychain
```

Without it, builds are ad-hoc signed and each rebuild loses the permission. To clear a
stale grant: `tccutil reset ListenEvent local.keyboardsounds`, then relaunch and allow it.

## Tests

```bash
scripts/test.sh
```

## Releasing

Bump `version` in `scripts/build-app.sh`, then:

```bash
scripts/package-dmg.sh   # builds dist/Mechanify-<version>.dmg and its SHA-256
```

Attach the `.dmg` to a GitHub release tagged `v<version>`.

## How it works

| Piece | File | Job |
| --- | --- | --- |
| `KeyListener` | `Sources/MechanifyCore/KeyListener.swift` | Listen-only `CGEventTap` for key-down; skips auto-repeat; re-enables itself if macOS disables the tap |
| `SoundEngine` | `Sources/MechanifyCore/SoundEngine.swift` | `AVAudioEngine` with all samples preloaded and a pool of 12 player nodes used in rotation, so fast typing overlaps cleanly |
| `RoundRobin`, `SamplePicker` | `Sources/MechanifyCore/Selection.swift` | Voice rotation and random sample choice (never the same sample twice in a row) |
| `SoundProfile` | `Sources/MechanifyCore/SoundProfile.swift` | A profile is a folder of WAVs under `Resources/Profiles` |
| `AppState`, menu | `Sources/Mechanify/` | Settings, permission flow, launch at login, SwiftUI `MenuBarExtra` |

### Adding a profile

Drop a folder of mono WAV files (all the same sample rate) into `Resources/Profiles/<name>`
and rebuild. Trim leading silence from each file, or the click will lag behind the key.

## Sound credits

Every recording is released under [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
(no attribution required, credited here anyway). Licenses were checked on each source page.

| Profile | Source | What was done |
| --- | --- | --- |
| Cherry MX Clear | "Mechanical keyboard clicking. Different keys (4)" by **humi74**, [freesound.org/s/412926](https://freesound.org/s/412926/) | 18 single presses cut out |
| Cherry MX Red | "Keyboard clicking typing Cherry Red Mechanical" by **handygaber**, [freesound.org/s/499773](https://freesound.org/s/499773/) | 32 presses cut from typing |
| Gateron Black | "Gateron Black Switches Sound" by **el_boss**, [freesound.org/s/643559](https://freesound.org/s/643559/) | 3 clean presses, plus ±3% pitch variants |
| Cherry MX Blue | "wKey", "qKey", "ctrlKey" by **UberBosser**, [freesound.org/s/421581](https://freesound.org/s/421581/), [/421583](https://freesound.org/s/421583/), [/421584](https://freesound.org/s/421584/) | 3 presses, plus ±3% pitch variants |
| Classic | [Keyboard Soundpack #1](https://opengameart.org/node/122745) by **unicaegames** (Cherry KC 1000) | 32 single presses |

To rebuild them, download the sources and run (needs `ffmpeg` and `python3`):

```bash
scripts/make-profiles.sh "<unicae pack>/Single Keys" <folder with the Freesound .wav files>
```

`scripts/slice-hits.py` finds each keystroke in a typing recording, skips releases and
clips that overlap the next key, and keeps the most even-sounding presses.

## License

Code: [MIT](LICENSE) © 2026 Abrar Altaf Lone. Switch recordings: CC0 1.0, by the authors
credited above.

Cherry MX and Gateron are trademarks of their respective owners. Switch names are used
only to describe which switch a recording comes from; Mechanify is not affiliated with or
endorsed by them.
