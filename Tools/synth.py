# генерирует звуки клавиш: python3 Tools/synth.py Sounds
# нажатие = короткий щелчок пластика (шум через два резонанса) + тихое отпускание
import math, random, struct, sys, wave, os

SR = 44100

def bandpass(x, f, q):
    w = 2 * math.pi * f / SR
    a = math.sin(w) / (2 * q)
    b0, b2, a1, a2 = a / (1 + a), -a / (1 + a), -2 * math.cos(w) / (1 + a), (1 - a) / (1 + a)
    y = []; x1 = x2 = y1 = y2 = 0.0
    for v in x:
        o = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y

def tick(n, at, f, q, decay, rnd):
    # шумовой импульс через два резонанса: основной и на октаву с лишним выше
    ex = [0.0] * n
    for i in range(int(0.004 * SR)):
        if at + i < n: ex[at + i] = rnd.uniform(-1, 1) * math.exp(-i / (decay * SR))
    lo = bandpass(ex, f, q)
    hi = bandpass(ex, f * 1.7, q * 1.3)
    return [a + 0.6 * b for a, b in zip(lo, hi)]

def key(p, rnd, size=1.0):
    n = int(0.15 * SR)
    pitch = rnd.uniform(0.94, 1.06) / size
    press = tick(n, int(0.002 * SR), p["f"] * pitch, p["q"], p["decay"] * size, rnd)
    up = int(rnd.uniform(0.06, 0.08) * SR)
    release = tick(n, up, p["f"] * pitch * 1.15, p["q"], p["decay"], rnd)
    x = [a + p["release"] * b for a, b in zip(press, release)]
    f = int(0.02 * SR)
    for i in range(f): x[n - f + i] *= (f - i) / f
    return x

def save(x, path, level):
    peak = max(abs(v) for v in x) or 1
    data = b"".join(struct.pack("<h", int(v / peak * level * 32767)) for v in x)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data); w.close()

# f — высота щелчка, q — звонкость, decay — длина, release — громкость отпускания
PACKS = {
    "Clack":  dict(f=2100, q=6,  decay=0.0025, release=0.45, level=0.75),
    "Bright": dict(f=3000, q=7,  decay=0.002,  release=0.4,  level=0.7),
    "Deep":   dict(f=1300, q=5,  decay=0.003,  release=0.4,  level=0.8),
    "Crisp":  dict(f=2600, q=4,  decay=0.0012, release=0.35, level=0.7),
    "Ring":   dict(f=1800, q=14, decay=0.0025, release=0.4,  level=0.7),
    "Soft":   dict(f=1500, q=3,  decay=0.002,  release=0.3,  level=0.45),
}

out = sys.argv[1]
for name, p in PACKS.items():
    d = os.path.join(out, name); os.makedirs(d, exist_ok=True)
    rnd = random.Random(name)
    for i in range(1, 13):
        save(key(p, rnd), f"{d}/key{i}.wav", p["level"] * rnd.uniform(0.85, 1.0))
    # длинные клавиши чуть ниже
    save(key(p, rnd, size=1.35), f"{d}/space.wav", p["level"])
    save(key(p, rnd, size=1.15), f"{d}/enter.wav", p["level"])
    save(key(p, rnd, size=1.1), f"{d}/backspace.wav", p["level"])
    print(name)
