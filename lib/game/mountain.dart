// The mountain around a route: which band of it a height is in, the hour,
// and how much snow lies there. The scene takes its colours from here and
// the game its snow; nothing here draws.
//
// The hour passes as you climb: every route starts on a clear afternoon and
// reaches dusk near its top. Only the hard route goes on into the night over
// its upper part, and the Daily Wall turns to night high up.
import 'dart:math' as math;

import 'core.dart';
import 'field_book.dart';

double _smooth(double a, double b, double x) {
  final t = clampD((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/// Where a height of the Daily Wall starts each band, in world units. The
/// icefall starts at the snow line.
const double dailyCliff = 900, dailyIce = 2000, dailySummit = 4200;

/// The hour as a number: 1 is day, 2 is dusk, 3 is night (the [DayTime]
/// index; 0, dawn, is not used while you climb).
typedef Hour = double;

class Mountain {
  const Mountain._();

  /// How far up route [r] height [y] is, 0 at the ground and 1 at the top.
  /// The Daily Wall has no top: it maps its bands onto the same scale.
  static double progress(ClimbRoute r, double y) {
    if (!r.endless) return clampD(y / math.max(1.0, r.topY), 0, 1);
    if (y < dailyCliff) return 0.25 * y / dailyCliff;
    if (y < dailyIce) return 0.25 + 0.25 * (y - dailyCliff) / (dailyIce - dailyCliff);
    if (y < dailySummit) return 0.5 + 0.25 * (y - dailyIce) / (dailySummit - dailyIce);
    return math.min(1.0, 0.75 + 0.25 * (y - dailySummit) / 3000);
  }

  /// The hour at height [y] of route [r].
  static Hour hourAt(ClimbRoute r, double y) {
    final p = progress(r, y);
    if (r.endless) return 1 + _smooth(600, 3000, y) + _smooth(4200, 7000, y);
    if (r.level >= 3) return 1 + _smooth(0.05, 0.5, p) + _smooth(0.55, 0.92, p);
    return 1 + _smooth(0.08, 0.96, p);
  }

  /// The colours of one band between two hours.
  static Env _at(Zone z, Hour h) {
    final a = h.floor().clamp(0, 3), b = math.min(3, a + 1);
    return Env.lerp(Env.of(z, DayTime.values[a]), Env.of(z, DayTime.values[b]), h - a);
  }

  /// The mountain's colours at progress [p] and hour [h], blended across
  /// about 5% on each side of a band's edge so the sky never jumps.
  static Env envAt(double p, Hour h) {
    const edges = [0.25, 0.5, 0.75];
    for (var k = 0; k < edges.length; k++) {
      final d = p - edges[k];
      if (d.abs() < 0.05) {
        final t = _smooth(-0.05, 0.05, d);
        return Env.lerp(_at(Zone.values[k], h), _at(Zone.values[k + 1], h), t);
      }
    }
    return _at(zoneAt(p), h);
  }

  static Env env(ClimbRoute r, double y) => envAt(progress(r, y), hourAt(r, y));

  /// How dark it is outside the headlamp (0 to 1).
  static double night(Hour h) => _smooth(2.15, 2.95, h);

  /// How much frost sits at the edges of the screen (0 to 1), between the
  /// table's bands and hours.
  static double frost(ClimbRoute r, double y) {
    final p = progress(r, y), h = hourAt(r, y);
    final z = clampD(p * 4 - 0.5, 0, 3), z0 = z.floor(), z1 = math.min(3, z0 + 1);
    final a = h.floor().clamp(1, 3), b = math.min(3, a + 1);
    double f(int zi, int hi) => frostAt(Zone.values[zi], DayTime.values[hi]);
    final lo = f(z0, a) + (f(z0, b) - f(z0, a)) * (h - a), hi = f(z1, a) + (f(z1, b) - f(z1, a)) * (h - a);
    return lo + (hi - lo) * (z - z0);
  }

  /// How much snow lies and falls at height [y] (0 to 1). It starts gently
  /// in the icefall band and gets heavier toward the top.
  static double snow(ClimbRoute r, double y) {
    if (r.endless) return _smooth(dailyIce - 300, dailySummit + 1500, y);
    final p = progress(r, y);
    return _smooth(0.45, 1.0, p);
  }

  /// A number from 0 to 1 that stays the same for hold [k] of route [r].
  /// Every device gets the same answer (String.hashCode differs on the web).
  static double holdHash(ClimbRoute r, int k) {
    var s = 0;
    for (final u in r.id.codeUnits) {
      s = (imul32(s, 31) + u) & 0xffffffff;
    }
    var h = (imul32(k + 0x9e37, 0x85ebca6b) ^ s) & 0xffffffff;
    h = imul32((h ^ (h >> 13)) & 0xffffffff, 0xc2b2ae35);
    return (((h ^ (h >> 16)) & 0xffff)) / 0x10000;
  }

  /// Whether hold [k] of [r] starts the climb covered in snow. More holds
  /// are covered the higher you go; ledges, the ground and the top carry snow
  /// too, but you stand on those, so it never makes them slick.
  static bool snowCovered(ClimbRoute r, int k) {
    final h = r.holds[k];
    if (h.t.rest) return false;
    final s = snow(r, h.y);
    return s > 0.04 && holdHash(r, k) < 0.25 + 0.75 * s;
  }
}
