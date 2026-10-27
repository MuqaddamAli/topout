
const LIMB_NAMES = ['left hand', 'right hand', 'left foot', 'right foot'];
const IS_HAND = [true, true, false, false];
const SIDE = [-1, 1, -1, 1];
const JOINT = [[-13, 25], [13, 25], [-10, -25], [10, -25]]; // shoulder / hip offsets from torso centre (y up)
const REACH = [66, 66, 80, 80];
const MINR = [16, 16, 24, 24];
const SEG = [[34, 33], [34, 33], [41, 40], [41, 40]];
const SLOW = 0.35;            // grip drain while aiming
const UNITS_PER_M = 100;
const WALL = { l: 0, r: 360, hl: 34, hr: 326 };   // wall band and the x range holds may use
const HOLD = {
  jug:    { hand: 'good', foot: 'good', drain: 2.5, feet: 1,   label: 'big hold' },
  crimp:  { hand: 'weak', foot: 'good', drain: 6.5, feet: 1,   label: 'small edge' },
  sloper: { hand: 'weak', foot: 'weak', drain: 8,   feet: 0.5, label: 'round hold' },
  chip:   { hand: 'no',   foot: 'good', drain: 0,   feet: 1,   label: 'foot step' },
  ledge:  { hand: 'good', foot: 'good', drain: 1.5, feet: 1,   label: 'ledge', rest: true, wide: true },
  ground: { hand: 'no',   foot: 'good', drain: 0,   feet: 1,   label: 'ground', rest: true, wide: true },
  top:    { hand: 'good', foot: 'good', drain: 1.5, feet: 1,   label: 'top', rest: true, wide: true }
};
const MODES = {
  casual: { name: 'Relaxed', drain: 0.6, ledges: true, note: 'Your hands get tired more slowly.' },
  normal: { name: 'Normal', drain: 1, ledges: true, note: 'Rest on a ledge to save your place.' },
  solo:   { name: 'No saves', drain: 1, ledges: false, note: 'If you fall, you start again from the ground.' }
};

function quality(h, i) { return IS_HAND[i] ? HOLD[h.t].hand : HOLD[h.t].foot; }
function attachPoint(h, i, px) {
  if (HOLD[h.t].wide) {
    const mid = (h.x + h.x2) / 2;
    return { x: Math.max(h.x + 6, Math.min(h.x2 - 6, px == null ? mid : px)), y: h.y };
  }
  return { x: h.x + SIDE[i] * 3, y: h.y };
}
function holdDist(h, px, py) {
  if (HOLD[h.t].wide) { const cx = Math.max(h.x, Math.min(h.x2, px)); return Math.hypot(px - cx, py - h.y); }
  return Math.hypot(px - h.x, py - h.y);
}
// Torso solver: gravity pulls the body down (or standing pushes it up) while each attached limb keeps it within reach.
function solve(C0, anchors, iters) {
  let x = C0.x, y = C0.y;
  if (!anchors.length) return { x, y, err: 0 };
  const hang = anchors.some(a => a.i < 2 && (a.w == null || a.w >= 1));
  const bias = hang ? -1.5 : 1.5;
  const n = iters || 40;
  for (let k = 0; k < n + 12; k++) {
    if (k < n) y += bias;
    for (const a of anchors) {
      const w = a.w == null ? 1 : a.w;
      const jx = x + JOINT[a.i][0], jy = y + JOINT[a.i][1];
      const dx = a.x - jx, dy = a.y - jy, L = Math.hypot(dx, dy) || 1e-6;
      if (L > REACH[a.i]) { const c = (L - REACH[a.i]) * 0.6 * w; x += dx / L * c; y += dy / L * c; }
      else if (L < MINR[a.i]) { const c = (MINR[a.i] - L) * 0.6 * w; x -= dx / L * c; y -= dy / L * c; }
    }
  }
  let err = 0;
  for (const a of anchors) {
    if (a.w != null && a.w < 1) continue;
    const L = Math.hypot(a.x - x - JOINT[a.i][0], a.y - y - JOINT[a.i][1]);
    err = Math.max(err, L - REACH[a.i], MINR[a.i] - L);
  }
  return { x, y, err };
}
function supportInfo(limbs, holds) {
  let hands = 0, feet = 0, feetW = 0, rest = 0; const restIds = [];
  for (let i = 0; i < 4; i++) {
    const l = limbs[i]; if (l.h == null) continue;
    const H = HOLD[holds[l.h].t];
    if (IS_HAND[i]) hands++;
    else { feet++; feetW += H.feet; if (H.rest) { rest++; restIds.push(l.h); } }
  }
  const standing = rest === 2;
  return { hands, feet, feetW, standing, restIds, supported: standing || (hands >= 1 && hands + feet >= 2) };
}
function feetMult(fw) { return fw >= 2 ? 0.55 : fw >= 1.5 ? 0.75 : fw >= 1 ? 1 : fw >= 0.5 ? 1.4 : 2; }
function gripRates(limbs, holds, mode) {
  const s = supportInfo(limbs, holds), m = MODES[mode] || MODES.normal, rates = [0, 0];
  for (let i = 0; i < 2; i++) {
    const l = limbs[i];
    if (l.h == null) { rates[i] = 14; continue; }
    if (s.standing) { rates[i] = 12; continue; }
    rates[i] = -HOLD[holds[l.h].t].drain * feetMult(s.feetW) * (s.hands === 1 ? 1.5 : 1) * m.drain;
  }
  return { rates, s };
}
function feasible(limbs, i, pt, C) {
  const anc = [];
  for (let k = 0; k < 4; k++) {
    if (k === i) { anc.push({ i: k, x: pt.x, y: pt.y }); continue; }
    const l = limbs[k]; if (l.h != null) anc.push({ i: k, x: l.x, y: l.y });
  }
  const r = solve(C, anc, 50);
  return r.err < 1.2 ? r : null;
}

