"""Renders the game's music and sound effects to files.

The sounds are made by the synth in web_prototype/topout.html (Web Audio).
This script runs that same code in headless Chromium with an offline audio
context and saves the result, so the Flutter app plays exactly the same sounds.

Needs: pip install playwright numpy; playwright install chromium; ffmpeg on PATH.
Run:   python tool/render_audio.py            (sound effects, wind)
       python tool/render_audio.py music      (the music loop, takes a few minutes)
"""
import base64, os, pathlib, subprocess, sys, tempfile
import numpy as np
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets' / 'audio'
SR = 44100
GAIN = 2.0   # same lift for every file, so the mix between music and sounds stays as designed

PRE = """
window.__fake = 0;
window.AudioContext = function () {
  const ac = new OfflineAudioContext(2, Math.ceil(44100 * window.__len), 44100);
  Object.defineProperty(ac, 'state', { get: () => 'running' });
  Object.defineProperty(ac, 'currentTime', { get: () => window.__fake });
  ac.resume = () => Promise.resolve(); ac.suspend = () => Promise.resolve();
  window.__ac = ac; return ac;
};
"""

RENDER = """async ([job, len]) => {
  window.__len = len;
  const AU = window.__topout.AU; AU.init(); clearInterval(AU.timer);
  const ac = window.__ac;
  window.__fake = 0.02;
  if (job.music) {
    AU.setSfx(false);
    const s16 = AU.s16; let st = job.from;
    for (let t = 0; st < job.to; t += s16) { window.__fake = t; AU.playStep(st++, t); }
  } else if (job.wind) {
    AU.setMusic(false); AU.windG.gain.value = job.wind;
  } else {
    AU.setMusic(false);
    if (job.name === 'bird') AU.bird(0.02);
    else if (job.name === 'breath') { AU.nextBreath = 0; AU.breath(1); }
    else AU.play(job.name, { kind: job.kind, pan: 0 });
  }
  window.__fake = 0;
  const buf = await ac.startRendering();
  const L = buf.getChannelData(0), R = buf.getChannelData(1), n = L.length, f = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) { f[2 * i] = L[i]; f[2 * i + 1] = R[i]; }
  let bin = ''; const u8 = new Uint8Array(f.buffer);
  for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
  return btoa(bin);
}"""

SFX = [  # file name, sound, hold kind, variants, seconds
    ('grab_jug', 'grab', 'jug', 3, 1.6), ('grab_crimp', 'grab', 'crimp', 3, 1.6), ('grab_sloper', 'grab', 'sloper', 3, 1.6),
    ('foot', 'foot', None, 4, 1.4), ('chalk', 'chalk', None, 2, 1.8), ('slip', 'slip', None, 2, 2.0),
    ('fall', 'fall', None, 1, 2.4), ('land', 'land', None, 2, 2.4), ('jump', 'jump', None, 2, 2.0),
    ('catch', 'catch', None, 2, 2.0), ('save', 'save', None, 1, 3.0), ('top', 'top', None, 1, 4.6),
    ('best', 'best', None, 1, 2.6), ('no', 'no', None, 1, 1.2), ('tap', 'tap', None, 2, 0.8),
    ('bird', 'bird', None, 4, 1.8), ('breath', 'breath', None, 2, 1.6),
]


def render(browser, job, seconds):
    page = browser.new_page()
    page.add_init_script(PRE)
    page.goto((ROOT / 'web_prototype' / 'topout.html').as_uri() + '#debug')
    page.wait_for_timeout(300)
    raw = base64.b64decode(page.evaluate(RENDER, [job, seconds]))
    page.close()
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def trim(a, floor=2e-4, fade=0.03):
    loud = np.where(np.abs(a).max(axis=1) > floor)[0]
    end = min(len(a), (loud[-1] if len(loud) else 0) + int(0.05 * SR))
    a = a[:max(end, int(0.1 * SR))]
    n = min(len(a), int(fade * SR))
    a[-n:] *= np.linspace(1, 0, n)[:, None]
    return a


def save(a, name, bitrate='160k'):
    with tempfile.NamedTemporaryFile(suffix='.f32', delete=False) as tmp:
        tmp.write(np.clip(a * GAIN, -1, 1).astype('<f4').tobytes())
    out = OUT / f'{name}.mp3'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', tmp.name,
                    '-codec:a', 'libmp3lame', '-b:a', bitrate, str(out)], check=True)
    os.unlink(tmp.name)
    print(f'{out.name:22s} {len(a) / SR:6.2f} s  peak {np.abs(a).max() * GAIN:.3f}')


def loop(a, cycle):
    """Fold the tail after one cycle back onto the start, so the file loops without a seam."""
    n = int(round(cycle * SR))
    body, tail = a[:n].copy(), a[n:]
    body[:len(tail)] += tail
    return body


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    what = sys.argv[1] if len(sys.argv) > 1 else 'sfx'
    with sync_playwright() as p:
        browser = p.chromium.launch()
        if what == 'music':
            s16 = 60 / 72 / 4
            cycle = 512 * s16           # 32 bars
            a = render(browser, {'music': True, 'from': 512, 'to': 1024}, cycle + 5)
            save(loop(a, cycle), 'music', '128k')
        else:
            for name, sound, kind, n, secs in SFX:
                for v in range(1, n + 1):
                    job = {'name': sound, 'kind': kind}
                    save(trim(render(browser, job, secs)), f'{name}_{v}')
            a = render(browser, {'wind': 0.25}, 26)
            save(loop(a[int(1.5 * SR):], 22), 'wind', '96k')
        browser.close()


if __name__ == '__main__':
    main()
