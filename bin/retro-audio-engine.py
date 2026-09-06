#!/usr/bin/env python3
"""PipeWire audio bridge for Plebs-compatible Lua visualizers.

Keeps audio capture in a helper thread and forwards frame requests to the Lua
engine with bass/mid/treble/beat values. If capture is unavailable, rendering
continues silently with zeroed metrics.
"""
import array
import math
import os
import subprocess
import sys
import threading
import time

RATE = 8000
WINDOW = 256
SPECTRUM_BINS = 16
TWIDDLES = [
    [(math.cos(2.0 * math.pi * k * n / WINDOW),
      math.sin(2.0 * math.pi * k * n / WINDOW)) for n in range(WINDOW)]
    for k in range(1, SPECTRUM_BINS + 1)
]
lock = threading.Lock()
metrics = {"bass": 0.0, "mid": 0.0, "treble": 0.0, "beat": False, "spectrum": [], "waveform": []}


def sink_monitor():
    try:
        sink = subprocess.check_output(
            ["pactl", "get-default-sink"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        monitor = f"{sink}.monitor"
        sources = subprocess.check_output(
            ["pactl", "list", "short", "sources"], text=True, stderr=subprocess.DEVNULL
        )
        for row in sources.splitlines():
            fields = row.split("\t")
            if len(fields) >= 2 and fields[1] == monitor:
                # pw-cat reliably links by numeric PipeWire/Pulse ID. The
                # monitor name is otherwise mistaken for the default mic.
                return fields[0]
        return "@DEFAULT_AUDIO_SINK@.monitor"
    except (OSError, subprocess.CalledProcessError):
        return "@DEFAULT_AUDIO_SINK@.monitor"


def spectrum_energy(samples):
    """Return a compact normalized spectrum for Lua presets."""
    result = []
    for twiddles in TWIDDLES:
        re = im = 0.0
        for sample, (cosine, sine) in zip(samples, twiddles):
            re += sample * cosine
            im -= sample * sine
        result.append(min(1.0, math.sqrt(re * re + im * im) / len(samples) * 8.0))
    return result


def capture():
    try:
        proc = subprocess.Popen(
            [
                "pw-cat", "--record", "--raw", "--target", sink_monitor(),
                "--format", "f32", "--rate", str(RATE), "--channels", "1", "-",
            ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    except OSError:
        return

    previous = 0.0
    while True:
        raw = proc.stdout.read(WINDOW * 4) if proc.stdout else b""
        if len(raw) < WINDOW * 4:
            break
        samples = array.array("f")
        samples.frombytes(raw)
        rms = min(1.0, math.sqrt(sum(x * x for x in samples) / len(samples)) * 4.0)
        spectrum = spectrum_energy(samples)
        bass = min(1.0, sum(spectrum[0:4]) / 4.0)
        mid = min(1.0, sum(spectrum[4:12]) / 8.0)
        treble = min(1.0, sum(spectrum[12:]) / max(1, len(spectrum[12:])))
        waveform = [round(max(-1.0, min(1.0, samples[i])), 4) for i in range(0, len(samples), 8)]
        beat = bass > max(0.42, previous * 1.35) and bass > 0.12
        previous = previous * 0.82 + bass * 0.18
        with lock:
            metrics.update(bass=bass, mid=mid, treble=treble, beat=beat,
                          spectrum=spectrum, waveform=waveform)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: retro-audio-engine.py SCENE.lua")
    engine = subprocess.Popen(
        ["lua", os.path.join(os.path.dirname(__file__), "retro-engine.lua"), sys.argv[1]],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    assert engine.stdin is not None and engine.stdout is not None
    threading.Thread(target=capture, daemon=True).start()
    try:
        for line in sys.stdin:
            with lock:
                m = dict(metrics)
            request = line.strip()
            if not request:
                continue
            request += " bass %.4f mid %.4f treble %.4f beat %d\n" % (
                m["bass"], m["mid"], m["treble"], 1 if m["beat"] else 0
            )
            request = request.rstrip("\n")
            request += " spectrum " + ",".join("%.4f" % x for x in m["spectrum"])
            request += " waveform " + ",".join("%.4f" % x for x in m["waveform"]) + "\n"
            engine.stdin.write(request)
            engine.stdin.flush()
            output = engine.stdout.readline()
            if not output:
                break
            sys.stdout.write(output)
            sys.stdout.flush()
    finally:
        if engine.poll() is None:
            engine.terminate()


if __name__ == "__main__":
    main()
