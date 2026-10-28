#!/usr/bin/env python3
"""Makes the game's music and sound effects (assets/audio/*.mp3).

Everything is synthesized here, offline, with numpy, and encoded with ffmpeg:
no samples, no noise floors, no clipping. Sounds that carry a pitch use notes
from the music's key (D major), so they sit well together.

    python tool/make_audio.py              all files
    python tool/make_audio.py grab foot    only the files whose names start so

Needs numpy, and ffmpeg (with libmp3lame) on PATH.
"""
import pathlib
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets' / 'audio'


# ---------------------------------------------------------------- basics

def hz(m):
    """MIDI note number to frequency."""
    return 440.0 * 2 ** ((m - 69) / 12)


def samples(seconds):
    return int(round(seconds * SR))


def ramp(n):
    """A raised-cosine fade from 0 to 1 over n samples (no clicks)."""
    if n <= 0:
        return np.ones(0)
    return 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))


def env(total, attack, tau, length=None, release=0.08):
    """Attack, then an exponential decay with time constant tau; after
    `length` seconds the note is let go and fades with `release`."""
    n = samples(total)
    t = np.arange(n) / SR
    e = np.exp(-t / tau) if tau else np.ones(n)
    a = min(samples(attack), n)
    e[:a] *= ramp(a)
    if length is not None and length < total:
        k = samples(length)
        e[k:] *= np.exp(-(t[k:] - t[k]) / release)
    return e


def osc(freq, n, phase=0.0):
    """A sine; freq may be a number or an array (a glide)."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.sin(phase + 2 * np.pi * np.cumsum(f) / SR)


def glide(f0, f1, n, curve=2.0):
    """Frequency moving from f0 to f1 (exponential-ish when curve > 1)."""
    u = np.linspace(0, 1, n) ** (1 / curve)
    return f0 * (f1 / f0) ** u


def partials(freq, total, spec, attack=0.004, length=None, release=0.08, detune=0.0):
    """Additive tone: spec is [(ratio, amplitude, decay seconds), ...]."""
    n = samples(total)
    out = np.zeros(n)
    for ratio, amp, tau in spec:
        f = freq * ratio * (1 + detune)
        if f > SR * 0.45:
            continue
        out += amp * osc(f, n) * env(total, attack, tau, length, release)
    return out


def shape(x, lo=None, hi=None, order=2):
    """Gentle band shaping in the frequency domain (zero phase, circular).
    lo/hi are the corner frequencies of a Butterworth-like high/low pass."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR) + 1e-9
    g = np.ones_like(f)
    if hi:
        g /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1 + (lo / f) ** (2 * order))
    return np.fft.irfft(spec * g, len(x))


def noise(n, rng, lo=None, hi=None, order=2):
    """Filtered noise, scaled to unit RMS."""
    pad = samples(0.05)
    x = shape(rng.standard_normal(n + 2 * pad), lo, hi, order)[pad:pad + n]
    return x / (np.sqrt((x ** 2).mean()) + 1e-12)


def place(dst, src, at):
    """Mixes src into dst starting at sample `at` (cut at the end)."""
    at = int(at)
    if at >= len(dst):
        return
    m = min(len(src), len(dst) - at)
    dst[at:at + m] += src[:m]


def impulse(seconds, rt60, rng, bright=4500, stereo=True):
    """A soft room: early taps, then a dark, smoothly decaying tail."""
    n = samples(seconds)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        tail = shape(rng.standard_normal(n), 120, bright, 1) * np.exp(-6.91 * t / rt60)
        tail[:samples(0.012)] = 0
        tail *= ramp(n)[::-1] ** 0.25  # end at zero
        for ms, g in [(11, 0.5), (17, 0.35), (23, 0.3), (31, 0.22)]:
            tail[samples(ms / 1000) + rng.integers(0, 20)] += g * rng.choice([-1, 1])
        chans.append(tail / np.sqrt((tail ** 2).sum()))
    return chans


def convolve(x, ir, circular=False):
    """FFT convolution. Circular wraps the tail around (for seamless loops)."""
    if circular:
        n = len(x)
        h = np.zeros(n)
        h[:min(n, len(ir))] = ir[:n]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


def room(x, wet, rt60=0.7, seed=1, bright=4500):
    """Adds a little space to a mono sound: the dry sound at full level plus
    `wet` times a soft room (the impulse has unit energy)."""
    rng = np.random.default_rng(seed)
    (ir,) = impulse(rt60 * 1.4, rt60, rng, bright, stereo=False)
    y = wet * convolve(x, ir)
    y[:len(x)] += x
    return y


