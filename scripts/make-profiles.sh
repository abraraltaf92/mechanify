#!/usr/bin/env bash
# Rebuilds Resources/Profiles from the CC0 source recordings (needs ffmpeg and python3).
#
#   make-profiles.sh <unicae "Single Keys" folder> <folder of Freesound downloads>
#
# Sources (all CC0, see README for links):
#   Cherry MX Clear  humi74, freesound 412926, single presses with releases -> sliced
#   Cherry MX Red    handygaber, freesound 499773, typing (96 kHz / 24-bit) -> sliced
#   Gateron Black    el_boss, freesound 643559, a few keystrokes            -> sliced + pitch variants
#   Cherry MX Blue   UberBosser, freesound 421581/421583/421584, single presses -> pitch variants
#   Classic          unicaegames "Keyboard Soundpack #1" (OpenGameArt), single presses
#
# Each profile gets down/ (presses) and up/ (releases). Clips are cut from the original
# files at their native sample rate and written as 24-bit mono, so no quality is lost
# to resampling. Releases come from the recording when it has clean ones; otherwise a
# softer, brighter release is derived from the presses. Every clip starts on the click.
set -euo pipefail

unicae="${1:?usage: make-profiles.sh <unicae Single Keys dir> <freesound dir>}"
freesound="${2:?usage: make-profiles.sh <unicae Single Keys dir> <freesound dir>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/Resources/Profiles"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trim="silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.002"
tail="areverse,silenceremove=start_periods=1:start_threshold=-60dB,afade=t=in:d=0.01,areverse"
enc=(-ac 1 -c:a pcm_s24le)
MIN_REAL_RELEASES=6

src() { ls "$freesound"/"$1"__*.wav | head -1; }
rate_of() { ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$1"; }
peak_db() { ffmpeg -hide_banner -i "$1" -af astats=metadata=0 -f null - 2>&1 | awk '/Peak level dB/{print $NF; exit}'; }
fresh() { rm -rf "$out/$1"; mkdir -p "$out/$1/down" "$out/$1/up"; }
count() { ls "$out/$1/$2" 2>/dev/null | wc -l | tr -d ' '; }

# cut <source> <start> <dur> <gain dB> <output>: one clip at full source quality.
cut() {
  local fade_at
  fade_at=$(awk -v d="$3" 'BEGIN{x=d-0.015; if (x<0) x=0; printf "%.5f", x}')
  ffmpeg -hide_banner -loglevel error -y -ss "$2" -t "$3" -i "$1" \
    -af "volume=${4}dB,afade=t=out:st=$fade_at:d=0.015" "${enc[@]}" "$5"
}

# slice <freesound id> <profile> <presses> <releases>
slice() {
  local source analysis kind start dur gain p=0 r=0
  source="$(src "$1")"
  analysis="$work/$1.wav"
  ffmpeg -hide_banner -loglevel error -y -i "$source" -ac 1 -ar 44100 -c:a pcm_s16le "$analysis"
  fresh "$2"
  python3 -I "$root/scripts/slice-hits.py" "$analysis" --presses "$3" --releases "$4" > "$work/$1.cuts"
  while read -r kind start dur gain; do
    case "$kind" in
      press) p=$((p + 1)); cut "$source" "$start" "$dur" "$gain" "$out/$2/down/$(printf 'press-%02d.wav' $p)" ;;
      release) r=$((r + 1)); cut "$source" "$start" "$dur" "$gain" "$out/$2/up/$(printf 'release-%02d.wav' $r)" ;;
    esac
  done < <(grep -E '^(press|release) ' "$work/$1.cuts")
  if [ "$r" -lt $MIN_REAL_RELEASES ]; then
    rm -f "$out/$2/up/"*.wav
    derive_releases "$2"
  fi
}

# A key's upstroke is a shorter, quieter, brighter tick than its press.
derive_releases() {
  local n=0 f
  for f in "$out/$1/down/"*.wav; do
    n=$((n + 1))
    [ $n -gt 12 ] && break
    ffmpeg -hide_banner -loglevel error -y -i "$f" \
      -af "atrim=0:0.07,highpass=f=900,volume=-13dB,afade=t=out:st=0.045:d=0.025" \
      "${enc[@]}" "$out/$1/up/$(printf 'release-%02d.wav' $n)"
  done
}

# Adds copies pitched -3% and +3% (more variety from few hits).
pitch_variants() {
  local f base rate p
  for f in "$1"/*.wav; do
    base="${f%.wav}"
    rate=$(rate_of "$f")
    for p in 97 103; do
      ffmpeg -hide_banner -loglevel error -y -i "$f" \
        -af "asetrate=$((rate * p / 100)),aresample=$rate" "${enc[@]}" "$base-p$p.wav"
    done
  done
}

# Single-press files: trim to the click, peak at -4 dBFS like the sliced profiles.
single() {  # single <file> <output> <normalise yes|no>
  ffmpeg -hide_banner -loglevel error -y -i "$1" -af "$trim,$tail" "${enc[@]}" "$work/single.wav"
  local gain=0
  [ "$3" = yes ] && gain=$(awk -v p="$(peak_db "$work/single.wav")" 'BEGIN{printf "%.2f", -4 - p}')
  ffmpeg -hide_banner -loglevel error -y -i "$work/single.wav" -af "volume=${gain}dB" "${enc[@]}" "$2"
}

slice 412926 "Cherry MX Clear" 24 16
slice 499773 "Cherry MX Red" 32 16
slice 643559 "Gateron Black" 12 8
pitch_variants "$out/Gateron Black/down"
pitch_variants "$out/Gateron Black/up"

fresh "Cherry MX Blue"
n=0
for id in 421581 421583 421584; do  # w, q, ctrl (the space bar recording is left out)
  n=$((n + 1))
  single "$(src $id)" "$out/Cherry MX Blue/down/$(printf 'press-%02d.wav' $n)" yes
done
pitch_variants "$out/Cherry MX Blue/down"
derive_releases "Cherry MX Blue"

fresh "Classic"
n=0
for f in "$unicae"/keypress-*.wav; do
  n=$((n + 1))
  single "$f" "$out/Classic/down/$(printf 'press-%02d.wav' $n)" no
done
derive_releases "Classic"

for d in "$out"/*/; do
  p="$(basename "$d")"
  echo "$p: $(count "$p" down) presses, $(count "$p" up) releases, $(rate_of "$(ls "$d"down/*.wav | head -1)") Hz"
done
