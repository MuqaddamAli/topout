// The climber's body: shoulders, hips and head from the torso, arms and legs
// bent with two-bone IK, and the gear that swings (ponytail, chalk bag and
// quickdraws). Nothing here knows about the game; game.dart feeds it.
import 'dart:math' as math;

import 'core.dart';

enum HandStyle { grip, fist, open }

double lerpD(double a, double b, double t) => a + (b - a) * t;

/// A point turned by angle [a] around [c].
Pt rot(Pt c, double a, double dx, double dy) {
  final co = math.cos(a), s = math.sin(a);
  return Pt(c.x + dx * co - dy * s, c.y + dx * s + dy * co);
}

/// Upper arm, forearm, thigh and shin of the original climber. Climbers with
/// a longer or shorter reach have their limbs scaled to match.
const double upperArm = 34, foreArm = 26.5, thigh = 41, shin = 36;

class ArmGeo {
  ArmGeo(this.s, this.m, this.w, this.e, this.dir, this.style, this.kind);
  final Pt s, m, w, e, dir;
  final HandStyle style;
  final HoldType kind;
}

class LegGeo {
  LegGeo(this.h, this.k, this.a, this.e, this.free);
  final Pt h, k, a, e;
  final bool free;
}

class Pose {
  Pose(this.c, this.tilt, this.br, this.lookX, this.lookUp) {
    shoulders = [
      for (final i in [0, 1]) (rot(c, tilt, jointOffset[i][0], jointOffset[i][1])..y += 0.5 * br),
    ];
    hips = [for (final i in [2, 3]) rot(c, tilt, jointOffset[i][0], jointOffset[i][1])];
    final hc = rot(c, tilt, 0, 38.5);
    head = Pt(hc.x + lookX * 0.5, hc.y + lookUp * 1.4 + 0.3 * br);
  }
  final Pt c;
  final double tilt, br, lookX, lookUp;
  late final List<Pt> shoulders;
  late final List<Pt> hips;
  late final Pt head;
  late final List<ArmGeo> arms;
  late final List<LegGeo> legs;
}

/// Bends a two-bone limb from joint [j] toward [e]: elbows go out and down,
/// knees out and up.
({Pt mid, Pt end}) ikJoint(Pt j, Pt e, double a, double b, double side, bool leg) {
  var dx = e.x - j.x, dy = e.y - j.y;
  var d = hypot(dx, dy);
  if (d == 0) d = 1e-6;
  final maxd = a + b - 0.6;
  if (d > maxd) {
    dx *= maxd / d;
    dy *= maxd / d;
    d = maxd;
  }
  d = math.max(d, (a - b).abs() + 0.6);
  final ang = math.acos(clampD((a * a + d * d - b * b) / (2 * a * d), -1, 1)), base = math.atan2(dy, dx);
  final p1 = Pt(j.x + math.cos(base + ang) * a, j.y + math.sin(base + ang) * a);
  final p2 = Pt(j.x + math.cos(base - ang) * a, j.y + math.sin(base - ang) * a);
  double score(Pt p) => side * p.x + (leg ? 0.6 : -0.6) * p.y;
  return (mid: score(p1) > score(p2) ? p1 : p2, end: Pt(j.x + dx, j.y + dy));
}

/// Arm [i] from shoulder [s] to the hand at [e0]. [scale] stretches the bones.
ArmGeo armGeo(int i, Pt s, Pt e0, HandStyle st, HoldType kind, double scale) {
  var dx = e0.x - s.x, dy = e0.y - s.y;
  var d = hypot(dx, dy);
  if (d == 0) d = 1;
  dx /= d;
  dy /= d;
  Pt dir;
  if (st == HandStyle.grip) {
    final bx = dx * 0.4, by = dy * 0.4 + 0.6;
    var bl = hypot(bx, by);
    if (bl == 0) bl = 1;
    dir = Pt(bx / bl, by / bl);
  } else {
    dir = Pt(dx, dy);
  }
  final ik = ikJoint(s, Pt(e0.x - dir.x * 7, e0.y - dir.y * 7), upperArm * scale, foreArm * scale, sideOf[i], false);
  final w = ik.end;
  return ArmGeo(s, ik.mid, w, Pt(w.x + dir.x * 7, w.y + dir.y * 7), dir, st, kind);
}

/// Leg [i] from hip [h] to the foot at [e0]. [kneeShake] moves the knee sideways.
LegGeo legGeo(int i, Pt h, Pt e0, bool free, double scale, [double kneeShake = 0]) {
  final side = sideOf[i];
  final ik = ikJoint(h, Pt(e0.x - side * 3.5, e0.y + 6.5), thigh * scale, shin * scale, side, true);
  final k = ik.mid.copy()..x += kneeShake;
  final a = ik.end;
  return LegGeo(h, k, a, Pt(a.x + side * 3.5, a.y - 6.5), free);
}

