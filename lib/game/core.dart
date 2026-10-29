// Game rules: holds, the body solver, grip, jumps and the route builders.
//
// This file has no Flutter imports, so it can be tested on its own. It is a
// line-by-line port of the web prototype's core, and the tests in
// test/core_test.dart check that both make the same walls.

import 'dart:math' as math;

const List<String> limbNames = ['left hand', 'right hand', 'left foot', 'right foot'];
const List<bool> isHand = [true, true, false, false];
const List<double> sideOf = [-1, 1, -1, 1];

/// Shoulder and hip offsets from the centre of the torso (y points up).
const List<List<double>> jointOffset = [
  [-13, 25],
  [13, 25],
  [-10, -25],
  [10, -25],
];
const List<double> reach = [66, 66, 80, 80];
const List<double> minReach = [16, 16, 24, 24];

/// Grip drains at this rate while you aim a limb.
const double slowWhileAiming = 0.35;
const double unitsPerMetre = 100;

/// The band of the wall the camera can show, and the x range holds may use.
class Wall {
  static const double left = 0, right = 360, holdLeft = 34, holdRight = 326;
}

enum Quality { good, weak, no }

enum HoldType {
  jug(Quality.good, Quality.good, 2.5, 1, 'big hold'),
  crimp(Quality.weak, Quality.good, 6.5, 1, 'small edge'),
  sloper(Quality.weak, Quality.weak, 8, 0.5, 'round hold'),
  chip(Quality.no, Quality.good, 0, 1, 'foot step'),
  ledge(Quality.good, Quality.good, 1.5, 1, 'ledge', rest: true, wide: true),
  ground(Quality.no, Quality.good, 0, 1, 'ground', rest: true, wide: true),
  top(Quality.good, Quality.good, 1.5, 1, 'top', rest: true, wide: true);

  const HoldType(this.hand, this.foot, this.drain, this.feet, this.label, {this.rest = false, this.wide = false});
  final Quality hand;
  final Quality foot;
  final double drain;
  final double feet;
  final String label;
  final bool rest;
  final bool wide;
}

enum Mode {
  casual('Relaxed', 0.6, true, 0.22, 'Your hands get tired more slowly.'),
  normal('Normal', 1, true, 0.3, 'Rest on a ledge to save your place.'),
  solo('No saves', 1, false, 0.38, 'If you fall, you start again from the ground.');

  const Mode(this.label, this.drain, this.ledges, this.slowMo, this.note);
  final String label;
  final double drain;
  final bool ledges;

  /// How slow time runs while you can catch a hold in a fall.
  final double slowMo;
  final String note;

  static Mode fromName(String? name) {
    for (final m in Mode.values) {
      if (m.name == name) return m;
    }
    return Mode.normal;
  }
}

/// A mutable 2D point in world units (centimetres, y up).
class Pt {
  Pt(this.x, this.y);
  double x;
  double y;
  Pt copy() => Pt(x, y);
  @override
  String toString() => 'Pt(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

class Hold {
  const Hold(this.t, this.x, this.y, [this.x2]);
  final HoldType t;
  final double x;
  final double y;

  /// Right end of a wide hold (ledge, ground, top). Null for small holds.
  final double? x2;
}

/// One hand or foot. [h] is the index of the hold it is on, or null when free.
class Limb {
  Limb(this.h, this.x, this.y);
  int? h;
  double x;
  double y;
  Limb copy() => Limb(h, x, y);
}

class Anchor {
  const Anchor(this.i, this.x, this.y, [this.w]);
  final int i;
  final double x;
  final double y;

  /// Weight of a soft anchor (the limb you are dragging). Null means a real hold.
  final double? w;
}

class SolveResult {
  const SolveResult(this.x, this.y, this.err);
  final double x;
  final double y;
  final double err;
}

double hypot(double x, double y) => math.sqrt(x * x + y * y);
double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);

/// Rounds like JavaScript's Math.round (halves go up), so walls match the web build.
double jsRound(double x) => (x + 0.5).floorToDouble();

Quality quality(Hold h, int i) => isHand[i] ? h.t.hand : h.t.foot;

Pt attachPoint(Hold h, int i, [double? px]) {
  if (h.t.wide) {
    final mid = (h.x + h.x2!) / 2;
    return Pt(math.max(h.x + 6, math.min(h.x2! - 6, px ?? mid)), h.y);
  }
  return Pt(h.x + sideOf[i] * 3, h.y);
}

double holdDist(Hold h, double px, double py) {
  if (h.t.wide) {
    final cx = math.max(h.x, math.min(h.x2!, px));
    return hypot(px - cx, py - h.y);
  }
  return hypot(px - h.x, py - h.y);
}

