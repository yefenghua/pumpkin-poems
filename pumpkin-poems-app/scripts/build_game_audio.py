"""Generate original, local game music and cues; no downloaded recordings needed."""
import math
from pathlib import Path
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "pumpkin-poems-app/Resources"


def render(name, duration, notes, loop=False):
    samples = [0.0] * int(RATE * duration)
    for start, frequency, length, amplitude in notes:
        for i in range(int(RATE * length)):
            t = i / RATE
            envelope = min(1, t / 0.015) * math.exp(-4.5 * t / length) * min(1, (length - t) / 0.05)
            tone = math.sin(2 * math.pi * frequency * t) + .2 * math.sin(4 * math.pi * frequency * t)
            at = int(start * RATE) + i
            if loop:
                at %= len(samples)
            if at < len(samples):
                samples[at] += amplitude * envelope * tone
    with wave.open(str(OUT / f"game-{name}.wav"), "wb") as f:
        f.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        f.writeframes(b"".join(struct.pack("<h", round(max(-.95, min(.95, s)) * 32767)) for s in samples))


if __name__ == "__main__":
    # A calm pentatonic phrase. Wrapping each tail makes the 24-second loop continuous.
    melody = [0, 4, 7, 9, 7, 4, 2, 0, 4, 7, 12, 9, 7, 4, 2, 4]
    notes = [(i * 1.5, 261.6256 * 2 ** (pitch / 12), 2.8, .28) for i, pitch in enumerate(melody)]
    notes += [(i * 6, 130.8128 * 2 ** (pitch / 12), 5.5, .14) for i, pitch in enumerate([0, 7, 9, 4])]
    render("garden", 24, notes, loop=True)
    render("tap", .09, [(0, 660, .08, .25)])
    render("success", .6, [(0, 523.25, .35, .4), (.12, 659.25, .4, .35), (.24, 783.99, .35, .3)])
    render("error", .3, [(0, 293.66, .2, .3), (.1, 261.63, .18, .25)])
    render("complete", 1.2, [(i * .16, f, .5, .3) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])])
    print("Generated original garden loop and four interaction cues.")
