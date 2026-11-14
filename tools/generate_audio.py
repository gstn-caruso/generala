"""Generate the game's original, small sound effects (standard library only)."""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
random.seed(42)


def save(name, duration, sample):
    values = [max(-1, min(1, sample(i / RATE))) for i in range(int(duration * RATE))]
    with wave.open(str(OUT / f"{name}.wav"), "wb") as file:
        file.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        file.writeframes(b"".join(struct.pack("<h", int(v * 26000)) for v in values))


def knock(t):
    return (math.sin(t * 2 * math.pi * 420) * 0.55 + random.uniform(-1, 1) * 0.35) * math.exp(-t * 85)


OUT.mkdir(parents=True, exist_ok=True)
save("hit", 0.15, knock)
save("select", 0.12, lambda t: math.sin(t * 2 * math.pi * 880) * math.exp(-t * 55) * 0.25)
save("roll", 0.65, lambda t: sum(knock(t - p) * 0.5 for p in (0, .08, .17, .27, .39) if t >= p))
notes = (523.25, 659.25, 783.99)
save("score", 0.65, lambda t: sum(math.sin((t - i * .075) * 2 * math.pi * note) * math.exp(-(t - i * .075) * 8) * .16 for i, note in enumerate(notes) if t >= i * .075))
