#!/usr/bin/env python3
"""Makes the game's sounds (assets/audio/*.mp3).

The sound effects are cut and mixed from CC0 recordings (Kenney and
OpenGameArt packs, see docs/SOUND_CREDITS.md), fetched once into
build/audio-sources. The music, the wind and the birds are synthesized here
with numpy. Everything is encoded with ffmpeg.

    python tool/make_audio.py              all files
    python tool/make_audio.py grab foot    only the files whose names start so

Needs numpy, ffmpeg (with libmp3lame) on PATH, and the internet the first time.
"""
import pathlib
import subprocess
import sys
import urllib.parse
import urllib.request

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


def finish(x, loud_db, floor_db=-70.0, fade=0.02, peak_db=-1.0):
    """Sets the loudness of the loud part, keeps the peak under `peak_db`
    (a sharp click sounds louder than its loudness says), cuts the silent
    tail and fades the end to true zero."""
    win = samples(0.03)
    frames = x[:len(x) // win * win].reshape(-1, win)
    rms = np.sqrt((frames ** 2).mean(1))
    loud = rms[rms > rms.max() * 0.25]
    level = np.sqrt((loud ** 2).mean())
    x = x * (10 ** (loud_db / 20) / level)
    peak = np.max(np.abs(x))
    if peak > 10 ** (peak_db / 20):
        x *= 10 ** (peak_db / 20) / peak
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


# ---------------------------------------------------------------- stock recordings

# The sound effects are cut from CC0 (public domain) recordings: Kenney's
# packs and CC0 packs from OpenGameArt, as mirrored by the Open Game SFX
# Index. They are fetched once, at a fixed commit, into build/audio-sources.
# docs/SOUND_CREDITS.md lists the recordings each file is made of.
INDEX = 'https://raw.githubusercontent.com/Legerdo/open-game-sfx-index/d463e4d24ea2c18a75b27de8da1532642d80483c/audio/'
CACHE = ROOT / 'build' / 'audio-sources'

# folder in the index: (pack, author, page)
PACKS = {
    'impact-sounds': ('Impact Sounds', 'Kenney', 'https://kenney.nl/assets/impact-sounds'),
    'rpg-audio': ('RPG Audio', 'Kenney', 'https://kenney.nl/assets/rpg-audio'),
    'interface-sounds': ('Interface Sounds', 'Kenney', 'https://kenney.nl/assets/interface-sounds'),
    'ui-audio': ('UI Audio', 'Kenney', 'https://kenney.nl/assets/ui-audio'),
    'music-jingles': ('Music Jingles', 'Kenney', 'https://kenney.nl/assets/music-jingles'),
    'oga-rpg-pack': ('RPG Sound Pack', 'artisticdude', 'https://opengameart.org/content/rpg-sound-pack'),
    'oga-battle': ('Battle Sound Effects', 'Ogrebane', 'https://opengameart.org/content/battle-sound-effects'),
    'oga-rubberduck-breaking-75': ('75 CC0 breaking, falling and hit SFX', 'rubberduck', 'https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx'),
    'oga-rubberduck-metal-wood-100': ('100 CC0 metal and wood SFX', 'rubberduck', 'https://opengameart.org/content/100-cc0-metal-and-wood-sfx'),
    'oga-rubberduck-foley-100-v2': ('100 CC0 SFX #2', 'rubberduck', 'https://opengameart.org/content/100-cc0-sfx-2'),
    'oga-rubberduck-100-foley': ('100 CC0 SFX', 'rubberduck', 'https://opengameart.org/content/100-cc0-sfx'),
    'oga-rubberduck-creatures-80-v2': ('80 CC0 creature SFX #2', 'rubberduck', 'https://opengameart.org/content/80-cc0-creture-sfx-2'),
}

# which recordings each file uses, for docs/SOUND_CREDITS.md
USED = {}
_making = ['']


def stock(path, start=0.0, length=None, semis=0.0):
    """A recording from the index (its path under audio/), mono, from `start`
    seconds and at most `length` long, `semis` semitones higher (resampled,
    so a higher sound is also a little shorter)."""
    USED.setdefault(_making[0], set()).add(path)
    f = CACHE / path
    if not f.exists():
        f.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(INDEX + urllib.parse.quote(path), timeout=60) as r:
            f.write_bytes(r.read())
    cmd = ['ffmpeg', '-v', 'error', '-i', str(f), '-ac', '1', '-ar', str(SR), '-f', 'f64le', '-']
    x = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float64)
    a = samples(start)
    x = (x[a:] if length is None else x[a:a + samples(length)]).copy()
    if semis:
        x = np.interp(np.arange(0, len(x) - 1, 2 ** (semis / 12)), np.arange(len(x)), x)
    # neither a cut nor the end of a recording (they stop hard) ever clicks
    if start:
        k = min(samples(0.004), len(x))
        x[:k] *= ramp(k)
    k = min(samples(0.012), len(x))
    x[len(x) - k:] *= ramp(k)[::-1]
    return x


