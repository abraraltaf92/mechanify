#!/usr/bin/env bash
# Builds the three sound profiles from the CC0 "Keyboard Soundpack #1" by unicaegames
# (https://opengameart.org/node/122745). Pass the pack's "Single Keys" folder.
#
#   natural - as recorded, leading silence trimmed
#   deep    - pitched down ~18% and low-passed (a heavier, "thocky" feel)
#   crisp   - pitched up ~15%, low end cut, highs lifted (a brighter, "clicky" feel)
#
# Leading silence is trimmed so the click starts on the first sample: the raw files
# carry up to ~55 ms of silence, which would be heard as lag.
set -euo pipefail

src="${1:?usage: make-profiles.sh <path to 'Single Keys' folder>}"
out="$(cd "$(dirname "$0")/.." && pwd)/Resources/Profiles"
rate=44100
trim="silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.002"
tail="areverse,silenceremove=start_periods=1:start_threshold=-60dB,afade=t=in:d=0.01,areverse"

chain() {  # macOS ships bash 3.2, so no associative arrays
  case "$1" in
    natural) echo "$trim,$tail" ;;
    deep) echo "asetrate=$((rate * 82 / 100)),aresample=$rate,lowpass=f=3200,volume=1.6,$trim,$tail" ;;
    crisp) echo "asetrate=$((rate * 115 / 100)),aresample=$rate,highpass=f=450,treble=g=4:f=4000,$trim,$tail" ;;
  esac
}

for profile in natural deep crisp; do
  mkdir -p "$out/$profile"
  rm -f "$out/$profile"/*.wav
  i=0
  for f in "$src"/keypress-*.wav; do
    i=$((i + 1))
    ffmpeg -hide_banner -loglevel error -y -i "$f" -af "$(chain "$profile")" \
      -ac 1 -ar "$rate" -c:a pcm_s16le "$out/$profile/$(printf 'key-%02d.wav' "$i")"
  done
  echo "$profile: $i samples"
done