def finish(x, loud_db, floor_db=-70.0, fade=0.02):
    """Sets the loudness of the loud part, keeps the peak under -1 dBFS,
    cuts the silent tail and fades the end to true zero."""
    win = samples(0.03)
    frames = x[:len(x) // win * win].reshape(-1, win)
    rms = np.sqrt((frames ** 2).mean(1))
    loud = rms[rms > rms.max() * 0.25]
    level = np.sqrt((loud ** 2).mean())
    x = x * (10 ** (loud_db / 20) / level)
    peak = np.max(np.abs(x))
    if peak > 10 ** (-1 / 20):
        x *= 10 ** (-1 / 20) / peak
    above = np.nonzero(np.abs(x) > 10 ** (floor_db / 20))[0]
    end = above[-1] + 1 if len(above) else len(x)
    x = x[:end].copy()
    f = min(samples(fade), len(x))
    x[len(x) - f:] *= ramp(f)[::-1]
    return x


def write(name, x):
    """Encodes mono (1-D) or stereo (2 x n) audio to assets/audio/<name>.mp3."""
    stereo = x.ndim == 2
    data = (x.T if stereo else x).astype(np.float32).tobytes()
    OUT.mkdir(parents=True, exist_ok=True)
    cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2' if stereo else '1', '-i', '-',
           '-c:a', 'libmp3lame', '-q:a', '5' if stereo else '6', str(OUT / f'{name}.mp3')]
    subprocess.run(cmd, input=data, check=True)
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    print(f'{name:<16} {x.shape[-1] / SR:5.2f} s  peak {peak:6.1f} dB')


# ---------------------------------------------------------------- instruments

def ep(m, total, length, vel, rng):
    """Electric piano: warm fundamental, softer overtones, a bell-like tine on
    the attack. Brighter when played harder, darker up high."""
    soft = 1 - np.clip((m - 52) / 40, 0, 0.6)
    b = 0.6 + 0.8 * vel
    spec = [(1, 1.0, 2.4), (2, 0.42 * b * soft, 1.0), (3, 0.14 * b * soft, 0.5),
            (4.02, 0.1 * b, 0.14), (7.1, 0.025 * b, 0.06)]
    return vel * partials(hz(m), total, spec, attack=0.005, length=length, release=0.35,
                          detune=rng.uniform(-0.0012, 0.0012))


def kalimba(m, vel, total=1.6):
    """Soft mallet: a round fundamental and two quick, quiet overtones."""
    spec = [(1, 1.0, 0.75), (3.93, 0.18, 0.09), (9.2, 0.035, 0.03)]
    return vel * partials(hz(m), total, spec, attack=0.003)


def bell(m, vel, total=2.2, tau=1.1):
    """A warm chime for the save, top and best sounds."""
    spec = [(1, 1.0, tau), (2.0, 0.22, tau * 0.6), (3.0, 0.1, tau * 0.35), (4.16, 0.06, tau * 0.2)]
    return vel * partials(hz(m), total, spec, attack=0.004)


def mallet(m, vel, total=0.5, tau=0.18):
    """Short muted wood tone for small cues."""
    return vel * partials(hz(m), total, [(1, 1.0, tau), (3.9, 0.12, tau * 0.2)], attack=0.003)


def pat(f0, f1, tau, total, attack=0.002):
    """The body of a soft impact: a sine that drops in pitch and dies away."""
    n = samples(total)
    return osc(glide(f0, f1, n, 3.0), n) * env(total, attack, tau)


# ---------------------------------------------------------------- sound effects

def grab(kind, v):
    """A hand closing on a hold: a soft woody pat (jug), a crisp tick on a
    small edge (crimp), a dull round pat on a sloper."""
    rng = np.random.default_rng(100 + v * 7 + {'jug': 0, 'crimp': 1, 'sloper': 2}[kind])
    p = 1 + (v - 1) * 0.045
    total = 0.35
    n = samples(total)
    if kind == 'jug':
        x = pat(175 * p, 118 * p, 0.05, total)
        x += 0.32 * partials(610 * p, total, [(1, 1, 0.026), (2.47, 0.35, 0.012)])
        grit = 0.07
    elif kind == 'crimp':
        x = 0.6 * pat(225 * p, 160 * p, 0.035, total)
        x += 0.36 * partials(900 * p, total, [(1, 1, 0.018), (2.41, 0.3, 0.008)])
        grit = 0.06
    else:
        x = pat(140 * p, 98 * p, 0.07, total, attack=0.004)
        x += 0.22 * partials(420 * p, total, [(1, 1, 0.03)], attack=0.004)
        grit = 0.0
    if grit:
        x += grit * noise(n, rng, 300, 1800) * env(total, 0.001, 0.012)
    return finish(room(x, 0.12, 0.35, seed=v), -24)