/// Torso solver: gravity pulls the body down (or standing pushes it up) while
/// each attached limb keeps it within reach ([rch], one length per limb).
SolveResult solve(Pt c0, List<Anchor> anchors, [int iters = 40, List<double> rch = reach]) {
  var x = c0.x, y = c0.y;
  if (anchors.isEmpty) return SolveResult(x, y, 0);
  final hang = anchors.any((a) => a.i < 2 && (a.w == null || a.w! >= 1));
  final bias = hang ? -1.5 : 1.5;
  final n = iters;
  for (var k = 0; k < n + 12; k++) {
    if (k < n) y += bias;
    for (final a in anchors) {
      final w = a.w ?? 1.0;
      final jx = x + jointOffset[a.i][0], jy = y + jointOffset[a.i][1];
      final dx = a.x - jx, dy = a.y - jy;
      var l = hypot(dx, dy);
      if (l == 0) l = 1e-6;
      if (l > rch[a.i]) {
        final c = (l - rch[a.i]) * 0.6 * w;
        x += dx / l * c;
        y += dy / l * c;
      } else if (l < minReach[a.i]) {
        final c = (minReach[a.i] - l) * 0.6 * w;
        x -= dx / l * c;
        y -= dy / l * c;
      }
    }
  }
  var err = 0.0;
  for (final a in anchors) {
    if (a.w != null && a.w! < 1) continue;
    final l = hypot(a.x - x - jointOffset[a.i][0], a.y - y - jointOffset[a.i][1]);
    err = math.max(err, math.max(l - rch[a.i], minReach[a.i] - l));
  }
  return SolveResult(x, y, err);
}

class Support {
  const Support(this.hands, this.feet, this.feetW, this.standing, this.restIds, this.supported);
  final int hands;
  final int feet;
  final double feetW;
  final bool standing;
  final List<int> restIds;
  final bool supported;
}

/// While a hold is still covered in snow, a hand on it tires [snowSlick]
/// times as fast, and a foot on it counts [snowFoot] of a dry one. The snow
/// comes off after the limb has been on it a moment (see Game).
const double snowSlick = 1.5, snowFoot = 0.6;

/// How the limbs hold the body up. [snowy] are the holds that still have snow on them.
Support supportInfo(List<Limb> limbs, List<Hold> holds, [Set<int> snowy = const {}]) {
  var hands = 0, feet = 0, rest = 0;
  var feetW = 0.0;
  final restIds = <int>[];
  for (var i = 0; i < 4; i++) {
    final l = limbs[i];
    if (l.h == null) continue;
    final t = holds[l.h!].t;
    if (isHand[i]) {
      hands++;
    } else {
      feet++;
      feetW += t.feet * (snowy.contains(l.h) ? snowFoot : 1);
      if (t.rest) {
        rest++;
        restIds.add(l.h!);
      }
    }
  }
  final standing = rest == 2;
  return Support(hands, feet, feetW, standing, restIds, standing || (hands >= 1 && hands + feet >= 2));
}

double feetMult(double fw) => fw >= 2 ? 0.55 : fw >= 1.5 ? 0.75 : fw >= 1 ? 1 : fw >= 0.5 ? 1.4 : 2;

class GripRates {
  const GripRates(this.rates, this.s);
  final List<double> rates;
  final Support s;
}

/// How fast each hand gains (+) or loses (-) grip per second, for climber [k].
/// [snowy] are the holds that still have snow on them.
GripRates gripRates(List<Limb> limbs, List<Hold> holds, Mode mode, [Climber? k, Set<int> snowy = const {}]) {
  final kk = k ?? Climber.base;
  final s = supportInfo(limbs, holds, snowy);
  final rates = <double>[0, 0];
  for (var i = 0; i < 2; i++) {
    final l = limbs[i];
    if (l.h == null) {
      rates[i] = 14 * kk.restMul;
      continue;
    }
    if (s.standing) {
      rates[i] = 12 * kk.restMul;
      continue;
    }
    rates[i] = -kk.holdDrain(holds[l.h!].t) * feetMult(s.feetW) * (s.hands == 1 ? kk.oneHand : 1) * mode.drain *
        (snowy.contains(l.h) ? snowSlick : 1);
  }
  return GripRates(rates, s);
}

/// Can limb [i] reach [pt] while the other attached limbs stay where they are?
SolveResult? feasible(List<Limb> limbs, int i, Pt pt, Pt c, [Climber? k]) {
  final anc = <Anchor>[];
  for (var n = 0; n < 4; n++) {
    if (n == i) {
      anc.add(Anchor(n, pt.x, pt.y));
      continue;
    }
    final l = limbs[n];
    if (l.h != null) anc.add(Anchor(n, l.x, l.y));
  }
  final r = solve(c, anc, 50, (k ?? Climber.base).reach);
  return r.err < 1.2 ? r : null;
}

// ---------------------------------------------------------------- jumps

/// Extra reach a jump gives, in units (cm).
const double dynoExtra = 58;

/// Grip lost when you catch a jump.
const Map<Quality, double> catchCost = {Quality.good: 18, Quality.weak: 30};

/// Seconds to get a second hold after a one-hand catch (runs slower while you aim).
const double hangTime = 1.5;

class DynoResult {
  const DynoResult.no(this.why)
      : ok = false,
        end = null;
  const DynoResult.yes(Pt this.end)
      : ok = true,
        why = '';
  final bool ok;
  final String why;
  final Pt? end;
}

