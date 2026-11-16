#!/usr/bin/env bash
# Rebuilds Resources/Profiles from the CC0 source recordings (needs ffmpeg and python3).
#
#   make-profiles.sh <unicae "Single Keys" folder> <folder of Freesound downloads>
#
# Sources (all CC0, see README for links):
#   Classic          unicaegames "Keyboard Soundpack #1" (OpenGameArt), single presses
#   Cherry MX Clear  humi74, freesound 412926, single presses        -> sliced
#   Cherry MX Red    handygaber, freesound 499773, typing            -> sliced
#   Gateron Black    el_boss, freesound 643559, a few keystrokes     -> sliced + pitch variants
#   Cherry MX Blue   UberBosser, freesound 421581/421583/421584, single presses -> pitch variants
#
# Every sample is mono 16-bit 44.1 kHz and starts on the click (leading silence trimmed),
# so the sound lands with the key press.
set -euo pipefail

unicae="${1:?usage: make-profiles.sh <unicae Single Keys dir> <freesound dir>}"
freesound="${2:?usage: make-profiles.sh <unicae Single Keys dir> <freesound dir>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Resources/Profiles"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rate=44100
trim="silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.002"
tail="areverse,silenceremove=start_periods=1:start_threshold=-60dB,afade=t=in:d=0.01,areverse"

src() { ls "$freesound"/"$1"__*.wav | head -1; }
to_mono() { ffmpeg -hide_banner -loglevel error -y -i "$1" -ac 1 -ar $rate -c:a pcm_s16le "$2"; }
fresh() { rm -rf "$out/$1"; mkdir -p "$out/$1"; }

# Adds copies pitched -3% and +3% next to each sample (more variety from few hits).
pitch_variants() {
  local dir="$1" f base
  for f in "$dir"/*.wav; do
    base="${f%.wav}"
    for p in 97 103; do
      ffmpeg -hide_banner -loglevel error -y -i "$f" \
        -af "asetrate=$((rate * p / 100)),aresample=$rate" -c:a pcm_s16le "$base-p$p.wav"
    done
  done
}

slice() {  # slice <freesound id> <profile> <count>
  to_mono "$(src "$1")" "$work/$1.wav"
  fresh "$2"
  python3 -I "$root/scripts/slice-hits.py" "$work/$1.wav" "$out/$2" --count "$3" --max-ms 160
}

# Classic: the original pack, as recorded.
fresh "Classic"
i=0
for f in "$unicae"/keypress-*.wav; do
  i=$((i + 1))
  ffmpeg -hide_banner -loglevel error -y -i "$f" -af "$trim,$tail" -ac 1 -ar $rate -c:a pcm_s16le \
    "$out/Classic/$(printf 'key-%02d.wav' "$i")"
done

slice 412926 "Cherry MX Clear" 24
slice 499773 "Cherry MX Red" 32
slice 643559 "Gateron Black" 12
pitch_variants "$out/Gateron Black"

fresh "Cherry MX Blue"
n=0
for id in 421581 421583 421584; do  # w, q, ctrl (the space bar recording is left out)
  n=$((n + 1))
  ffmpeg -hide_banner -loglevel error -y -i "$(src $id)" -af "$trim,$tail" \
    -ac 1 -ar $rate -c:a pcm_s16le "$work/blue.wav"
  peak=$(ffmpeg -hide_banner -i "$work/blue.wav" -af astats=metadata=0 -f null - 2>&1 \
    | awk '/Peak level dB/{print $NF; exit}')
  ffmpeg -hide_banner -loglevel error -y -i "$work/blue.wav" -af "volume=$(echo "-4 - ($peak)" | bc -l)dB" \
    -c:a pcm_s16le "$out/Cherry MX Blue/$(printf 'key-%02d.wav' "$n")"  # peak at -4 dBFS like the rest
done
pitch_variants "$out/Cherry MX Blue"

for d in "$out"/*/; do echo "$(basename "$d"): $(ls "$d" | wc -l | tr -d ' ') samples"; done