def band(x, lo=None, hi=None):
    """[shape] for a one-shot sound: padded first, so the filter's ringing
    cannot wrap from the start of the sound around to its end."""
    pad = samples(0.06)
    return shape(np.concatenate([np.zeros(pad), x, np.zeros(pad)]), lo, hi)[pad:pad + len(x)]


def mix(total, *parts):
    """Lays (sound, at seconds, gain in dB) parts into `total` seconds."""
    x = np.zeros(samples(total))
    for s, at, db in parts:
        place(x, s * 10 ** (db / 20), samples(at))
    return x


IMPACT, RPG, UI = 'impact-sounds/', 'rpg-audio/', 'interface-sounds/'
JINGLE = 'music-jingles/jingles_'
CLOTH = 'oga-rpg-pack/RPG Sound Pack/inventory/cloth.wav'
CLOTH_HEAVY = 'oga-rpg-pack/RPG Sound Pack/inventory/cloth-heavy.wav'
KEYS = 'oga-rubberduck-metal-wood-100/keys_0'


# ---------------------------------------------------------------- sound effects

def grab(kind, v):
    """A hand closing on a hold: a slap of skin on a jug, fingertips knocking
    onto a small edge (crimp), a palm smearing onto a sloper. Each has a
    soft, low thump under it for the weight of the body."""
    weight = band(stock(f'{IMPACT}impactSoft_medium_00{v}.ogg'), 40, 900)
    if kind == 'jug':
        hand = band(stock(f'{IMPACT}impactPunch_medium_00{(0, 2, 4)[v - 1]}.ogg', length=0.3), 90, 2400)
        x = mix(0.34, (hand, 0, 0), (weight, 0, -5))
    elif kind == 'crimp':
        tip = band(stock('oga-rubberduck-breaking-75/bfh1_rock_hit_01.ogg', semis=(0, 1.5, -1.5)[v - 1]), 300, 5000)
        knock = band(stock(f'{IMPACT}impactGeneric_light_00{v}.ogg'), 120, 3000)
        x = mix(0.3, (tip, 0, 0), (knock, 0.004, -6), (weight, 0, -12))
    else:
        palm = band(stock(RPG + ('handleSmallLeather.ogg', 'handleSmallLeather2.ogg', 'handleSmallLeather.ogg')[v - 1],
                           semis=(0, 0, -2)[v - 1]), 150, 3800)
        x = mix(0.36, (palm, 0, 0), (weight, 0.01, -2))
    return finish(room(x, 0.1, 0.35, seed=v), -24, peak_db=-14)


def foot(v):
    """A climbing shoe set down on rock."""
    x = band(stock(f'{IMPACT}footstep_concrete_00{v - 1}.ogg'), 70, 3500)
    return finish(room(x, 0.08, 0.3, seed=v), -29, peak_db=-18)


def snow(v):
    """A hand or a foot crunching into snow on a hold."""
    x = band(stock(f'{IMPACT}footstep_snow_00{v - 1}.ogg'), 120, 9000)
    return finish(room(x, 0.08, 0.3, seed=40 + v), -30, peak_db=-18)


def chalk(v):
    """Fingers dipping into the chalk bag."""
    x = band(stock(RPG + ('cloth2.ogg', 'cloth4.ogg')[v - 1]), 300, 6500)
    return finish(x, -34, peak_db=-21)


def slip(v):
    """A hand or a foot skating off: a scuff, and grit trickling down."""
    scuff = band(stock(RPG + ('cloth1.ogg', 'cloth3.ogg')[v - 1]), 200, 6000)
    grit = band(stock(f'oga-rubberduck-breaking-75/bfh1_rock_falling_0{(8, 7)[v - 1]}.ogg'), 400, 9000)
    bump = band(stock(f'{IMPACT}impactSoft_medium_00{v + 2}.ogg'), 40, 700)
    x = mix(0.95, (scuff, 0, 0), (grit, 0.12, -7), (bump, 0, -9))
    return finish(room(x, 0.2, 0.6, seed=v), -25, peak_db=-13)


def fall():
    """Off the wall: a rush of air and a flap of clothes."""
    air = band(stock('oga-rubberduck-foley-100-v2/sfx100v2_air_02.ogg'), 150, 1800)
    swish = band(stock('oga-battle/battle_sound_effects/swish_3.wav', semis=-3), 100, 4000)
    flap = band(stock(CLOTH_HEAVY), 150, 6000)
    x = mix(1.3, (air, 0, 0), (swish, 0, -2), (flap, 0.06, -10))
    return finish(room(x, 0.15, 0.6, seed=5), -25)