/// A hand can jump to a hold just out of reach if a foot is on a hold
/// (climbers with [Perk.freeJump] do not need the foot).
DynoResult dynoCheck(List<Limb> limbs, int i, Pt pt, Pt c, [Climber? k]) {
  if (!isHand[i]) return const DynoResult.no('Only hands can jump.');
  final kk = k ?? Climber.base, rch = kk.reach;
  final feet = (limbs[2].h != null ? 1 : 0) + (limbs[3].h != null ? 1 : 0);
  // stand up as far as the other holds allow, then measure what is left for the jump
  final hard = <Anchor>[];
  for (var n = 0; n < 4; n++) {
    if (n != i && limbs[n].h != null) hard.add(Anchor(n, limbs[n].x, limbs[n].y));
  }
  final lean = solve(c, [...hard, Anchor(i, pt.x, pt.y, 0.6)], 60, rch);
  final p = solve(Pt(lean.x, lean.y), hard, 1, rch);
  final sx = p.x + jointOffset[i][0], sy = p.y + jointOffset[i][1];
  final d = hypot(pt.x - sx, pt.y - sy);
  if (d > rch[i] + kk.dynoExtra) return const DynoResult.no('Too far, even with a jump.');
  if (pt.y < sy - 4) return const DynoResult.no('You can only jump up.');
  if (feet == 0 && kk.perk != Perk.freeJump) return const DynoResult.no('Put a foot on a hold first.');
  final end = solve(c, [Anchor(i, pt.x, pt.y)], 60, rch);
  return DynoResult.yes(Pt(end.x, end.y));
}

// ---------------------------------------------------------------- catching a fall

/// A falling body speeds up by this much each second (cm/s²).
const double fallGravity = 1100;

/// The fastest fall in which a hand can still catch a hold (cm/s): about half
/// a second, or 1.4 m, of falling.
const double snatchMaxSpeed = 560;

/// How far a body falls before it is too fast to catch anything.
const double snatchDrop = snatchMaxSpeed * snatchMaxSpeed / (2 * fallGravity);

/// Grip that catching each kind of hold costs, when you have only just let go.
const Map<HoldType, double> snatchBase = {
  HoldType.ledge: 10,
  HoldType.top: 10,
  HoldType.jug: 16,
  HoldType.crimp: 30,
  HoldType.sloper: 38,
};

/// Where hand [i] of a body at [c] (falling, so arms up) would catch [h], or
/// null if it cannot: the hold must be a hand hold, within reach of the
/// shoulder, and not below it (a falling hand grabs up, not down).
Pt? snatchPoint(Hold h, int i, Pt c, [Climber? k]) {
  if (!isHand[i] || quality(h, i) == Quality.no) return null;
  final sx = c.x + jointOffset[i][0], sy = c.y + jointOffset[i][1];
  final pt = attachPoint(h, i, sx);
  if (pt.y < sy - 10) return null;
  return hypot(pt.x - sx, pt.y - sy) <= (k ?? Climber.base).reach[i] + 4 ? pt : null;
}

/// Grip a catch on a hold of type [t] costs at fall speed [speed] (cm/s).
/// The faster the fall, the harder the jolt.
double snatchCost(HoldType t, double speed, [Climber? k]) {
  final kk = k ?? Climber.base;
  final fingers = kk.perk == Perk.strongFingers && t == HoldType.crimp ? 0.75 : 1.0;
  return snatchBase[t]! * (1 + 1.6 * math.min(1.0, speed.abs() / snatchMaxSpeed)) * kk.catchMul * fingers;
}

// ---------------------------------------------------------------- climbers

/// The one rule that makes a climber different from the others.
enum Perk {
  calm('Calm', 'Grip lasts longer while you aim.'),
  strongArm('Strong arm', 'Hanging on one hand costs less grip.'),
  strongFingers('Strong fingers', 'Small edges tire the hands less.'),
  freeJump('Free jump', 'Can jump with no feet on the wall, even right after a catch.');

  const Perk(this.label, this.note);
  final String label;
  final String note;
}

// The Climber class has fields with these names, so it reads the base values here.
const List<double> _baseReach = reach;
const double _baseDynoExtra = dynoExtra, _baseHangTime = hangTime;

/// Each climber's four stats (1 to 5) add up to this, so nobody is best at everything.
const int statBudget = 12;

/// A climber you can pick. Stat 3 is the original game; every point above or
/// below moves one number a small step.
class Climber {
  Climber({
    required this.id,
    required this.name,
    required this.role,
    required this.reachStat,
    required this.gripStat,
    required this.restStat,
    required this.jumpStat,
    required this.perk,
  })  : reach = List.unmodifiable([
          _baseReach[0] + 3.0 * (reachStat - 3),
          _baseReach[1] + 3.0 * (reachStat - 3),
          _baseReach[2] + 3.0 * (reachStat - 3),
          _baseReach[3] + 3.0 * (reachStat - 3),
        ]),
        drainMul = 1 - 0.1 * (gripStat - 3),
        restMul = 1 + 0.15 * (restStat - 3),
        dynoExtra = _baseDynoExtra + 10.0 * (jumpStat - 3),
        hangTime = _baseHangTime + 0.2 * (jumpStat - 3),
        catchMul = 1 - 0.1 * (jumpStat - 3);

  final String id;
  final String name;

  /// What the climber is good at, in two or three words.
  final String role;
  final int reachStat, gripStat, restStat, jumpStat;
  final Perk perk;

  /// Arm, arm, leg, leg reach in cm.
  final List<double> reach;