// ---- Routes ----
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function pick(arr, rng) { let tot = 0; for (const a of arr) tot += a[1]; let r = rng() * tot; for (const [t, w] of arr) { r -= w; if (r <= 0) return t; } return arr[0][0]; }
function makeRoute(id, name, level, blurb, tutorial) {
  return { id, name, level, blurb, tutorial: !!tutorial, holds: [{ t: 'ground', x: -200, x2: 560, y: 0 }], startHands: [], topY: 0, _grid: new Map(), _ledges: [] };
}
const GRID = 40;
function gridAdd(r, k) {
  const h = r.holds[k]; if (h.x2 != null) return;
  const key = Math.floor(h.x / GRID) + ',' + Math.floor(h.y / GRID);
  let c = r._grid.get(key); if (!c) r._grid.set(key, c = []); c.push(k);
}
function nearHold(r, x, y, d) {   // true if a small hold is closer than d, or (x, y) sits on a ledge
  const gx = Math.floor(x / GRID), gy = Math.floor(y / GRID), n = Math.ceil(d / GRID);
  for (let i = -n; i <= n; i++) for (let j = -n; j <= n; j++) {
    const c = r._grid.get((gx + i) + ',' + (gy + j)); if (!c) continue;
    for (const k of c) { const h = r.holds[k]; if (Math.hypot(h.x - x, h.y - y) < d) return true; }
  }
  return false;
}
function onLedge(r, x, y, mx, below, above) {
  for (const h of r._ledges) if (y > h.y - below && y < h.y + above && x > h.x - mx && x < h.x2 + mx) return true;
  return false;
}
function addHold(r, t, x, y, x2) {
  if (x2 == null) {
    if (nearHold(r, x, y, 18) || onLedge(r, x, y, 10, 16, 16)) return -1;
    r.holds.push({ t, x, y }); gridAdd(r, r.holds.length - 1);
  } else pushLedge(r, { t, x, y, x2 });
  return r.holds.length - 1;
}
function pushLedge(r, h) { r.holds.push(h); if (h.t !== 'ground') r._ledges.push(h); }
// A line that wanders across the wall. Starts in the middle near the ground.
function wander(rng, amp) {
  const a1 = amp * (0.6 + rng() * 0.4), f1 = 0.0032 + rng() * 0.0026, p1 = rng() * 6.283;
  const a2 = amp * (0.15 + rng() * 0.15), f2 = 0.011 + rng() * 0.006, p2 = rng() * 6.283;
  const raw = y => a1 * Math.sin(y * f1 + p1) + a2 * Math.sin(y * f2 + p2);
  const r0 = raw(200);
  return y => {
    const k = Math.max(0, Math.min(1, (y - 200) / 260));
    return Math.max(78, Math.min(282, 180 + (raw(y) - r0) * k));
  };
}
function ladder(r, rng, y0, y1, o) {
  let side = o.startSide || -1, y = y0;
  const sp = o.spread || 34;
  while (y <= y1) {
    const cx = o.cxAt ? o.cxAt(y) : (o.cx || 180);
    const x = Math.max(WALL.hl, Math.min(WALL.hr, cx + side * sp + (rng() - 0.5) * (o.jit || 18)));
    addHold(r, pick(o.types, rng), Math.round(x), Math.round(y));
    if (rng() < (o.feet == null ? 0.7 : o.feet)) addHold(r, o.footType || 'chip', Math.round(cx - side * 14 + (rng() - 0.5) * 16), Math.round(y - (o.footDrop || 28)));
    side = -side;
    y += (o.step || 50) * (0.85 + rng() * 0.3);
  }
}
// Extra holds spread over the whole width, so there is more than one way up.
function scatter(r, rng, y0, y1, o) {
  const tries = Math.round((y1 - y0) * (WALL.hr - WALL.hl) / 1000 * (o.dens || 1));
  for (let k = 0; k < tries; k++) {
    const x = Math.round(WALL.hl + rng() * (WALL.hr - WALL.hl)), y = Math.round(y0 + rng() * (y1 - y0));
    const chip = rng() < (o.chip == null ? 0.4 : o.chip);
    if (nearHold(r, x, y, chip ? 30 : (o.minD || 50)) || onLedge(r, x, y, 18, 26, 34)) continue;
    r.holds.push({ t: chip ? 'chip' : pick(o.types, rng), x, y }); gridAdd(r, r.holds.length - 1);
  }
}
function ledgeAt(r, cx, y, w) {
  const half = w / 2, mid = Math.max(WALL.hl + half, Math.min(WALL.hr - half, cx));
  pushLedge(r, { t: 'ledge', x: Math.round(mid - half), x2: Math.round(mid + half), y });
}
function topAt(r, y) { pushLedge(r, { t: 'top', x: 40, x2: 320, y }); r.topY = y; }
function startCluster(r) {
  r.startHands = [addHold(r, 'jug', 150, 160), addHold(r, 'jug', 212, 166)];
  [[164, 42], [198, 48], [152, 96], [210, 102]].forEach(p => addHold(r, 'chip', p[0], p[1]));
}
function finish(r) { delete r._grid; delete r._ledges; return r; }
function buildRoutes() {
  const out = [];
  // 1. First Wall: the lesson line stays in the middle, extra big holds fill the sides
  const a = makeRoute('first', 'First Wall', 1, 'Big holds. Learn how to climb.', true);
  startCluster(a);
  [['jug', 138, 218], ['jug', 224, 230], ['chip', 180, 196], ['crimp', 182, 272], ['jug', 140, 292], ['jug', 226, 302]].forEach(h => addHold(a, h[0], h[1], h[2]));
  pushLedge(a, { t: 'ledge', x: 108, x2: 256, y: 345 });
  [['jug', 150, 396], ['jug', 214, 408], ['chip', 178, 430], ['sloper', 184, 452], ['jug', 140, 478], ['jug', 226, 490], ['chip', 176, 512], ['jug', 152, 540], ['jug', 214, 552]].forEach(h => addHold(a, h[0], h[1], h[2]));
  topAt(a, 610);
  let rng = mulberry32(3);
  scatter(a, rng, 120, 580, { dens: 0.9, minD: 54, chip: 0.35, types: [['jug', 4], ['crimp', 1]] });
  out.push(finish(a));

  // 2. Granite Steps: a line that wanders left and right, two ledges
  const b = makeRoute('steps', 'Granite Steps', 2, 'Smaller holds and two ledges.');
  rng = mulberry32(7);
  startCluster(b);
  let cx = wander(rng, 70);
  ladder(b, rng, 214, 300, { types: [['jug', 3], ['crimp', 2]], feet: 0.85, cxAt: cx });
  ledgeAt(b, cx(345), 345, 140);
  ladder(b, rng, 396, 590, { types: [['jug', 2], ['crimp', 3], ['sloper', 1]], feet: 0.75, cxAt: cx });
  ledgeAt(b, cx(638), 638, 150);
  ladder(b, rng, 690, 860, { types: [['crimp', 3], ['jug', 2], ['sloper', 1]], feet: 0.7, cxAt: cx });
  topAt(b, 912);
  const cx2 = y => 360 - cx(y);
  ladder(b, rng, 240, 860, { types: [['crimp', 3], ['sloper', 2], ['jug', 1]], feet: 0.5, cxAt: cx2, startSide: 1 });
  scatter(b, rng, 120, 880, { dens: 0.8, minD: 52, chip: 0.4, types: [['jug', 2], ['crimp', 3], ['sloper', 1]] });
  out.push(finish(b));

  // 3. Crimp Ladder: small holds, few steps, one ledge
  const c = makeRoute('crimps', 'Crimp Ladder', 3, 'Small holds and few steps for your feet.');
  rng = mulberry32(21);
  startCluster(c);
  cx = wander(rng, 85);
  ladder(c, rng, 214, 560, { types: [['crimp', 4], ['sloper', 2], ['jug', 1]], feet: 0.45, step: 54, spread: 38, cxAt: cx });
  ledgeAt(c, cx(604), 604, 130);
  ladder(c, rng, 656, 1140, { types: [['crimp', 4], ['sloper', 2], ['jug', 1]], feet: 0.4, step: 56, spread: 40, cxAt: cx });
  topAt(c, 1192);
  scatter(c, rng, 120, 1160, { dens: 0.75, minD: 54, chip: 0.3, types: [['crimp', 4], ['sloper', 3], ['jug', 1]] });
  out.push(finish(c));
  return out;
}
const ROUTES = buildRoutes();

