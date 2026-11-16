#!/usr/bin/env python3
"""Find single key presses and releases in a typing recording (standard library only).

Analyses a mono 16-bit WAV copy of the recording and prints a cut list; make-profiles.sh
then cuts each clip from the ORIGINAL file at its native sample rate and bit depth, so
the analysis copy's lower quality never reaches the app.

Output (times in seconds):
    gain_db <dB that brings a typical press to about -4 dBFS>
    press <start> <duration> <gain dB>
    release <start> <duration> <gain dB>

A press is a loud onset after a quiet stretch whose peak comes early. A release is the
same shape, much quieter (the key springing back up). Clips that catch an overlapping
keystroke are cut short or skipped.

usage: slice-hits.py ANALYSIS.wav [--presses 24] [--releases 16] [--max-ms 160]
"""
import argparse
import array
import math
import sys
import wave

FRAME_MS = 1
QUIET_BEFORE_MS = 25
MIN_PRESS_MS = 60
MIN_RELEASE_MS = 35
PRE_ROLL_MS = 2
MAX_PEAK_MS = 30
SECOND_HIT_AFTER_MS = 35
SECOND_HIT_RATIO = 0.4
TARGET_PEAK = 0.63  # about -4 dBFS
CEILING = 0.89  # about -1 dBFS: no clip may peak above this


def read_mono16(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            sys.exit(f"{path}: expected mono 16-bit PCM")
        rate = w.getframerate()
        data = array.array("h", w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    return rate, data


def percentile(values, q):
    s = sorted(values)
    return s[min(len(s) - 1, int(q * len(s)))]


def find_hits(rate, data, max_ms):
    """Returns (peak, start_sample, length) for every clean onset."""
    frame = max(1, rate * FRAME_MS // 1000)
    peaks = [max(map(abs, data[i:i + frame]), default=0) for i in range(0, len(data), frame)]
    floor = percentile(peaks, 0.2)
    threshold = max(floor * 6, max(peaks) * 0.03, 1)
    quiet = QUIET_BEFORE_MS // FRAME_MS

    onsets = []
    for i in range(quiet, len(peaks)):
        if peaks[i] >= threshold and all(p < threshold * 0.5 for p in peaks[i - quiet:i]):
            if not onsets or (i - onsets[-1]) * FRAME_MS >= MIN_RELEASE_MS:
                onsets.append(i)

    hits = []
    for n, i in enumerate(onsets):
        start = max(0, (i - PRE_ROLL_MS // FRAME_MS) * frame)
        limit = start + rate * max_ms // 1000
        if n + 1 < len(onsets):
            limit = min(limit, (onsets[n + 1] - 5) * frame)
        seg = data[start:limit]
        if not seg:
            continue
        peak_at = max(range(len(seg)), key=lambda j: abs(seg[j]))
        if peak_at * 1000 // rate > MAX_PEAK_MS:
            continue  # caught an overlapping keystroke
        peak = abs(seg[peak_at])
        length = len(seg)
        for j in range(rate * SECOND_HIT_AFTER_MS // 1000, len(seg), frame):
            if max(map(abs, seg[j:j + frame])) > peak * SECOND_HIT_RATIO:
                length = max(0, j - 5 * frame)
                break
        hits.append((peak, start, length))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--presses", type=int, default=24)
    ap.add_argument("--releases", type=int, default=16)
    ap.add_argument("--max-ms", type=int, default=160)
    args = ap.parse_args()

    rate, data = read_mono16(args.input)
    hits = find_hits(rate, data, args.max_ms)
    if not hits:
        sys.exit(f"{args.input}: no hits found")

    loud = percentile([p for p, _, _ in hits], 0.8)
    min_press = rate * MIN_PRESS_MS // 1000
    min_release = rate * MIN_RELEASE_MS // 1000
    presses = [h for h in hits if h[0] >= loud * 0.45 and h[2] >= min_press]
    releases = [h for h in hits if loud * 0.08 <= h[0] < loud * 0.45 and h[2] >= min_release]

    typical = percentile([p for p, _, _ in presses], 0.5)
    chosen = sorted(presses, key=lambda h: abs(h[0] - typical))[: args.presses]
    typical_release = percentile([p for p, _, _ in releases], 0.5) if releases else 0
    chosen_releases = sorted(releases, key=lambda h: abs(h[0] - typical_release))[: args.releases]

    # One gain for every clip, so releases stay as much quieter as they really are,
    # capped per clip so the loudest presses never clip.
    gain_db = 20 * math.log10(TARGET_PEAK * 32767 / typical)
    print(f"gain_db {gain_db:.2f}")
    for kind, group in (("press", chosen), ("release", chosen_releases)):
        for peak, start, length in sorted(group, key=lambda h: h[1]):
            clip_gain = min(gain_db, 20 * math.log10(CEILING * 32767 / peak))
            print(f"{kind} {start / rate:.5f} {length / rate:.5f} {clip_gain:.2f}")
    print(f"{args.input}: {len(hits)} onsets, kept {len(chosen)} presses, "
          f"{len(chosen_releases)} releases", file=sys.stderr)


if __name__ == "__main__":
    main()