  /// Multiplies how fast a hand tires on a hold.
  final double drainMul;

  /// Multiplies how fast a hand gets its grip back.
  final double restMul;

  /// Extra reach a jump gives, and the time to grab a second hold after it.
  final double dynoExtra, hangTime;

  /// Multiplies the grip a catch costs.
  final double catchMul;

  int get statTotal => reachStat + gripStat + restStat + jumpStat;

  /// Arm and leg length compared to the original climber (for drawing).
  double get armScale => reach[0] / _baseReach[0];
  double get legScale => reach[2] / _baseReach[2];

  /// Grip drain while you aim a limb, as a share of the normal drain.
  double get aimSlow => perk == Perk.calm ? 0.2 : slowWhileAiming;

  /// Grip drain when only one hand holds on.
  double get oneHand => perk == Perk.strongArm ? 1.2 : 1.5;

  double holdDrain(HoldType t) => t.drain * (perk == Perk.strongFingers && t == HoldType.crimp ? 0.7 : 1) * drainMul;

  double catchCostFor(Quality q) => catchCost[q == Quality.good ? Quality.good : Quality.weak]! * catchMul;

  static final Climber ada = Climber(
      id: 'ada', name: 'Ada', role: 'All-rounder', reachStat: 3, gripStat: 3, restStat: 3, jumpStat: 3, perk: Perk.calm);
  static final Climber rio = Climber(
      id: 'rio', name: 'Rio', role: 'Long reach', reachStat: 5, gripStat: 2, restStat: 3, jumpStat: 2, perk: Perk.strongArm);
  static final Climber mei = Climber(
      id: 'mei', name: 'Mei', role: 'Small holds', reachStat: 2, gripStat: 4, restStat: 4, jumpStat: 2, perk: Perk.strongFingers);
  static final Climber kai = Climber(
      id: 'kai', name: 'Kai', role: 'Jumper', reachStat: 3, gripStat: 2, restStat: 2, jumpStat: 5, perk: Perk.freeJump);

  static final List<Climber> all = List.unmodifiable([ada, rio, mei, kai]);

  /// The original climber: every stat at 3. The prototype's rules are hers.
  static Climber get base => ada;

  static Climber byId(String? id) => all.firstWhere((k) => k.id == id, orElse: () => ada);
}

// ---------------------------------------------------------------- random numbers

/// 32-bit integer multiply with wrap-around, like JavaScript's Math.imul.
/// Written so it gives the same answer on the Dart VM and on the web.
int imul32(int a, int b) {
  final ah = (a >> 16) & 0xffff, al = a & 0xffff;
  final bh = (b >> 16) & 0xffff, bl = b & 0xffff;
  return (al * bl + ((((ah * bl + al * bh) & 0xffff) << 16) & 0xffffffff)) & 0xffffffff;
}

/// The mulberry32 generator, identical to the web build: same seed, same wall.
class Rng {
  Rng(int seed) : _a = seed & 0xffffffff;
  int _a;