def land(v):
    """Onto the crash pad: a heavy, soft thud, the clothes, the gear on the harness."""
    thud = band(stock(f'{IMPACT}impactSoft_heavy_00{(0, 2)[v - 1]}.ogg'), 30, 1500)
    body = band(stock(RPG + 'dropLeather.ogg'), 120, 6000)
    gear = band(stock(f'{KEYS}{(4, 1)[v - 1]}.ogg'), 800, 9000)
    x = mix(0.6, (thud, 0, 0), (body, 0.008, -7), (gear, 0.03, -20))
    return finish(x, -22)


def jump(v):
    """A jump for a hold: a quick whoosh, the clothes, the gear jingling."""
    whoosh = band(stock('oga-rpg-pack/RPG Sound Pack/battle/' + ('swing.wav', 'swing2.wav')[v - 1]), 120, 6000)
    cloth = band(stock(RPG + 'cloth2.ogg'), 200, 7000)
    gear = band(stock(f'{KEYS}{(1, 4)[v - 1]}.ogg'), 800, 9000)
    x = mix(0.55, (whoosh, 0, 0), (cloth, 0.02, -9), (gear, 0.05, -19))
    return finish(room(x, 0.1, 0.4, seed=v), -27)


def catch(v):
    """Catching the hold at the end of a jump: a hard slap, the body swinging in."""
    hand = band(stock(f'{IMPACT}impactPunch_heavy_00{(1, 3)[v - 1]}.ogg', length=0.45), 60, 2800)
    swing = band(stock(CLOTH_HEAVY), 150, 6000)
    gear = band(stock(f'{KEYS}4.ogg', semis=(0, 1)[v - 1]), 800, 9000)
    x = mix(0.8, (hand, 0, 0), (swing, 0.03, -9), (gear, 0.04, -18))
    return finish(room(x, 0.12, 0.5, seed=v), -22)


def snatch(v):
    """A falling hand slams onto a hold: a heavy slap and a jolt through the
    body and the gear."""
    hand = band(stock(f'{IMPACT}impactPunch_heavy_00{(0, 4)[v - 1]}.ogg', length=0.5), 50, 3200)
    jolt = band(stock(f'{IMPACT}impactSoft_heavy_00{(1, 3)[v - 1]}.ogg'), 30, 900)
    gear = band(stock(f'{KEYS}1.ogg', semis=(0, -1)[v - 1]), 700, 9000)
    cloth = band(stock(CLOTH), 200, 6500)
    x = mix(0.8, (hand, 0, 0), (jolt, 0, -4), (gear, 0.035, -14), (cloth, 0.02, -10))
    return finish(room(x, 0.12, 0.45, seed=30 + v), -21)


def save():
    """Clipping in at a ledge: the carabiner's gate, then two rising notes."""
    gate = band(stock(RPG + 'metalClick.ogg'), 400, 12000)
    ding = stock(JINGLE + 'STEEL08.ogg')
    x = mix(1.6, (gate, 0, 0), (ding, 0.3, -6))
    return finish(room(x, 0.25, 1.2, seed=9, bright=6000), -22)


def top():
    """The top: pizzicato, steel drum and a low orchestral hit climbing
    D, E, F sharp, G together."""
    x = mix(1.6, (stock(JINGLE + 'PIZZI10.ogg'), 0, 0), (stock(JINGLE + 'STEEL10.ogg'), 0, -4),
            (stock(JINGLE + 'HIT16.ogg'), 0, -9))
    return finish(room(x, 0.3, 1.4, seed=11, bright=6000), -21)


def best():
    """A new best: a playful pizzicato turn, moved into D."""
    x = stock(JINGLE + 'PIZZI15.ogg', semis=2)
    return finish(room(x, 0.25, 1.0, seed=12, bright=6500), -23)


def no():
    """A move that cannot be made: a dull, short knock on wood."""
    knock = band(stock(f'{IMPACT}impactWood_light_000.ogg'), 80, 3000)
    low = band(stock(UI + 'bong_001.ogg'), 60, 1500)
    return finish(mix(0.3, (knock, 0, 0), (low, 0, -10)), -27, peak_db=-17)


def tap(v):
    """A button: a soft click."""
    x = band(stock('ui-audio/' + ('click1.ogg', 'click3.ogg')[v - 1]), 200, 6000)
    return finish(x, -33, peak_db=-21)


def page(v):
    """Turning a page of the field book."""
    x = band(stock(RPG + ('bookFlip1.ogg', 'bookFlip2.ogg')[v - 1], start=(0.25, 0)[v - 1], length=0.45), 250, 8000)
    return finish(x, -31, peak_db=-19)