/// The pose of climber [k] with the torso at [c] and the hands and feet at
/// [hands] and [feet]. [kneeShake] moves each knee sideways (tired legs).
Pose climberPose(Climber k, Pt c, double tilt, double br, double lookX, double lookUp, List<Pt> hands,
    List<HandStyle> styles, List<HoldType> kinds, List<Pt> feet, List<bool> footFree,
    [List<double> kneeShake = const [0, 0]]) {
  final p = Pose(c, tilt, br, lookX, lookUp);
  p.arms = [for (final i in [0, 1]) armGeo(i, p.shoulders[i], hands[i], styles[i], kinds[i], k.armScale)];
  p.legs = [for (final i in [2, 3]) legGeo(i, p.hips[i - 2], feet[i - 2], footFree[i - 2], k.legScale, kneeShake[i - 2])];
  return p;
}

/// Torso height above the feet when standing straight on a flat ledge.
double standHeight(Climber k) => -jointOffset[2][1] + k.reach[2];

/// Standing tall with fists on the hips, like on the summit (title screen and
/// the climber cards). The torso is at (0, 0).
Pose standingPose(Climber k, {double lookX = -1.2, double lookUp = 0.6}) {
  final p = Pose(Pt(0, 0), 0, 0, lookX, lookUp), h = standHeight(k);
  p.arms = [
    for (final i in [0, 1]) armGeo(i, p.shoulders[i], Pt(sideOf[i] * 21, -23), HandStyle.fist, HoldType.jug, k.armScale),
  ];
  p.legs = [for (final i in [2, 3]) legGeo(i, p.hips[i - 2], Pt(sideOf[i] * 13, -h), false, k.legScale)];
  return p;
}

// ---------------------------------------------------------------- gear

const List<double> qdLen = [10, 12, 10, 12];
const List<List<double>> qdAt = [
  [-12.6, -20.5],
  [-9.4, -21.8],
  [12.6, -20.5],
  [9.4, -21.8],
];

Pt tailRoot(Pose p) {
  final o = rot(Pt(0, 0), p.tilt * 0.5, -p.lookX * 0.8, -8.2);
  return Pt(p.head.x + o.x, p.head.y + o.y);
}

Pt bagAnchor(Pose p) => rot(p.c, p.tilt, 0, -21);
Pt qdAnchor(Pose p, int k) => rot(p.c, p.tilt, qdAt[k][0], qdAt[k][1]);

class QuickdrawState {
  QuickdrawState(this.p, this.prev);
  final Pt p, prev;
}

/// Things that swing: the hair, the chalk bag and the quickdraws. Each is a
/// little verlet chain hanging from the body.
class Gear {
  /// Builds the gear hanging straight down from pose [p]. [links] is how many
  /// points the hair chain has (0 for short hair).
  Gear(Pose p, {int links = 5, this.link = 3.5}) {
    final root = tailRoot(p);
    for (var k = 0; k < links; k++) {
      final q = Pt(root.x, root.y - k * link);
      tail.add(q);
      tailPrev.add(q.copy());
    }
    final ba = bagAnchor(p);
    bag = Pt(ba.x, ba.y - 7);
    bagPrev = bag.copy();
    for (var k = 0; k < qdLen.length; k++) {
      final a = qdAnchor(p, k), q = Pt(a.x, a.y - qdLen[k]);
      qd.add(QuickdrawState(q, q.copy()));
    }
  }

  final double link;
  final List<Pt> tail = [], tailPrev = [];
  late Pt bag, bagPrev;
  final List<QuickdrawState> qd = [];

  static void _verlet(Pt p, Pt prev, double ax, double ay, double h, double damp) {
    final vx = (p.x - prev.x) * damp, vy = (p.y - prev.y) * damp;
    prev.x = p.x;
    prev.y = p.y;
    p.x += vx + ax * h * h;
    p.y += vy + ay * h * h;
  }

  static void _tie(Pt a, Pt p, double len) {
    final dx = p.x - a.x, dy = p.y - a.y;
    var d = hypot(dx, dy);
    if (d == 0) d = 1e-6;
    p.x = a.x + dx / d * len;
    p.y = a.y + dy / d * len;
  }

  /// Steps the swing by [dt] seconds with a sideways [wind].
  void update(Pose p, double dt, double wind) {
    final h = math.min(dt, 1 / 30), damp = math.pow(0.965, h * 60).toDouble();
    if (tail.isNotEmpty) {
      final root = tailRoot(p);
      tail[0]
        ..x = root.x
        ..y = root.y;
      tailPrev[0]
        ..x = root.x
        ..y = root.y;
      for (var k = 1; k < tail.length; k++) {
        _verlet(tail[k], tailPrev[k], wind, -900, h, damp);
      }
      for (var it = 0; it < 3; it++) {
        for (var k = 1; k < tail.length; k++) {
          _tie(tail[k - 1], tail[k], link);
        }
      }
    }
    _verlet(bag, bagPrev, wind * 0.15, -900, h, damp);
    _tie(bagAnchor(p), bag, 7);
    for (var k = 0; k < qd.length; k++) {
      final q = qd[k];
      _verlet(q.p, q.prev, wind * 0.1, -900, h, damp);
      _tie(qdAnchor(p, k), q.p, qdLen[k]);
    }
  }
}
