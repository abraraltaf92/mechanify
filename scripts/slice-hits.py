#!/usr/bin/env python3
"""Cut a typing recording into single key hits (Python standard library only).

Input must be mono 16-bit PCM WAV (make-profiles.sh converts with ffmpeg first).
Finds onsets (a loud frame after a quiet stretch), cuts each hit from 2 ms before the
onset until the next hit or MAX_MS, drops quiet onsets (mostly key releases), then keeps
up to --count hits whose loudness is closest to typical, so the set sounds even.
Each hit is peak-normalised to a shared level and given a short fade-out.

usage: slice-hits.py INPUT.wav OUTPUT_DIR [--count 24] [--max-ms 180] [--prefix key]
"""
import argparse
import array
import os
import sys
import wave

FRAME_MS = 1
QUIET_BEFORE_MS = 25
MIN_HIT_MS = 60
PRE_ROLL_MS = 2
FADE_MS = 15
TARGET_PEAK = 0.63  # about -4 dBFS
MAX_PEAK_MS = 30
SECOND_HIT_AFTER_MS = 35
SECOND_HIT_RATIO = 0.4


def read_mono16(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            sys.exit(f"{path}: expected mono 16-bit PCM")
        rate = w.getframerate()
        data = array.array("h", w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        data.byteswap()
    return rate, data


def write_mono16(path, rate, samples):
    out = array.array("h", samples)
    if sys.byteorder == "big":
        out.byteswap()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())


def percentile(values, q):
    s = sorted(values)
    return s[min(len(s) - 1, int(q * len(s)))]


def find_hits(rate, data, max_ms):
    frame = max(1, rate * FRAME_MS // 1000)
    peaks = [max(map(abs, data[i:i + frame]), default=0) for i in range(0, len(data), frame)]
    floor = percentile(peaks, 0.2)
    threshold = max(floor * 8, max(peaks) * 0.06, 1)
    quiet = QUIET_BEFORE_MS // FRAME_MS

    onsets = []
    for i in range(quiet, len(peaks)):
        if peaks[i] >= threshold and all(p < threshold * 0.5 for p in peaks[i - quiet:i]):
            if not onsets or (i - onsets[-1]) * FRAME_MS >= MIN_HIT_MS:
                onsets.append(i)

    hits = []
    for n, i in enumerate(onsets):
        start = max(0, (i - PRE_ROLL_MS // FRAME_MS) * frame)
        limit = start + rate * max_ms // 1000
        if n + 1 < len(onsets):
            limit = min(limit, (onsets[n + 1] - 5) * frame)
        seg = data[start:limit]
        if len(seg) * 1000 // rate < MIN_HIT_MS:
            continue
        # A press peaks within a few ms. A late peak means the clip caught an
        # overlapping keystroke instead, so skip it.
        peak_at = max(range(len(seg)), key=lambda j: abs(seg[j]))
        if peak_at * 1000 // rate > MAX_PEAK_MS:
            continue
        # Fast typing leaves no quiet gap before the next key: cut where a second
        # hit rises out of the decay.
        peak = abs(seg[peak_at])
        rise_from = rate * SECOND_HIT_AFTER_MS // 1000
        for j in range(rise_from, len(seg), frame):
            if max(map(abs, seg[j:j + frame])) > peak * SECOND_HIT_RATIO:
                seg = seg[:max(0, j - 5 * frame)]
                break
        if len(seg) * 1000 // rate < MIN_HIT_MS:
            continue
        hits.append((peak, seg))
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("outdir")
    ap.add_argument("--count", type=int, default=24)
    ap.add_argument("--max-ms", type=int, default=180)
    ap.add_argument("--prefix", default="key")
    args = ap.parse_args()

    rate, data = read_mono16(args.input)
    hits = find_hits(rate, data, args.max_ms)
    if not hits:
        sys.exit(f"{args.input}: no hits found")

    # Releases and grazes are much quieter than presses: drop them.
    loud = percentile([p for p, _ in hits], 0.8)
    presses = [h for h in hits if h[0] >= loud * 0.45]
    typical = percentile([p for p, _ in presses], 0.5)
    chosen = sorted(presses, key=lambda h: abs(h[0] - typical))[: args.count]

    os.makedirs(args.outdir, exist_ok=True)
    fade = rate * FADE_MS // 1000
    gain = TARGET_PEAK * 32767 / typical
    for k, (_, seg) in enumerate(chosen, 1):
        out = []
        n = len(seg)
        for j, s in enumerate(seg):
            v = s * gain
            if j >= n - fade:
                v *= (n - j) / fade
            out.append(int(max(-32767, min(32767, v))))
        write_mono16(os.path.join(args.outdir, f"{args.prefix}-{k:02d}.wav"), rate, out)
    print(f"{os.path.basename(args.input)}: {len(hits)} onsets, {len(presses)} presses, kept {len(chosen)}")


if __name__ == "__main__":
    main()