def clip(v):
    """Roping up: a carabiner snapping shut."""
    x = band(stock(RPG + ('metalLatch.ogg', 'metalClick.ogg')[v - 1], length=(None, 0.2)[v - 1]), 400, 12000)
    return finish(room(x, 0.12, 0.4, seed=50 + v), -27, peak_db=-15)


def breath(v):
    """A tired breath out."""
    x = band(stock('oga-rubberduck-creatures-80-v2/breath_02.ogg', semis=(0, -2)[v - 1]), 150, 2600)
    return finish(x, -34)


def heart():
    """Time slows down in a fall: two soft, low heartbeats."""
    lub = band(stock(f'{IMPACT}impactSoft_heavy_000.ogg'), 25, 260)
    dub = band(stock(f'{IMPACT}impactSoft_heavy_003.ogg', semis=1), 25, 260)
    return finish(mix(1.0, (lub, 0, 0), (dub, 0.24, -3)), -26)


def emote_cheer():
    """Cheer: a sax climbing D, E, F sharp, G."""
    return finish(room(stock(JINGLE + 'SAX10.ogg'), 0.25, 1.0, seed=21, bright=6500), -25)


def emote_taunt():
    """Taunt: a cheeky boing."""
    x = mix(0.6, (band(stock('oga-rubberduck-100-foley/spring_03.ogg'), 120, 9000), 0, 0),
            (stock(UI + 'pluck_002.ogg'), 0, -8))
    return finish(room(x, 0.2, 0.8, seed=22, bright=6000), -26, peak_db=-13)


def emote_aura():
    """Aura: a dreamy pizzicato run up a whole-tone scale from D, with a shimmer."""
    run = stock(JINGLE + 'PIZZI02.ogg', semis=2)
    shimmer = band(stock('oga-rpg-pack/RPG Sound Pack/battle/magic1.wav'), 1500, 12000)
    x = mix(1.6, (run, 0, 0), (shimmer, 0.05, -14))
    return finish(room(x, 0.35, 1.6, seed=23, bright=5500), -27)


def credits():
    """docs/SOUND_CREDITS.md: the recordings in each file."""
    lines = ['# Sound credits', '',
             'The sound effects are cut and mixed by `tool/make_audio.py` from CC0 (public',
             'domain) recordings: no credit is needed, but here it is. The recordings come',
             'from the [Open Game SFX Index](https://github.com/Legerdo/open-game-sfx-index),',
             'which mirrors these packs. The music, the wind and the birds are synthesized',
             'by the same script.', '',
             '| Pack | By | Licence |', '|---|---|---|']
    packs = sorted({p.split('/')[0] for used in USED.values() for p in used})
    for p in packs:
        name, by, page = PACKS[p]
        lines.append(f'| [{name}]({page}) | {by} | CC0 1.0 |')
    lines += ['', '| File | Made from |', '|---|---|']
    for name in sorted(USED):
        if name:
            lines.append(f'| `{name}.mp3` | ' + ', '.join(f'`{p}`' for p in sorted(USED[name])) + ' |')
    (ROOT / 'docs' / 'SOUND_CREDITS.md').write_text('\n'.join(lines) + '\n')


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
    for v in (1, 2, 3):
        yield f'snow_{v}', lambda v=v: snow(v)
    for v in (1, 2):
        yield f'chalk_{v}', lambda v=v: chalk(v)
        yield f'slip_{v}', lambda v=v: slip(v)
        yield f'land_{v}', lambda v=v: land(v)
        yield f'jump_{v}', lambda v=v: jump(v)
        yield f'catch_{v}', lambda v=v: catch(v)
        yield f'tap_{v}', lambda v=v: tap(v)
        yield f'page_{v}', lambda v=v: page(v)
        yield f'clip_{v}', lambda v=v: clip(v)
        yield f'breath_{v}', lambda v=v: breath(v)
    for v in (1, 2, 3, 4):
        yield f'bird_{v}', lambda v=v: bird(v)
    for v in (1, 2):
        yield f'snatch_{v}', lambda v=v: snatch(v)
    yield 'heart_1', heart
    yield 'fall_1', fall
    yield 'save_1', save
    yield 'top_1', top
    yield 'best_1', best
    yield 'no_1', no
    yield 'emote_cheer_1', emote_cheer
    yield 'emote_taunt_1', emote_taunt
    yield 'emote_aura_1', emote_aura
    yield 'wind', wind
    yield 'music', music


if __name__ == '__main__':
    only = sys.argv[1:]
    for name, make in jobs():
        if only and not any(name.startswith(o) for o in only):
            continue
        _making[0] = name
        write(name, make())
    if not only:
        credits()