def foot(v):
    """A rubber shoe on rock: a low soft thud and a short, quiet scuff."""
    rng = np.random.default_rng(200 + v)
    p = 1 + (v - 2.5) * 0.05
    total = 0.3
    n = samples(total)
    x = 0.9 * pat(115 * p, 78 * p, 0.045, total, attack=0.003)
    x += 0.16 * noise(n, rng, 150, 900) * env(total, 0.008, 0.03)
    return finish(room(x, 0.1, 0.3, seed=v), -29)


def chalk(v):
    """A dip in the chalk bag: a soft powdery puff."""
    rng = np.random.default_rng(300 + v)
    total = 0.45
    n = samples(total)
    x = noise(n, rng, 300, 1300) * env(total, 0.03, 0.09)
    x += 0.35 * pat(210, 170, 0.025, total)
    return finish(x, -34)


def slip(v):
    """A hand slips: two soft notes going down, and a light scrape."""
    rng = np.random.default_rng(400 + v)
    total = 0.9
    n = samples(total)
    hi, lo = (69, 66) if v == 1 else (71, 67)  # A4 to F#4, B4 to G4
    x = np.zeros(n)
    place(x, mallet(hi, 0.8, 0.6, 0.22), 0)
    place(x, mallet(lo, 0.7, 0.6, 0.28), samples(0.13))
    scrape = noise(n, rng, 450, 1400) * env(total, 0.01, 0.12, 0.25, 0.05)
    x += 0.22 * scrape
    return finish(room(x, 0.2, 0.6, seed=v), -25)


def fall():
    """Falling: a soft whoosh of air and a low falling tone."""
    rng = np.random.default_rng(500)
    total = 1.0
    n = samples(total)
    t = np.arange(n) / SR
    # air: crossfade from a brighter to a darker band as the climber drops
    bright = noise(n, rng, 280, 1100)
    dark = noise(n, rng, 110, 450)
    u = np.clip(t / 0.8, 0, 1)
    air = (bright * (1 - u) + dark * u) * env(total, 0.12, 0.5)
    tone = 0.5 * osc(glide(330, 150, n, 1.5), n) * env(total, 0.02, 0.35)
    return finish(room(air * 0.6 + tone, 0.15, 0.6, seed=5), -25)


def land(v):
    """Landing on the crash pad: a deep soft thump, no rattle."""
    rng = np.random.default_rng(600 + v)
    total = 0.6
    n = samples(total)
    p = 1 + (v - 1.5) * 0.06
    x = pat(88 * p, 50 * p, 0.12, total, attack=0.003)
    x += 0.4 * noise(n, rng, 40, 300) * env(total, 0.004, 0.05)
    x += 0.06 * noise(n, rng, 350, 1200) * env(total, 0.01, 0.06)
    return finish(x, -22)


def jump(v):
    """A jump: a light rising breath of air and a small rising tone."""
    rng = np.random.default_rng(700 + v)
    total = 0.45
    n = samples(total)
    t = np.arange(n) / SR
    low = noise(n, rng, 220, 650)
    high = noise(n, rng, 500, 1300)
    u = np.clip(t / 0.25, 0, 1)
    air = (low * (1 - u) + high * u) * env(total, 0.03, 0.12)
    tone = osc(glide(300 * (1 + 0.04 * v), 520, n, 0.7), n) * env(total, 0.01, 0.08)
    return finish(room(0.6 * air + 0.5 * tone, 0.12, 0.4, seed=v), -27)


def catch(v):
    """Catching a hold after a jump: a firm pat and a small bright note."""
    rng = np.random.default_rng(800 + v)
    total = 0.9
    n = samples(total)
    x = pat(190, 128, 0.06, total)
    x += 0.3 * partials(600, total, [(1, 1, 0.03), (2.47, 0.3, 0.012)])
    x += 0.06 * noise(n, rng, 300, 1800) * env(total, 0.001, 0.012)
    place(x, mallet(74 if v == 1 else 76, 0.28, 0.7, 0.3), samples(0.02))
    return finish(room(x, 0.15, 0.5, seed=v), -22)


