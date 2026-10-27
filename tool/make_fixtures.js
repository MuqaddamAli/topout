// Writes test/fixtures/core_fixtures.json from the web prototype's rules,
// so the Dart port can be checked against them (see test/core_test.dart).
// Run: node tool/make_fixtures.js
const fs = require('fs');
const path = require('path');
const core = fs.readFileSync(path.join(__dirname, '..', 'web_prototype', 'core.js'), 'utf8');
const A = new Function(core + '\nreturn { ROUTES, buildEndless, dailySeed, mulberry32, solve, feasible, dynoCheck, gripRates, supportInfo, attachPoint, JOINT };')();

const holdsOf = r => r.holds.map(h => [h.t, h.x, h.y, h.x2 == null ? null : h.x2]);
const out = { rng: {}, seeds: {}, routes: [], daily: [], solve: [], feasible: [], dyno: [], grip: [] };

for (const s of [1, 3, 7, 21, 99, 123456789, 4294967295]) { const r = A.mulberry32(s); out.rng[s] = Array.from({ length: 6 }, () => r()); }
for (const d of ['topout-2026-10-27', 'topout-2027-01-01', 'abc']) out.seeds[d] = A.dailySeed(d);
for (const r of A.ROUTES) out.routes.push({ id: r.id, topY: r.topY, startHands: r.startHands, holds: holdsOf(r) });
for (const d of ['2026-10-27', '2027-01-01']) {
  const r = A.buildEndless(A.dailySeed('topout-' + d), 40, d);
  out.daily.push({ date: d, topY: r.topY, startHands: r.startHands, holds: holdsOf(r) });
}

// Solver checks on real positions from the first route.
const R = A.ROUTES[0], H = R.holds, rnd = A.mulberry32(2024);
const limbsAt = (hs) => hs.map((h, i) => { if (h == null) return { h: null, x: 0, y: 0 }; const p = A.attachPoint(H[h], i); return { h, x: p.x, y: p.y }; });
const small = H.map((h, k) => k).filter(k => H[k].x2 == null);
const near = (x, y, d, hand) => { const c = small.filter(k => Math.hypot(H[k].x - x, H[k].y - y) < d && (!hand || H[k].t !== 'chip')); return c.length ? c[Math.floor(rnd() * c.length)] : null; };
for (let n = 0; n < 60; n++) {
  const C = { x: 130 + rnd() * 100, y: 120 + rnd() * 380 };
  const hs = [near(C.x - 20, C.y + 55, 45, true), near(C.x + 20, C.y + 55, 45, true), near(C.x - 15, C.y - 55, 45, false), near(C.x + 15, C.y - 55, 45, false)];
  if (n % 5 === 4) hs[2] = null;
  if (hs.every(h => h == null)) continue;
  const limbs = limbsAt(hs);
  const anc = []; limbs.forEach((l, i) => { if (l.h != null) anc.push({ i, x: l.x, y: l.y }); });
  const iters = [24, 50, 80][n % 3];
  const s = A.solve(C, anc, iters);
  out.solve.push({ c: [C.x, C.y], anchors: anc.map(a => [a.i, a.x, a.y]), iters, out: [s.x, s.y, s.err] });
  const i = Math.floor(rnd() * 4), target = near(C.x, C.y + (i < 2 ? 70 : -40), 110, i < 2);
  if (target == null) continue;
  const pt = A.attachPoint(H[target], i);
  const f = A.feasible(limbs, i, pt, C);
  out.feasible.push({ limbs: limbs.map(l => [l.h, l.x, l.y]), i, pt: [pt.x, pt.y], c: [C.x, C.y], out: f ? [f.x, f.y, f.err] : null });
  const dc = A.dynoCheck(limbs, i, pt, C);
  out.dyno.push({ limbs: limbs.map(l => [l.h, l.x, l.y]), i, pt: [pt.x, pt.y], c: [C.x, C.y], ok: dc.ok, why: dc.why || '', end: dc.ok ? [dc.end.x, dc.end.y] : null });
  for (const mode of ['casual', 'normal']) {
    const g = A.gripRates(limbs, H, mode);
    out.grip.push({ limbs: limbs.map(l => [l.h, l.x, l.y]), mode, rates: g.rates, standing: g.s.standing, supported: g.s.supported, feetW: g.s.feetW });
  }
}
fs.writeFileSync(path.join(__dirname, '..', 'test', 'fixtures', 'core_fixtures.json'), JSON.stringify(out));
console.log('routes', out.routes.map(r => r.holds.length).join(','), 'daily', out.daily.map(r => r.holds.length).join(','),
  'dyno ok', out.dyno.filter(d => d.ok).length, 'feasible', out.feasible.filter(f => f.out).length);
