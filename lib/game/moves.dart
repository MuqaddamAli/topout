// Each climber's own way of moving, only for show (the rules never see it):
// what they do while they hang still for a while, how they celebrate at the
// top, and how they flail in a fall. Ada looks around, Rio sways lazily and
// takes in the view, Mei studies the holds above her, and Kai can't keep
// still.
import 'dart:math' as math;

import 'core.dart';

double _smooth(double a, double b, double x) {
  final t = clampD((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/// A soft bump from 0 up to 1 and back over [len] seconds, starting at [at].
double _bump(double t, double at, double len) {
  final u = (t - at) / len;
  return u <= 0 || u >= 1 ? 0 : math.sin(u * math.pi);
}

/// How the body and the head move for climber [id] after holding still for
/// [still] seconds, at clock time [t]: a shift of the body (units), extra
/// lean, and where the head looks (added to the usual).
typedef Fidget = ({double dx, double dy, double tilt, double lookX, double lookUp});

Fidget fidget(String id, double still, double t) {
  final k = _smooth(2.5, 3.8, still);
  if (k <= 0) return (dx: 0, dy: 0, tilt: 0, lookX: 0, lookUp: 0);
  switch (id) {
    case 'rio':
      // a slow, lazy sway, looking out over the valley
      return (
        dx: math.sin(t * 0.8) * 2.2 * k,
        dy: 0,
        tilt: math.sin(t * 0.8) * 0.03 * k,
        lookX: math.sin(t * 0.45) * 2.6 * k,
        lookUp: -0.3 * k,
      );
    case 'mei':
      // she studies the holds above, then settles her weight now and then
      final c = t % 5;
      return (dx: 0, dy: -0.9 * _bump(c, 3.6, 0.7) * k, tilt: 0, lookX: math.sin(t * 0.7) * 0.9 * k, lookUp: 0.55 * k);
    case 'kai':
      // bounces on the toes in bursts, glancing around
      final c = t % 4.5, burst = c < 1.2 ? (math.sin(c * 9)).abs() * 2.2 * _smooth(0, 0.15, c) * _smooth(1.2, 1.0, c) : 0.0;
      return (dx: 0, dy: burst * k, tilt: 0, lookX: (math.sin(t * 0.9) > 0 ? 1.8 : -1.8) * k, lookUp: 0.2 * k);
    default:
      // Ada: looks up the route, then left and right
      final c = t % 7;
      return (
        dx: math.sin(t * 1.1) * 0.7 * k,
        dy: 0,
        tilt: 0,
        lookX: (2.2 * _bump(c, 2.4, 1.6) - 2.2 * _bump(c, 4.2, 1.6)) * k,
        lookUp: 0.7 * _bump(c, 0.2, 2) * k,
      );
  }
}

/// Where hand [i] of climber [id] goes while celebrating at the top, from the
/// body at ([x], [y]), [t] seconds into it. Also whether it makes a fist.
({double x, double y, bool fist}) cheerHand(String id, int i, double x, double y, double t) {
  final s = sideOf[i];
  switch (id) {
    case 'rio':
      // arms wide and high
      return (x: x + s * 52, y: y + 66 + math.sin(t * 3 + i) * 2, fist: false);
    case 'mei':
      // claps above her head
      final clap = (math.sin(t * 8)).abs();
      return (x: x + s * (3 + 9 * clap), y: y + 82, fist: false);
    case 'kai':
      // both arms straight up
      return (x: x + s * 15, y: y + 94 + math.sin(t * 10 + i) * 2, fist: true);
    default:
      // Ada: a fist pump with the right hand, the left on the hip
      if (i == 0) return (x: x - 21, y: y - 23, fist: true);
      final pump = math.max(0.0, math.sin(t * 7));
      return (x: x + 18, y: y + 70 + pump * 18, fist: true);
  }
}

/// How high climber [id] hops while celebrating, [t] seconds after the pull-up.
double cheerHop(String id, double t) => switch (id) {
      'kai' => 16 * _bump(t, 0.05, 0.42) + 10 * _bump(t, 0.6, 0.36),
      'mei' => 6 * _bump(t, 0.1, 0.3) + 6 * _bump(t, 0.5, 0.3),
      'rio' => 2.5 * _smooth(0, 0.4, t),
      _ => 7 * _bump(t, 0.1, 0.35),
    };

/// Where limb [i] of climber [id] flails while falling with nothing to catch:
/// an offset from its shoulder or hip ([jx], [jy]) at clock time [t].
({double x, double y}) flail(String id, int i, double jx, double jy, double t, double reach) {
  final s = sideOf[i], hand = isHand[i];
  switch (id) {
    case 'rio':
      // windmills with those long arms
      if (hand) {
        final a = t * 9 + (i == 0 ? 0 : math.pi);
        return (x: jx + s * 10 + math.cos(a) * reach * 0.7, y: jy + 14 + math.sin(a) * reach * 0.7);
      }
      return (x: jx + s * 16, y: jy - 58);
    case 'mei':
      // tucks in
      return hand ? (x: jx + s * 6, y: jy - 10) : (x: jx + s * 12, y: jy - 34);
    case 'kai':
      // a starfish
      return hand ? (x: jx + s * 46, y: jy + 34) : (x: jx + s * 34, y: jy - 50);
    default:
      // Ada: arms flail
      if (hand) return (x: jx + s * 26 + math.sin(t * 14 + i * 2) * 10, y: jy + 36 + math.cos(t * 14 + i * 2) * 8);
      return (x: jx + s * 16 + math.sin(t * 11 + i) * 4, y: jy - 52);
  }
}

/// One step of a critically damped spring: [x] moves toward [to] with
/// velocity [v], quickly and smoothly and without overshoot. [w] is how
/// stiff it is (per second). Exact for any time step.
(double, double) spring(double x, double v, double to, double w, double dt) {
  final y = x - to, e = math.exp(-w * dt), c = v + w * y;
  return (to + (y + c * dt) * e, (v - w * c * dt) * e);
}