def save():
    """The lamp lights up: two warm notes rising (A5, D6)."""
    total = 2.6
    x = np.zeros(samples(total))
    place(x, bell(81, 0.9, 2.2, 1.0), 0)
    place(x, bell(86, 0.8, 2.3, 1.2), samples(0.14))
    return finish(room(x, 0.3, 1.2, seed=9, bright=6000), -22)


def top():
    """At the top: a gentle rising arpeggio over a soft D major chord."""
    total = 3.6
    n = samples(total)
    x = np.zeros(n)
    for k, m in enumerate([74, 78, 81, 86, 90]):
        place(x, kalimba(m, 0.9 - k * 0.08, 2.2), samples(k * 0.12))
    chord = np.zeros(n)
    for m in [62, 66, 69, 74]:
        chord += partials(hz(m), total, [(1, 1, 3.0), (2, 0.2, 1.2)], attack=0.5, length=2.4, release=0.6)
    x += 0.18 * chord
    return finish(room(x, 0.3, 1.4, seed=11, bright=6000), -21)


def best():
    """A new best height: a small sparkle (E6, A6)."""
    total = 1.8
    x = np.zeros(samples(total))
    place(x, bell(88, 0.8, 1.6, 0.7), 0)
    place(x, bell(93, 0.6, 1.6, 0.8), samples(0.09))
    return finish(room(x, 0.25, 1.0, seed=12, bright=6500), -23)


def no():
    """You can't go there: two soft, low, muted notes."""
    total = 0.4
    x = np.zeros(samples(total))
    place(x, mallet(55, 0.9, 0.25, 0.05), 0)
    place(x, mallet(52, 0.8, 0.25, 0.06), samples(0.085))
    return finish(x, -27)


def tap(v):
    """A button: a tiny, quiet wooden tick."""
    total = 0.12
    f = 1150 if v == 1 else 1320
    x = partials(f, total, [(1, 1, 0.018), (2.6, 0.15, 0.006)], attack=0.002)
    return finish(x, -31)


def bird(v):
    """A small bird far off: a few short, sweet chirps."""
    rng = np.random.default_rng(900 + v)
    calls = {1: [(2600, 3300, 0.07), (2700, 3400, 0.07), (3200, 2600, 0.09)],
             2: [(3000, 3600, 0.05), (3000, 3600, 0.05), (3000, 3600, 0.05), (3400, 2800, 0.1)],
             3: [(2400, 3100, 0.1), (3300, 2500, 0.12)],
             4: [(2800, 3500, 0.06), (3500, 2900, 0.06), (2900, 3700, 0.08)]}[v]
    total = 1.0
    x = np.zeros(samples(total))
    at = 0.0
    for f0, f1, d in calls:
        n = samples(d)
        f = glide(f0, f1, n, 1.2) * (1 + 0.012 * np.sin(2 * np.pi * 38 * np.arange(n) / SR))
        chirp = osc(f, n) * np.hanning(n) ** 1.5
        chirp += 0.12 * osc(f * 2, n) * np.hanning(n) ** 2
        place(x, chirp, samples(at))
        at += d + rng.uniform(0.05, 0.11)
    return finish(room(x, 0.25, 0.9, seed=20 + v, bright=7000), -31)


def breath(v):
    """A tired breath out: soft and low."""
    rng = np.random.default_rng(1000 + v)
    total = 0.8
    n = samples(total)
    x = noise(n, rng, 200, 850)
    x *= env(total, 0.16, 0.0, 0.35, 0.12)
    return finish(x, -34)


def wind():
    """A 16 s loop of soft, low wind with slow gusts. Everything wraps, so it
    loops without a seam; the gusts are lowest at the loop point."""
    rng = np.random.default_rng(1100)
    n = samples(16.0)
    t = np.arange(n) / SR
    low = shape(rng.standard_normal(n), 60, 420, 2)
    mid = shape(rng.standard_normal(n), 250, 900, 2)
    low /= np.sqrt((low ** 2).mean())
    mid /= np.sqrt((mid ** 2).mean())
    gust = 0.55 - 0.25 * np.cos(2 * np.pi * t / 16) + 0.12 * np.sin(2 * np.pi * 3 * t / 16) + 0.08 * np.sin(2 * np.pi * 5 * t / 16 + 1)
    swell = 0.5 - 0.5 * np.cos(2 * np.pi * 2 * t / 16 + 0.6)
    x = low * gust + 0.35 * mid * gust * swell
    x = shape(x, None, 700, 3)
    x *= 10 ** (-26 / 20) / np.sqrt((x ** 2).mean())
    return x


