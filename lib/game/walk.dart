// Standing and walking (online only): where the body, hands and feet are for
// a climber standing on a flat hold (the ground, a ledge or the top), and the
// steps they take walking along it. Your own climber and the other players'
// climbers are both drawn from this, so a walk looks the same everywhere.
import 'dart:math' as math;

import 'body.dart';
import 'core.dart';

/// Walking speed, cm/s: a calm stroll.
const double walkSpeed = 55;

/// One full step cycle (left and right foot) covers this many cm.
const double strideLength = 52;

/// How far from a ledge's end the body may walk (the feet stay on it).
const double standMargin = 14;

/// The body, the hands and feet (left hand, right hand, left foot, right
/// foot) and the lean of a standing climber.
class StandPose {
  StandPose(this.c, this.ends, this.tilt, this.lookX);
  final Pt c;
  final List<Pt> ends;
  final double tilt, lookX;
}

/// Climber [k] standing with the body over [x] on a flat hold at height [y].
/// [facing] is -1 (left) or 1 (right), [phase] the step cycle in radians and
/// [walk] how much they walk, from 0 (still) to 1 (full stride).
StandPose standAt(Climber k, double x, double y, {double facing = 1, double phase = 0, double walk = 0}) {
  // upright with the legs almost straight, a little lower at each step
  final bob = walk * 1.6 * (1 - math.cos(phase * 2)) / 2;
  final c = Pt(x, y + standHeight(k) + 2.5 * k.legScale - bob);
  final ends = <Pt>[];
  for (var i = 0; i < 2; i++) {
    // arms hang loose, a little out to the sides, and swing against the legs
    final swing = -facing * math.sin(phase + i * math.pi) * 7 * walk;
    ends.add(Pt(c.x + sideOf[i] * 31 * k.armScale + swing, c.y + jointOffset[i][1] - 52 * k.armScale + swing.abs() * 0.2));
  }
  for (var i = 0; i < 2; i++) {
    // the foot ahead swings through and lifts, the other one is on the hold
    final s = math.sin(phase + i * math.pi), lift = math.max(0.0, math.cos(phase + i * math.pi));
    ends.add(Pt(x + sideOf[i] * 12 + facing * s * strideLength / 4 * walk, y + lift * 5 * walk));
  }
  return StandPose(c, ends, facing * 0.03 * walk, facing * 1.8 * walk);
}

/// The x range the body can walk on hold [h] of [r]: the whole wall on the
/// ground, and up to [standMargin] from the ends on a ledge or the top.
({double lo, double hi}) walkRange(ClimbRoute r, Hold h) => h.t == HoldType.ground
    ? (lo: r.wallLeft + 20, hi: r.wallRight - 20)
    : (lo: h.x + standMargin, hi: h.x2! - standMargin);