  double call() {
    _a = (_a + 0x6D2B79F5) & 0xffffffff;
    var t = imul32(_a ^ (_a >> 15), 1 | _a);
    t = ((t + imul32(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t;
    return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0;
  }
}

/// FNV-1a hash of a string, used to turn today's date into a seed.
int dailySeed(String str) {
  var h = 2166136261;
  for (final c in str.codeUnits) {
    h = (h ^ c) & 0xffffffff;
    h = imul32(h, 16777619);
  }
  return h;
}

// ---------------------------------------------------------------- routes

typedef Weighted = List<(HoldType, double)>;

HoldType pick(Weighted arr, Rng rng) {
  var tot = 0.0;
  for (final a in arr) {
    tot += a.$2;
  }
  var r = rng() * tot;
  for (final (t, w) in arr) {
    r -= w;
    if (r <= 0) return t;
  }
  return arr[0].$1;
}

class ClimbRoute {
  ClimbRoute({
    required this.id,
    required this.name,
    required this.level,
    required this.blurb,
    this.tutorial = false,
    this.endless = false,
    this.date = '',
  });
  final String id;
  final String name;

  /// 1 to 3 for the fixed routes, 0 for the Daily Wall.
  final int level;
  final String blurb;
  final bool tutorial;
  final bool endless;
  final String date;
  final List<Hold> holds = [const Hold(HoldType.ground, -200, 0, 560)];
  List<int> startHands = [];
  double topY = 0;

  /// The lanes side by side (see [laneWall]). A route on its own has one.
  List<Lane> get lanes => _lanes ??= [Lane(0, Wall.left, false, startHands, _spawns(0, startHands, holds))];
  List<Lane>? _lanes;

  /// Rows of holds that join neighbouring lanes. None with one lane.
  final List<Bridge> bridges = [];

  /// The x range of the whole wall, all lanes together.
  double get wallLeft => Wall.left;
  double get wallRight => Wall.left + lanes.length * Wall.right;

  /// The lane that x is in (the nearest one at the edges).
  Lane laneAt(double x) => lanes[clampD(((x - Wall.left) / Wall.right).floorToDouble(), 0, lanes.length - 1.0).toInt()];

  int get ledgeCount => holds.where((h) => h.t == HoldType.ledge).length;

  /// Indices of all holds sorted by height (made on first use, after the route
  /// is built), so the game and the painter only look at holds near a height.
  late final List<int> byY = List<int>.generate(holds.length, (k) => k)
    ..sort((a, b) => holds[a].y.compareTo(holds[b].y));
  late final List<double> _ys = [for (final k in byY) holds[k].y];

  /// The first position in [byY] whose hold is at height [y] or above.
  int firstAtOrAbove(double y) {
    var lo = 0, hi = _ys.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_ys[mid] < y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Keeps track of where holds are while a route is being built.
class _Builder {
  _Builder(this.r);
  final ClimbRoute r;
  final Map<String, List<int>> grid = {};
  final List<Hold> ledges = [];
  static const double cell = 40;

  void gridAdd(int k) {
    final h = r.holds[k];
    if (h.x2 != null) return;
    final key = '${(h.x / cell).floor()},${(h.y / cell).floor()}';
    grid.putIfAbsent(key, () => []).add(k);
  }

  /// True if a small hold is closer than [d].
  bool nearHold(double x, double y, double d) {
    final gx = (x / cell).floor(), gy = (y / cell).floor(), n = (d / cell).ceil();
    for (var i = -n; i <= n; i++) {
      for (var j = -n; j <= n; j++) {
        final c = grid['${gx + i},${gy + j}'];
        if (c == null) continue;
        for (final k in c) {
          final h = r.holds[k];
          if (hypot(h.x - x, h.y - y) < d) return true;
        }
      }
    }
    return false;
  }

  bool onLedge(double x, double y, double mx, double below, double above) {
    for (final h in ledges) {
      if (y > h.y - below && y < h.y + above && x > h.x - mx && x < h.x2! + mx) return true;
    }
    return false;
  }

  int addHold(HoldType t, double x, double y, [double? x2]) {
    if (x2 == null) {
      if (nearHold(x, y, 18) || onLedge(x, y, 10, 16, 16)) return -1;
      r.holds.add(Hold(t, x, y));
      gridAdd(r.holds.length - 1);
    } else {
      pushLedge(Hold(t, x, y, x2));
    }
    return r.holds.length - 1;
  }

  void pushLedge(Hold h) {
    r.holds.add(h);
    if (h.t != HoldType.ground) ledges.add(h);
  }

  void ladder(Rng rng, double y0, double y1,
      {required Weighted types,
      required double Function(double) cxAt,
      double startSide = -1,
      double spread = 34,
      double jit = 18,
      double feet = 0.7,
      HoldType footType = HoldType.chip,
      double footDrop = 28,
      double step = 50}) {
    var side = startSide, y = y0;
    while (y <= y1) {
      final cx = cxAt(y);
      final x = math.max(Wall.holdLeft, math.min(Wall.holdRight, cx + side * spread + (rng() - 0.5) * jit));
      final t = pick(types, rng);
      addHold(t, jsRound(x), jsRound(y));
      if (rng() < feet) {
        final fx = jsRound(cx - side * 14 + (rng() - 0.5) * 16);
        addHold(footType, fx, jsRound(y - footDrop));
      }
      side = -side;
      y += step * (0.85 + rng() * 0.3);
    }
  }

  /// Extra holds spread over the whole width, so there is more than one way up.
  void scatter(Rng rng, double y0, double y1,
      {required Weighted types, double dens = 1, double chip = 0.4, double minD = 50}) {
    final tries = jsRound((y1 - y0) * (Wall.holdRight - Wall.holdLeft) / 1000 * dens).toInt();
    for (var k = 0; k < tries; k++) {
      final x = jsRound(Wall.holdLeft + rng() * (Wall.holdRight - Wall.holdLeft));
      final y = jsRound(y0 + rng() * (y1 - y0));
      final isChip = rng() < chip;
      if (nearHold(x, y, isChip ? 30 : minD) || onLedge(x, y, 18, 26, 34)) continue;
      r.holds.add(Hold(isChip ? HoldType.chip : pick(types, rng), x, y));
      gridAdd(r.holds.length - 1);
    }
  }

  void ledgeAt(double cx, double y, double w) {
    final half = w / 2, mid = math.max(Wall.holdLeft + half, math.min(Wall.holdRight - half, cx));
    pushLedge(Hold(HoldType.ledge, jsRound(mid - half), y, jsRound(mid + half)));
  }

  void topAt(double y) {
    pushLedge(Hold(HoldType.top, 40, y, 320));
    r.topY = y;
  }

  void startCluster() {
    r.startHands = [addHold(HoldType.jug, 150, 160), addHold(HoldType.jug, 212, 166)];
    for (final p in const [
      [164.0, 42.0],
      [198.0, 48.0],
      [152.0, 96.0],
      [210.0, 102.0],
    ]) {
      addHold(HoldType.chip, p[0], p[1]);
    }
  }
}

/// A line that wanders across the wall. Starts in the middle near the ground.
double Function(double) wander(Rng rng, double amp) {
  final a1 = amp * (0.6 + rng() * 0.4), f1 = 0.0032 + rng() * 0.0026, p1 = rng() * 6.283;
  final a2 = amp * (0.15 + rng() * 0.15), f2 = 0.011 + rng() * 0.006, p2 = rng() * 6.283;
  double raw(double y) => a1 * math.sin(y * f1 + p1) + a2 * math.sin(y * f2 + p2);
  final r0 = raw(200);
  return (double y) {
    final k = math.max(0.0, math.min(1.0, (y - 200) / 260));
    return math.max(78.0, math.min(282.0, 180 + (raw(y) - r0) * k));
  };
}

const HoldType _jug = HoldType.jug, _crimp = HoldType.crimp, _sloper = HoldType.sloper, _chip = HoldType.chip;

List<ClimbRoute> buildRoutes() {
  final out = <ClimbRoute>[];

  // 1. First Wall: the lesson line stays in the middle, extra big holds fill the sides
  final a = ClimbRoute(id: 'first', name: 'First Wall', level: 1, blurb: 'Big holds. Learn how to climb.', tutorial: true);
  final ba = _Builder(a)..startCluster();
  for (final (t, x, y) in const [
    (_jug, 138.0, 218.0), (_jug, 224.0, 230.0), (_chip, 180.0, 196.0), //
    (_crimp, 182.0, 272.0), (_jug, 140.0, 292.0), (_jug, 226.0, 302.0),
  ]) {
    ba.addHold(t, x, y);
  }
  ba.pushLedge(const Hold(HoldType.ledge, 108, 345, 256));
  for (final (t, x, y) in const [
    (_jug, 150.0, 396.0), (_jug, 214.0, 408.0), (_chip, 178.0, 430.0), //
    (_sloper, 184.0, 452.0), (_jug, 140.0, 478.0), (_jug, 226.0, 490.0),
    (_chip, 176.0, 512.0), (_jug, 152.0, 540.0), (_jug, 214.0, 552.0),
  ]) {
    ba.addHold(t, x, y);
  }
  ba.topAt(610);
  var rng = Rng(3);
  ba.scatter(rng, 120, 580, dens: 0.9, minD: 54, chip: 0.35, types: const [(_jug, 4), (_crimp, 1)]);
  out.add(a);

  // 2. Granite Steps: a line that wanders left and right, two ledges
  final b = ClimbRoute(id: 'steps', name: 'Granite Steps', level: 2, blurb: 'Smaller holds and two ledges.');
  rng = Rng(7);
  final bb = _Builder(b)..startCluster();
  var cx = wander(rng, 70);
  bb.ladder(rng, 214, 300, types: const [(_jug, 3), (_crimp, 2)], feet: 0.85, cxAt: cx);
  bb.ledgeAt(cx(345), 345, 140);
  bb.ladder(rng, 396, 590, types: const [(_jug, 2), (_crimp, 3), (_sloper, 1)], feet: 0.75, cxAt: cx);
  bb.ledgeAt(cx(638), 638, 150);
  bb.ladder(rng, 690, 860, types: const [(_crimp, 3), (_jug, 2), (_sloper, 1)], feet: 0.7, cxAt: cx);
  bb.topAt(912);
  final cxB = cx;
  double cx2(double y) => 360 - cxB(y);
  bb.ladder(rng, 240, 860, types: const [(_crimp, 3), (_sloper, 2), (_jug, 1)], feet: 0.5, cxAt: cx2, startSide: 1);
  bb.scatter(rng, 120, 880, dens: 0.8, minD: 52, chip: 0.4, types: const [(_jug, 2), (_crimp, 3), (_sloper, 1)]);
  out.add(b);

  // 3. Crimp Ladder: small holds, few steps, one ledge
  final c = ClimbRoute(id: 'crimps', name: 'Crimp Ladder', level: 3, blurb: 'Small holds and few steps for your feet.');
  rng = Rng(21);
  final bc = _Builder(c)..startCluster();
  cx = wander(rng, 85);
  bc.ladder(rng, 214, 560, types: const [(_crimp, 4), (_sloper, 2), (_jug, 1)], feet: 0.45, step: 54, spread: 38, cxAt: cx);
  bc.ledgeAt(cx(604), 604, 130);
  bc.ladder(rng, 656, 1140, types: const [(_crimp, 4), (_sloper, 2), (_jug, 1)], feet: 0.4, step: 56, spread: 40, cxAt: cx);
  bc.topAt(1192);
  bc.scatter(rng, 120, 1160, dens: 0.75, minD: 54, chip: 0.3, types: const [(_crimp, 4), (_sloper, 3), (_jug, 1)]);
  out.add(c);
  return out;
}

// ---------------------------------------------------------------- Daily Wall

/// Height of one section of the Daily Wall. Each section ends with a ledge.
const double chunkHeight = 520;

class _ChunkStyle {
  const _ChunkStyle(this.types, this.feet, this.step, this.spread, this.dens);
  final Weighted types;
  final double feet;
  final double step;
  final double spread;
  final double dens;
}

_ChunkStyle _chunkStyle(int k) {
  final t = math.min(1.0, k / 6);
  final Weighted types = k == 0
      ? const [(_jug, 3), (_crimp, 1)]
      : k == 1
          ? const [(_jug, 2), (_crimp, 2)]
          : k < 4
              ? const [(_jug, 2), (_crimp, 3), (_sloper, 1)]
              : const [(_crimp, 4), (_sloper, 2), (_jug, 1)];
  return _ChunkStyle(types, 0.85 - 0.45 * t, 50 + 6 * t, 34 + 6 * t, 0.85 - 0.25 * t);
}

/// An endless wall made from a seed (the date). It gets harder as it goes up.
ClimbRoute buildEndless(int seed, int chunks, [String dateLabel = '']) {
  final r = ClimbRoute(
    id: 'daily',
    name: 'Daily Wall',
    level: 0,
    blurb: 'A new wall every day. How high can you go?',
    endless: true,
    date: dateLabel,
  );
  final rng = Rng(seed);
  final b = _Builder(r)..startCluster();
  final cx = wander(rng, 80);
  double cx2(double y) => 360 - cx(y);
  for (var k = 0; k < chunks; k++) {
    final base = k * chunkHeight, st = _chunkStyle(k);
    b.ladder(rng, base + (k == 0 ? 214 : 52), base + chunkHeight - 50,
        types: st.types, feet: st.feet, step: st.step, spread: st.spread, cxAt: cx);
    final ledgeCx = cx(base + chunkHeight);
    b.ledgeAt(ledgeCx, base + chunkHeight, 140 + jsRound(rng() * 20));
  }
  r.topY = chunks * chunkHeight;
  for (var k = 0; k < chunks; k++) {
    final base = k * chunkHeight, st = _chunkStyle(k);
    if (k > 0) {
      b.ladder(rng, base + 60, base + chunkHeight - 60,
          types: st.types, feet: st.feet * 0.6, step: st.step, spread: st.spread, cxAt: cx2, startSide: 1);
    }
    b.scatter(rng, math.max(120.0, base), base + chunkHeight, dens: st.dens, minD: 52, chip: 0.38, types: st.types);
  }
  return r;
}

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The Daily Wall for a given day. Everyone gets the same wall on the same day.
ClimbRoute dailyWallFor(DateTime day, {int chunks = 40}) {
  final key = dateKey(day);
  return buildEndless(dailySeed('topout-$key'), chunks, key);
}

// ---------------------------------------------------------------- lanes

/// An online room has one lane per two players, and at most this many.
const int maxLanes = 4;

int lanesFor(int players) => math.max(1, math.min(maxLanes, (players + 1) ~/ 2));

/// "Lane 2, left": a lane (0 is the first) and a side (0 left, 1 right), for people.
String laneLabel(int lane, int side) => 'Lane ${lane + 1}, ${side == 0 ? 'left' : 'right'}';

/// How far a spawn's body stands to the side of the start hold its hand is on.
const double spawnStep = 52;

/// Where one online player starts: standing on the ground beside the start
/// holds, with the hand on that side on the start jug of that side.
class Spawn {
  const Spawn(this.lane, this.side, this.hold, this.x);
  final int lane;

  /// 0: left of the start holds (left hand on the left jug), 1: right.
  final int side;

  /// The start jug the hand is on.
  final int hold;

  /// Where the body stands.
  final double x;

  int get hand => side;
}

class Lane {
  const Lane(this.index, this.x0, this.mirrored, this.startHands, this.spawns);
  final int index;

  /// The left edge of the lane. It is [Wall.right] wide.
  final double x0;

  /// Mirrored left to right (every other lane), so the lanes look different.
  final bool mirrored;

  /// The start jugs for the left and the right hand.
  final List<int> startHands;

  /// The left and the right spawn.
  final List<Spawn> spawns;

  double get x1 => x0 + Wall.right;
  double get mid => x0 + Wall.right / 2;
}

/// A short flat row of holds across the edge between lane [lane] and the
/// next one. It gives no height, so it is no shortcut to the top.
class Bridge {
  const Bridge(this.lane, this.y, this.holds);
  final int lane;

  /// Height of the hand holds.
  final double y;
  final List<int> holds;
}

List<Spawn> _spawns(int lane, List<int> hands, List<Hold> holds) => [
      Spawn(lane, 0, hands[0], attachPoint(holds[hands[0]], 0).x - spawnStep),
      Spawn(lane, 1, hands[1], attachPoint(holds[hands[1]], 1).x + spawnStep),
    ];

/// The pose at spawn [s] for climber [k]: feet on the ground either side of
/// the body, one hand on the start jug and the other at the hip. [err] is
/// how far the pose is from what the body can reach (under 1.2 is fine).
({List<Limb> limbs, Pt c, double err}) spawnPose(ClimbRoute r, Spawn s, [Climber? k]) {
  final p = attachPoint(r.holds[s.hold], s.hand);
  final limbs = [Limb(null, 0, 0), Limb(null, 0, 0), Limb(0, s.x - 17, 0), Limb(0, s.x + 17, 0)];
  limbs[s.hand] = Limb(s.hold, p.x, p.y);
  final sol = solve(Pt(s.x, 100), [
    for (var i = 0; i < 4; i++)
      if (limbs[i].h != null) Anchor(i, limbs[i].x, limbs[i].y)
  ], 80, (k ?? Climber.base).reach);
  final free = limbs[1 - s.hand];
  free
    ..x = sol.x + sideOf[1 - s.hand] * 21
    ..y = sol.y - 23;
  return (limbs: limbs, c: Pt(sol.x, sol.y), err: sol.err);
}

/// One half of a bridge at the right edge of a lane, at height y: two hand
/// holds about level, and two foot steps below them. (type, x, dy)
const List<(HoldType, double, double)> _bridgeHalf = [
  (HoldType.jug, 314, 0),
  (HoldType.jug, 346, 6),
  (HoldType.chip, 326, -44),
  (HoldType.chip, 346, -40),
];

/// Bridges go from [_bridgeFrom] up to [_bridgeTopGap] under the top: the
/// first place with room, then the first one at least [_bridgeEvery] higher.
const double _bridgeFrom = 230, _bridgeEvery = 260, _bridgeTopGap = 150, _bridgeTry = 12;

/// One lane of [base] with the bridge halves on both edges, in the lane's
/// own x (0 to [Wall.right]). [of] maps the holds of [base] to it; [right]
/// and [left] are the bridge halves on each edge, as (y, holds).
class _Template {
  _Template(this.holds, this.of, this.right, this.left);
  final List<Hold> holds;
  final Map<int, int> of;
  final List<(double, List<int>)> right, left;
}

_Template _laneTemplate(ClimbRoute base) {
  final scratch = ClimbRoute(id: base.id, name: base.name, level: base.level, blurb: base.blurb);
  final b = _Builder(scratch), of = <int, int>{};
  for (var k = 1; k < base.holds.length; k++) {
    final h = base.holds[k];
    if (h.t == HoldType.top) continue;
    of[k] = scratch.holds.length - 1;
    if (h.t.wide) {
      b.pushLedge(h);
    } else {
      scratch.holds.add(h);
      b.gridAdd(scratch.holds.length - 1);
    }
  }
  List<(double, List<int>)> edge(bool right) {
    final out = <(double, List<int>)>[];
    for (var y = _bridgeFrom; y + 6 <= base.topY - _bridgeTopGap; y += _bridgeTry) {
      final spots = [
        for (final (t, x, d) in _bridgeHalf) (t, right ? x : Wall.right - x, y + d),
      ];
      if (spots.any((s) => b.nearHold(s.$2, s.$3, 22) || b.onLedge(s.$2, s.$3, 20, 40, 40))) continue;
      final ids = <int>[];
      for (final (t, x, sy) in spots) {
        scratch.holds.add(Hold(t, x, sy));
        b.gridAdd(scratch.holds.length - 1);
        ids.add(scratch.holds.length - 2);
      }
      out.add((y, ids));
      y += _bridgeEvery - _bridgeTry;
    }
    return out;
  }

  final right = edge(true), left = edge(false);
  return _Template(scratch.holds.sublist(1), of, right, left);
}

/// [base] with [n] lanes side by side: lane k is a copy of it moved k wall
/// widths to the right, and every other lane is mirrored left to right. Both
/// edges of every lane get the same bridge halves, so all lanes have the
/// same holds; where two lanes meet, the halves make a bridge. The ground
/// and the top run across all lanes. With n = 1 it is [base] itself.
///
/// Everything comes from [base] and [n], so every device builds the same wall.
ClimbRoute laneWall(ClimbRoute base, int n) {
  if (n <= 1) return base;
  final r = ClimbRoute(
    id: base.id,
    name: base.name,
    level: base.level,
    blurb: base.blurb,
    tutorial: base.tutorial,
    endless: base.endless,
    date: base.date,
  );
  final extra = (n - 1) * Wall.right, g = base.holds[0];
  r.holds[0] = Hold(HoldType.ground, g.x, g.y, g.x2! + extra);
  final t = _laneTemplate(base), size = t.holds.length;
  int world(int lane, int i) => 1 + lane * size + i;
  final lanes = <Lane>[];
  for (var k = 0; k < n; k++) {
    final x0 = Wall.left + k * Wall.right, mirrored = k.isOdd;
    for (final h in t.holds) {
      if (!mirrored) {
        r.holds.add(Hold(h.t, x0 + h.x, h.y, h.x2 == null ? null : x0 + h.x2!));
      } else if (h.x2 == null) {
        r.holds.add(Hold(h.t, x0 + Wall.right - h.x, h.y));
      } else {
        r.holds.add(Hold(h.t, x0 + Wall.right - h.x2!, h.y, x0 + Wall.right - h.x));
      }
    }
    final s = [for (final i in base.startHands) world(k, t.of[i]!)];
    final hands = mirrored ? s.reversed.toList() : s;
    lanes.add(Lane(k, x0, mirrored, hands, _spawns(k, hands, r.holds)));
  }
  // Where an unmirrored lane meets the next one, both show the template's
  // right edge; where a mirrored lane meets the next one, both show its left edge.
  for (var k = 0; k + 1 < n; k++) {
    for (final (y, ids) in k.isEven ? t.right : t.left) {
      r.bridges.add(Bridge(k, y, [for (final i in ids) world(k, i), for (final i in ids) world(k + 1, i)]));
    }
  }
  for (final h in base.holds) {
    if (h.t == HoldType.top) r.holds.add(Hold(HoldType.top, h.x, h.y, h.x2! + extra));
  }
  r.startHands = lanes[0].startHands;
  r.topY = base.topY;
  r._lanes = lanes;
  return r;
}