# ---------------------------------------------------------------- music

BPM = 66
BEAT = 60 / BPM
BAR = 4 * BEAT

# (bass note, voicing) per bar, D major. Three sections of eight bars.
CHORDS = [
    (38, [54, 57, 61, 64]), (38, [54, 57, 61, 64]), (35, [54, 57, 62, 64]), (35, [54, 57, 62, 64]),   # Dmaj9  Bm11
    (43, [54, 57, 59, 62]), (43, [54, 57, 59, 62]), (45, [52, 57, 59, 64]), (45, [54, 57, 61, 64]),   # Gmaj9  Asus2 A6
    (40, [54, 55, 59, 62]), (42, [52, 57, 61, 64]), (43, [54, 59, 62, 66]), (45, [54, 59, 61, 64]),   # Em9 F#m7 Gmaj7 A6/9
    (35, [54, 57, 61, 62]), (43, [54, 57, 59, 62]), (40, [54, 55, 59, 62]), (45, [57, 62, 64, 69]),   # Bm9 Gmaj9 Em9 Asus4
    (38, [54, 57, 61, 64]), (35, [54, 57, 62, 64]), (43, [54, 57, 59, 62]), (43, [55, 58, 62, 64]),   # Dmaj9 Bm11 Gmaj9 Gm6
    (38, [54, 57, 61, 64]), (35, [54, 57, 62, 64]), (43, [54, 57, 59, 62]), (45, [52, 57, 59, 64]),   # Dmaj9 Bm11 Gmaj9 Asus2
]
SCALE = [69, 71, 74, 76, 78, 81, 83, 86]  # D major pentatonic, A4 to D6


