# генерирует звуки механической клавиатуры: python3 Tools/synth.py Sounds
import math, random, struct, sys, wave, os

SR = 44100

def biquad_bp(x, f, q):
    # полосовой резонатор
    w = 2 * math.pi * f / SR
    a = math.sin(w) / (2 * q)
    b0, b2 = a, -a
    a0, a1, a2 = 1 + a, -2 * math.cos(w), 1 - a
    b0, b2, a1, a2 = b0 / a0, b2 / a0, a1 / a0, a2 / a0
    y = [0.0] * len(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y

def lowpass(x, f):
    k = 1 - math.exp(-2 * math.pi * f / SR); y = []; s = 0.0
    for v in x:
        s += k * (v - s); y.append(s)
    return y

def burst(n, start, length, decay, rnd):
    # шумовой импульс с экспоненциальным спадом
    x = [0.0] * n
    for i in range(int(length * SR)):
        j = start + i
        if j >= n: break
        x[j] = rnd.uniform(-1, 1) * math.exp(-i / (decay * SR))
    return x

def tone(n, start, f, decay, rnd):
    # затухающий синус: корпус клавиши
    x = [0.0] * n; ph = rnd.uniform(0, 6.28)
    for i in range(n - start):
        e = math.exp(-i / (decay * SR))
        if e < 1e-4: break
        x[start + i] = math.sin(ph + 2 * math.pi * f * i / SR) * e
    return x

def mix(*parts):
    return [sum(p) for p in zip(*parts)]

def scale(x, g):
    return [v * g for v in x]

def hit(n, at, p, rnd, size, gain):
    # удар клавиши о дно: щелчок пластика + резонанс корпуса
    pitch = rnd.uniform(0.93, 1.07) / size
    out = []
    for f, q, d, g in p["modes"]:
        ex = burst(n, at, 0.004, 0.0015, rnd)
        out.append(scale(biquad_bp(ex, f * pitch, q), g * p["plastic"] * rnd.uniform(0.85, 1.15)))
    body = tone(n, at, p["body"] * pitch, p["body_decay"] * size, rnd)
    out.append(scale(body, p["body_gain"]))
    noise = lowpass(burst(n, at, 0.03 * size, p["noise_decay"] * size, rnd), p["noise_lp"])
    out.append(scale(noise, p["noise_gain"]))
    return scale(mix(*out), gain)

def key(p, rnd, size=1.0, rattle=0.0):
    n = int(0.26 * SR * max(1, size))
    parts = []
    at = int(0.003 * SR)
    if p.get("click"):
        # отдельный щелчок переключателя до удара о дно
        c = biquad_bp(burst(n, at, 0.002, 0.0006, rnd), rnd.uniform(4200, 5200), 3)
        parts.append(scale(c, p["click"]))
        at += int(0.006 * SR)
    parts.append(hit(n, at, p, rnd, size, 1.0))
    # отпускание: тише и выше
    up = at + int(rnd.uniform(0.07, 0.095) * SR)
    parts.append(hit(n, up, p, rnd, size * 0.8, p["release"]))
    if p.get("click"):
        c = biquad_bp(burst(n, up - int(0.004 * SR), 0.002, 0.0005, rnd), rnd.uniform(3800, 4600), 3)
        parts.append(scale(c, p["click"] * 0.6))
    if rattle:
        # дребезг стабилизатора на длинных клавишах
        r = at + int(0.012 * SR)
        parts.append(scale(biquad_bp(burst(n, r, 0.004, 0.002, rnd), 2600, 6), rattle))
    x = mix(*parts)
    # плавный хвост
    f = int(0.03 * SR)
    for i in range(f): x[n - f + i] *= (f - i) / f
    return x

def save(x, path, level):
    peak = max(abs(v) for v in x) or 1
    data = b"".join(struct.pack("<h", int(max(-1, min(1, v / peak * level)) * 32767)) for v in x)
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data); w.close()

# (частота, добротность, спад, громкость) резонансов пластика
PACKS = {
    # глухой, низкий, смазанные линейные
    "Thock": dict(plastic=4, modes=[(900, 4, 0, 1.0), (1700, 5, 0, 0.5), (3100, 6, 0, 0.15)], body=190, body_decay=0.018, body_gain=0.5,
                  noise_lp=1800, noise_decay=0.004, noise_gain=0.4, release=0.35, level=0.8),
    # плотный «кремовый», средний
    "Cream": dict(plastic=6, modes=[(1300, 5, 0, 1.0), (2400, 6, 0, 0.45), (4200, 8, 0, 0.15)], body=280, body_decay=0.012, body_gain=0.4,
                  noise_lp=2600, noise_decay=0.003, noise_gain=0.35, release=0.3, level=0.75),
    # звонкий пластик, высокий
    "Clack": dict(plastic=9, modes=[(2100, 6, 0, 1.0), (3600, 8, 0, 0.7), (5600, 10, 0, 0.35)], body=420, body_decay=0.008, body_gain=0.2,
                  noise_lp=5000, noise_decay=0.0025, noise_gain=0.4, release=0.45, level=0.75),
    # щёлкающие переключатели
    "Click": dict(plastic=7, modes=[(1600, 5, 0, 1.0), (3000, 7, 0, 0.5)], body=300, body_decay=0.01, body_gain=0.3,
                  noise_lp=3500, noise_decay=0.003, noise_gain=0.3, release=0.4, click=1.6, level=0.8),
    # тактильные, с небольшим бугорком
    "Tactile": dict(plastic=6, modes=[(1150, 4, 0, 1.0), (2200, 6, 0, 0.5), (3800, 8, 0, 0.2)], body=240, body_decay=0.014, body_gain=0.4,
                    noise_lp=2200, noise_decay=0.004, noise_gain=0.4, release=0.4, click=0.35, level=0.75),
    # тихие, приглушённые
    "Soft": dict(plastic=3, modes=[(700, 3, 0, 1.0), (1300, 4, 0, 0.35)], body=160, body_decay=0.012, body_gain=0.5,
                 noise_lp=1200, noise_decay=0.003, noise_gain=0.3, release=0.25, level=0.45),
}

out = sys.argv[1]
for name, p in PACKS.items():
    d = os.path.join(out, name); os.makedirs(d, exist_ok=True)
    rnd = random.Random(name)
    for i in range(1, 13):
        save(key(p, rnd), f"{d}/key{i}.wav", p["level"] * rnd.uniform(0.85, 1.0))
    save(key(p, rnd, size=1.6, rattle=0.25), f"{d}/space.wav", p["level"])
    save(key(p, rnd, size=1.25, rattle=0.12), f"{d}/enter.wav", p["level"])
    save(key(p, rnd, size=1.2, rattle=0.08), f"{d}/backspace.wav", p["level"])
    print(name)
