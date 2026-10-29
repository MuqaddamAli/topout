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

/// Something a standing climber does to show the others how they feel.
/// Cheer and Taunt play once; Aura lasts until they walk or grab a hold.
enum Emote {
  cheer('Cheer', 1.6),
  taunt('Taunt', 2.2),
  aura('Aura', double.infinity);

  const Emote(this.label, this.length);
  final String label;

  /// Seconds it plays.
  final double length;

  /// 1, 2, 3 on the wire (0 is none).
  int get wire => index + 1;
  static Emote? fromWire(num? v) => v != null && v >= 1 && v <= values.length ? values[v.toInt() - 1] : null;
}

/// How long after an emote (or a chat phrase) the next one may start, in seconds.
const double emoteCooldown = 2;

/// Quick chat: the only things you can say (no typing), shown above your
/// climber for everyone for [chatShow] seconds. 1 to 4 on the wire.
const List<String> quickChat = ['Wait for me!', 'Come on!', 'Nice!', 'Over here!'];
const double chatShow = 3;

/// The body, the hands and feet (left hand, right hand, left foot, right
/// foot), the lean and where the head looks of a standing climber.
class StandPose {
  StandPose(this.c, this.ends, this.tilt, this.lookX, [this.lookUp = 0.5]);
  final Pt c;
  final List<Pt> ends;
  final double tilt, lookX, lookUp;
}

double _smooth(double u) {
  final t = clampD(u, 0, 1);
  return t * t * (3 - 2 * t);
}

Pt _mix(Pt a, Pt b, double k) => Pt(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k);

/// Climber [k] standing with the body over [x] on a flat hold at height [y].
/// [facing] is -1 (left) or 1 (right), [phase] the step cycle in radians and
/// [walk] how much they walk, from 0 (still) to 1 (full stride).
StandPose standAt(Climber k, double x, double y,
    {double facing = 1, double phase = 0, double walk = 0, Emote? emote, double emoteT = 0}) {
  if (emote != null) return _emoting(k, x, y, facing, emote, emoteT);
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

/// Climber [k] standing over [x] on a flat hold at [y], [t] seconds into [e].
StandPose _emoting(Climber k, double x, double y, double f, Emote e, double t) {
  final still = standAt(k, x, y, facing: f);
  switch (e) {
    case Emote.cheer:
      // arms go up, two little hops, then the arms come down
      final up = _smooth(t / 0.15) * (1 - _smooth((t - 1.3) / 0.3));
      final hop = t < 0.45 ? 12 * math.sin(t / 0.45 * math.pi) : (t > 0.55 && t < 0.9 ? 7 * math.sin((t - 0.55) / 0.35 * math.pi) : 0.0);
      final c = Pt(x, still.c.y + hop);
      final ends = <Pt>[
        for (var i = 0; i < 2; i++)
          _mix(Pt(c.x + sideOf[i] * 31 * k.armScale, still.ends[i].y + hop),
              Pt(c.x + sideOf[i] * (22 + 3 * math.sin(t * 16 + i)), c.y + 25 + 56 * k.armScale), up),
        for (var i = 2; i < 4; i++) Pt(still.ends[i].x, y + hop * 0.9),
      ];
      return StandPose(c, ends, 0, 0, 0.5 + 0.5 * up);
    case Emote.taunt:
      // a hand on the hip, the other one waves "come on" toward the others; a laugh bounces the body
      final on = _smooth(t / 0.2) * (1 - _smooth((t - 1.9) / 0.3));
      final c = Pt(x, still.c.y + (math.sin(t * 13).abs() * 1.8 - 0.9) * on);
      final wave = f > 0 ? 1 : 0, hip = 1 - wave;
      final ends = [...still.ends];
      ends[hip] = _mix(still.ends[hip], Pt(c.x + sideOf[hip] * 21, c.y - 23), on);
      ends[wave] = _mix(still.ends[wave], Pt(c.x + f * (32 + 7 * math.sin(t * 10)), c.y + 34 + 4 * math.cos(t * 10)), on);
      return StandPose(c, ends, -f * 0.04 * on, f * 2.4 * on, 0.5 + 0.25 * math.sin(t * 13) * on);
    case Emote.aura:
      // down onto the back, legs out (one knee up), hands behind the head, the head tilted
      final down = _smooth(t / 0.7);
      final c = Pt(x, y + 19);
      final lying = [
        Pt(x - f * 45, y + 23),
        Pt(x - f * 43, y + 14),
        Pt(x + f * (f > 0 ? 100 : 66), y + 3),
        Pt(x + f * (f > 0 ? 66 : 100), y + 3),
      ];
      return StandPose(_mix(still.c, c, down), [for (var i = 0; i < 4; i++) _mix(still.ends[i], lying[i], down)],
          f * math.pi / 2 * down, f * 1.6 * down, 0.5 - 0.9 * down);
  }
}