// ---- Jumps: a hand can jump to a hold just out of reach if a foot is on a hold ----
const DYNO_EXTRA = 58;                    // extra reach a jump gives, in units (cm)
const CATCH_COST = { good: 18, weak: 30 }; // grip lost on the catch
const HANG_TIME = 1.5;                    // seconds to get a second hold after a one-hand catch (runs slower while you aim)
function dynoCheck(limbs, i, pt, C) {
  if (!IS_HAND[i]) return { ok: false, why: 'Only hands can jump.' };
  const feet = (limbs[2].h != null ? 1 : 0) + (limbs[3].h != null ? 1 : 0);
  // stand up as far as the other holds allow, then measure what is left for the jump
  const hard = [];
  for (let k = 0; k < 4; k++) if (k !== i && limbs[k].h != null) hard.push({ i: k, x: limbs[k].x, y: limbs[k].y });
  const lean = solve(C, hard.concat([{ i, x: pt.x, y: pt.y, w: 0.6 }]), 60);
  const P = solve(lean, hard, 1);
  const sx = P.x + JOINT[i][0], sy = P.y + JOINT[i][1];
  const d = Math.hypot(pt.x - sx, pt.y - sy);
  if (d > REACH[i] + DYNO_EXTRA) return { ok: false, why: 'Too far, even with a jump.' };
  if (pt.y < sy - 4) return { ok: false, why: 'You can only jump up.' };
  if (!feet) return { ok: false, why: 'Put a foot on a hold first.' };
  const end = solve(C, [{ i, x: pt.x, y: pt.y }], 60);
  return { ok: true, end: { x: end.x, y: end.y } };
}

