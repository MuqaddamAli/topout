import 'dart:math' as math;

/// Chalk puffs, rock dust, falling pebbles, snow knocked off holds, the
/// sparks of a lamp, and breath in the cold.
enum PartKind { chalk, dust, pebble, snow, spark, breath }

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.r, this.max, this.kind);
  double x, y, vx, vy;
  final double r, max;
  final PartKind kind;
  double t = 0;
}

/// A speck of dust floating in the evening light. Positions are fractions of the screen.
class Mote {
  Mote(this.x, this.y, this.vx, this.vy, this.r, this.ph, this.f);
  double x, y;
  final double vx, vy, r, ph, f;
}

/// A bird in a far-off flock: [u] runs across the screen (0 to 1) at speed
/// [v], [h] is its height, [ph] its wing beat and [s] its size.
class Bird {
  Bird(this.u, this.h, this.v, this.ph, this.s);
  double u, ph;
  final double h, v, s;
}

/// The small things that move by themselves: particles, dust motes and
/// birds. They are only for show and never change the climb.
class Effects {
  Effects() {
    for (var k = 0; k < 18; k++) {
      motes.add(Mote(_rand.nextDouble(), _rand.nextDouble(), (_rand.nextDouble() - 0.5) * 0.012, -0.004 - _rand.nextDouble() * 0.01,
          0.7 + _rand.nextDouble() * 1.3, _rand.nextDouble() * 6.3, 0.6 + _rand.nextDouble() * 1.4));
    }
  }

  final _rand = math.Random();
  final List<Particle> parts = [];
  final List<Mote> motes = [];
  final List<Bird> birds = [];
  double _nextFlock = 4;

  /// [n] particles flying out from x, y.
  void burst(double x, double y, PartKind kind, int n) {
    for (var k = 0; k < n; k++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final sp = kind == PartKind.pebble ? 20 + _rand.nextDouble() * 30 : 14 + _rand.nextDouble() * 38;
      parts.add(Particle(
        x,
        y,
        math.cos(a) * sp,
        kind == PartKind.pebble ? 10 + _rand.nextDouble() * 25 : (math.sin(a)).abs() * sp * 0.8,
        kind == PartKind.chalk ? 1.4 + _rand.nextDouble() * 2.2 : 1 + _rand.nextDouble() * 2,
        0.5 + _rand.nextDouble() * 0.5,
        kind,
      ));
    }
  }

  void update(double dt, double clock) {
    _updateParts(dt);
    _updateBirds(dt);
    _updateMotes(dt, clock);
  }

  void _updateParts(double dt) {
    for (final p in parts) {
      p.t += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.kind == PartKind.pebble) {
        p.vy -= 700 * dt;
      } else if (p.kind == PartKind.snow) {
        // a puff of snow knocked off a hold: it spreads, then drifts down
        p.vx *= 0.9;
        p.vy = p.vy * 0.9 - 40 * dt;
        p.x += math.sin(p.t * 5 + p.r * 3) * 0.12;
      } else if (p.kind == PartKind.breath) {
        // breath in the cold: it drifts out, rises a little and thins away
        p.vx *= 0.95;
        p.vy = p.vy * 0.95 + 10 * dt;
      } else {
        p.vx *= 0.9;
        p.vy = p.vy * 0.9 + (p.kind == PartKind.chalk ? 6 : -4) * dt;
      }
    }
    parts.removeWhere((p) => p.t >= p.max);
  }

  void _updateMotes(double dt, double clock) {
    for (final m in motes) {
      m.x += (m.vx + math.sin(clock * 0.5 + m.ph) * 0.006) * dt;
      m.y += m.vy * dt;
      if (m.x < -0.05) m.x += 1.1;
      if (m.x > 1.05) m.x -= 1.1;
      if (m.y < -0.05) m.y += 1.1;
    }
  }

  void _updateBirds(double dt) {
    _nextFlock -= dt;
    if (_nextFlock <= 0) {
      _nextFlock = 14 + _rand.nextDouble() * 16;
      final dir = _rand.nextDouble() < 0.5 ? 1.0 : -1.0, n = 3 + _rand.nextInt(3);
      final h = 150 + _rand.nextDouble() * 220, sp = 22 + _rand.nextDouble() * 14;
      for (var k = 0; k < n; k++) {
        birds.add(Bird(
          dir > 0 ? -0.1 - k * 0.03 : 1.1 + k * 0.03,
          h + (k.isOdd ? -10 : 10) * (k / 2).ceil() + _rand.nextDouble() * 6,
          dir * sp / 400,
          _rand.nextDouble() * 6,
          2.6 + _rand.nextDouble() * 1.2,
        ));
      }
    }
    for (final b in birds) {
      b.u += b.v * dt;
      b.ph += dt * 9;
    }
    birds.removeWhere((b) => b.u <= -0.3 || b.u >= 1.3);
  }
}