def pan(x, p):
    """Equal-power pan of a mono signal; p from -1 (left) to 1 (right)."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)])


def music():
    rng = np.random.default_rng(66)
    bars = len(CHORDS)
    length = samples(bars * BAR)
    tail = samples(6.0)
    keys = np.zeros((2, length + tail))
    pads = np.zeros((2, length + tail))
    bass = np.zeros(length + tail)
    melody = np.zeros((2, length + tail))

    for b, (root, voicing) in enumerate(CHORDS):
        at = b * BAR
        # electric piano: the chord on beat one, gently spread, and its top
        # two notes an octave up, softly, for a little shimmer
        for k, m in enumerate(voicing + [m + 12 for m in voicing[2:]]):
            vel = (0.55 if k < 4 else 0.25) + rng.uniform(-0.06, 0.06) - k % 4 * 0.03
            note = ep(m, BAR + 2.5, BAR * 0.92, vel, rng)
            start = samples(at + k * rng.uniform(0.012, 0.022))
            for c, g in enumerate((0.95, 0.85)):  # a little to the left
                place(keys[c], g * note, start)
        # a soft answer of the two top notes on some bars
        if b % 2 == 1 or b % 8 == 6:
            for k, m in enumerate(voicing[2:]):
                note = ep(m + (12 if b % 4 == 3 else 0), BEAT * 2.5, BEAT * 1.4, 0.26, rng)
                for c in range(2):
                    place(keys[c], note, samples(at + 2.5 * BEAT + k * 0.02))
        # pad: the voicing an octave up, slowly breathing in
        for k, m in enumerate(voicing):
            for c, det in enumerate((-0.0028, 0.0028)):
                n = samples(BAR + 2.2)
                f = hz(m + 12) * (1 + det)
                tone = osc(f, n, rng.uniform(0, 6.28)) + 0.3 * osc(2 * f, n) + 0.08 * osc(3 * f, n)
                e = np.ones(n)
                a = samples(1.4)
                e[:a] = ramp(a)
                r = samples(BAR)
                e[r:] = np.exp(-np.arange(n - r) / SR / 0.7)
                place(pads[c], 0.07 * tone * e, samples(at))
        # bass: the root on beat one (silent in the first bar), a soft step toward the next chord
        if b > 0:
            nb = samples(BAR)
            f = hz(root)
            tone = osc(f, nb) + 0.16 * osc(2 * f, nb) + 0.04 * osc(3 * f, nb)
            place(bass, 0.42 * tone * env(BAR, 0.025, 1.8, BEAT * 2.6, 0.18), samples(at))
            if b % 4 == 3:
                nxt = CHORDS[(b + 1) % bars][0]
                step = nxt + 7 if nxt + 7 <= 47 else nxt - 5
                nn = samples(BEAT)
                f2 = hz(step)
                tone = osc(f2, nn) + 0.16 * osc(2 * f2, nn)
                place(bass, 0.22 * tone * env(BEAT, 0.02, 0.6, BEAT * 0.8, 0.1), samples(at + 3 * BEAT))
        # kalimba: a short phrase on some bars, mostly chord tones
        if b % 8 in (1, 3, 5) or (b >= 16 and b % 8 == 6):
            if rng.random() < 0.8:
                tones = {(m % 12) for m in voicing} | {root % 12}
                count = rng.integers(3, 6)
                slots = sorted(rng.choice([0, 1, 2, 3, 4, 5, 6], size=count, replace=False))
                i = rng.integers(2, 6)
                for s in slots:
                    i = int(np.clip(i + rng.integers(-2, 3), 0, len(SCALE) - 1))
                    m = SCALE[i]
                    if m % 12 not in tones and rng.random() < 0.6:
                        i = max(0, i - 1)
                        m = SCALE[i]
                    swing = 0.06 if s % 2 else 0.0
                    when = at + s * BEAT / 2 + swing * BEAT
                    note = kalimba(m, rng.uniform(0.22, 0.32))
                    st = pan(note, rng.uniform(-0.4, 0.4))
                    for c in range(2):
                        place(melody[c], st[c], samples(when))

    # stereo tremolo on the keys, like an electric piano amp
    t = np.arange(length + tail) / SR
    trem = 0.09 * np.sin(2 * np.pi * 4.3 * t)
    keys[0] *= 1 + trem
    keys[1] *= 1 - trem
    mix = keys + pads + 1.6 * melody + np.stack([bass, bass])
    # wrap the tails of the last bars around to the start: the loop is seamless
    mix[:, :tail] += mix[:, length:]
    mix = mix[:, :length]
    # a warm room around everything (circular, so it wraps too)
    irs = impulse(3.2, 2.3, np.random.default_rng(3), bright=5000)
    wet = np.stack([convolve(mix[c], irs[c], circular=True) for c in range(2)])
    mix = mix + 0.3 * wet * np.sqrt((mix ** 2).mean()) / (np.sqrt((wet ** 2).mean()) + 1e-12)
    mix = np.stack([shape(mix[c], 35, 9000, 2) for c in range(2)])
    # a soft dip where the loop restarts, so a player's gap is never heard
    dip = np.ones(length)
    a, z = samples(0.9), samples(0.4)
    dip[-a:] = 0.2 + 0.8 * ramp(a)[::-1]
    dip[:z] = 0.2 + 0.8 * ramp(z)
    mix *= dip
    mix *= 10 ** (-20 / 20) / np.sqrt((mix ** 2).mean())
    peak = np.max(np.abs(mix))
    if peak > 10 ** (-3 / 20):
        mix *= 10 ** (-3 / 20) / peak
    return mix


# ---------------------------------------------------------------- all files

def jobs():
    for kind in ('jug', 'crimp', 'sloper'):
        for v in (1, 2, 3):
            yield f'grab_{kind}_{v}', lambda kind=kind, v=v: grab(kind, v)
    for v in (1, 2, 3, 4):
        yield f'foot_{v}', lambda v=v: foot(v)
    for v in (1, 2):
        yield f'chalk_{v}', lambda v=v: chalk(v)
        yield f'slip_{v}', lambda v=v: slip(v)
        yield f'land_{v}', lambda v=v: land(v)
        yield f'jump_{v}', lambda v=v: jump(v)
        yield f'catch_{v}', lambda v=v: catch(v)
        yield f'tap_{v}', lambda v=v: tap(v)
        yield f'breath_{v}', lambda v=v: breath(v)
    for v in (1, 2, 3, 4):
        yield f'bird_{v}', lambda v=v: bird(v)
    yield 'fall_1', fall
    yield 'save_1', save
    yield 'top_1', top
    yield 'best_1', best
    yield 'no_1', no
    yield 'wind', wind
    yield 'music', music


if __name__ == '__main__':
    only = sys.argv[1:]
    for name, make in jobs():
        if only and not any(name.startswith(o) for o in only):
            continue
        write(name, make())