// ---- Daily Wall: an endless wall made from the date ----
const CHUNK = 520;
function dailySeed(str) { let h = 2166136261; for (let k = 0; k < str.length; k++) { h ^= str.charCodeAt(k); h = Math.imul(h, 16777619); } return h >>> 0; }
function chunkStyle(k) {
  const t = Math.min(1, k / 6);
  const types = k === 0 ? [['jug', 3], ['crimp', 1]] : k === 1 ? [['jug', 2], ['crimp', 2]] : k < 4 ? [['jug', 2], ['crimp', 3], ['sloper', 1]] : [['crimp', 4], ['sloper', 2], ['jug', 1]];
  return { types, feet: 0.85 - 0.45 * t, step: 50 + 6 * t, spread: 34 + 6 * t, dens: 0.85 - 0.25 * t };
}
function buildEndless(seed, chunks, dateLabel) {
  const r = makeRoute('daily', 'Daily Wall', 0, 'A new wall every day. How high can you go?');
  r.endless = true; r.date = dateLabel || '';
  const rng = mulberry32(seed);
  startCluster(r);
  const cx = wander(rng, 80), cx2 = y => 360 - cx(y);
  for (let k = 0; k < chunks; k++) {
    const base = k * CHUNK, st = chunkStyle(k);
    ladder(r, rng, base + (k === 0 ? 214 : 52), base + CHUNK - 50, { ...st, cxAt: cx });
    ledgeAt(r, cx(base + CHUNK), base + CHUNK, 140 + Math.round(rng() * 20));
  }
  r.topY = chunks * CHUNK;
  for (let k = 0; k < chunks; k++) {
    const base = k * CHUNK, st = chunkStyle(k);
    if (k > 0) ladder(r, rng, base + 60, base + CHUNK - 60, { types: st.types, feet: st.feet * 0.6, step: st.step, spread: st.spread, cxAt: cx2, startSide: 1 });
    scatter(r, rng, Math.max(120, base), base + CHUNK, { dens: st.dens, minD: 52, chip: 0.38, types: st.types });
  }
  return finish(r);
}
