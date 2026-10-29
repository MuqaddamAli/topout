// Art that is made once: the rock texture (with its light and dark facets),
// the clouds, stars and grass. Everything is drawn in code, no image files.
// Whatever can be drawn ahead of time is, so a frame needs few draw calls.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'baked.dart';
import 'core.dart';
import 'palette.dart';

export 'baked.dart';

/// A 2D affine transform as the 4x4 matrix Flutter wants.
Float64List affine(double a, double b, double c, double d, double e, double f) =>
    Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1]);

Float64List scaleMatrix(double s) => affine(s, 0, 0, s, 0, 0);

/// An ellipse, turned by [rotation] radians, as a path.
ui.Path ellipsePath(double x, double y, double rx, double ry, [double rotation = 0]) {
  final p = ui.Path()..addOval(ui.Rect.fromCenter(center: ui.Offset.zero, width: rx * 2, height: ry * 2));
  final co = math.cos(rotation), s = math.sin(rotation);
  return p.transform(affine(co, s, -s, co, x, y));
}

/// Part of an ellipse from angle [start] to [end] (like the web canvas `ellipse`).
ui.Path ellipseArc(double x, double y, double rx, double ry, double rotation, double start, double end,
    {bool anticlockwise = false}) {
  var sweep = end - start;
  if (anticlockwise) {
    sweep = -((start - end) % (math.pi * 2));
  } else {
    sweep = sweep % (math.pi * 2);
  }
  final p = ui.Path()..addArc(ui.Rect.fromCenter(center: ui.Offset.zero, width: rx * 2, height: ry * 2), start, sweep);
  final co = math.cos(rotation), s = math.sin(rotation);
  return p.transform(affine(co, s, -s, co, x, y));
}

ui.RRect roundRect(double x, double y, double w, double h, double r) =>
    ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(x, y, w, h), ui.Radius.circular(r));

/// Dashes along the straight line from (ax, ay) to (bx, by): [on] long, [off] apart.
ui.Path dashLine(double ax, double ay, double bx, double by, double on, double off, [ui.Path? into]) {
  final out = into ?? ui.Path();
  final dx = bx - ax, dy = by - ay, len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return out;
  final ux = dx / len, uy = dy / len;
  for (var d = 0.0; d < len; d += on + off) {
    final e = math.min(d + on, len);
    out
      ..moveTo(ax + ux * d, ay + uy * d)
      ..lineTo(ax + ux * e, ay + uy * e);
  }
  return out;
}

/// A dashed circle: arcs [on] long, [off] apart (both measured along the edge).
ui.Path dashCircle(double cx, double cy, double r, double on, double off) {
  final out = ui.Path(), rect = ui.Rect.fromCircle(center: ui.Offset(cx, cy), radius: r);
  final n = math.max(1, (math.pi * 2 * r / (on + off)).floor()), step = math.pi * 2 / n;
  final sweep = step * on / (on + off);
  for (var k = 0; k < n; k++) {
    out.addArc(rect, k * step, sweep);
  }
  return out;
}

class Star {
  const Star(this.x, this.y, this.s, this.p);
  final double x, y, s, p;
}

class Tuft {
  const Tuft(this.x, this.h, this.n, this.lean);
  final double x, h, lean;
  final int n;
}

class Pebble {
  const Pebble(this.x, this.y, this.rx, this.ry, this.light);
  final double x, y, rx, ry;
  final bool light;
}

class CloudSprite {
  CloudSprite(this.baked, this.w, this.h);
  final Baked baked;
  final double w, h;
  ui.Image get image => baked.image;
}

/// Where each cloud floats. h: height above the summit (world units),
/// p: parallax, k: size, v: drift speed, a: opacity.
class CloudPlace {
  const CloudPlace(this.s, this.x, this.h, this.p, this.k, this.v, this.a);
  final int s;
  final double x, h, p, k, v, a;
}

class _CloudPal {
  const _CloudPal(this.top, this.mid, this.warm, this.rim, this.edge, this.hi, this.glow, this.under);
  final ui.Color top, mid, warm, rim, edge, hi, glow, under;
}

/// The shapes in the rock tile, made once from a seed: the rock and its
/// snow are both drawn from them.
class _RockShape {
  _RockShape(Rng r) {
    const size = Art.tileSize;
    // planes on a jittered grid that wraps around (cells of ~80 units)
    const n = 7, cell = size / n;
    final pts = [
      for (var j = 0; j < n; j++)
        [for (var i = 0; i < n; i++) ui.Offset(i * cell + (r() - 0.5) * cell * 0.8, j * cell + (r() - 0.5) * cell * 0.8)],
    ];
    ui.Offset at(int i, int j) => pts[j % n][i % n] + ui.Offset((i ~/ n) * size, (j ~/ n) * size);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final a = at(i, j), b = at(i + 1, j), cc = at(i, j + 1), d = at(i + 1, j + 1), flip = r() < 0.5;
        for (final t in flip ? [[a, b, d], [a, d, cc]] : [[a, b, cc], [b, d, cc]]) {
          facets.add((
            path: ui.Path()
              ..moveTo(t[0].dx, t[0].dy)
              ..lineTo(t[1].dx, t[1].dy)
              ..lineTo(t[2].dx, t[2].dy)
              ..close(),
            shade: (r() * 2 - 1) * 0.85 + 0.15,
          ));
        }
      }
    }
    // beds of rock, nearly level, each with its own gentle wave
    for (var i = 0; i < 9; i++) {
      final yc = (i + r() * 0.8) * size / 9, x0 = r() * size, len = 260 + r() * 520;
      final a1 = 3 + r() * 9, l1 = 180 + r() * 260, f1 = r() * 6, a2 = 1 + r() * 3, l2 = 40 + r() * 60, tiltK = (r() - 0.5) * 0.08;
      final path = ui.Path();
      for (var x = x0; x <= x0 + len; x += 8) {
        final y = yc + a1 * math.sin(x / l1 * math.pi * 2 + f1) + a2 * math.sin(x / l2 * math.pi * 2) + (x - x0) * tiltK;
        x == x0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      beds.add((path: path, x0: x0, x1: x0 + len, w: 0.7 + r() * 0.7, k: 0.6 + r() * 0.4));
    }
    // cracks, mostly up and down
    for (var i = 0; i < 18; i++) {
      var x = r() * size, y = r() * size, ang = math.pi / 2 + (r() - 0.5) * 1.1;
      final path = ui.Path()..moveTo(x, y);
      final steps = 5 + (r() * 9).floor();
      for (var k = 0; k < steps; k++) {
        ang += (r() - 0.5) * 0.7;
        final l = 9 + r() * 20;
        x += math.cos(ang) * l;
        y += math.sin(ang) * l;
        path.lineTo(x, y);
      }
      cracks.add((path: path, w: 1.1 + r() * 1.4));
    }
    for (var i = 0; i < 150; i++) {
      pits.add((at: ui.Offset(r() * size, r() * size), r: 1.1 + r() * 2.6));
    }
  }

  final List<({ui.Path path, double shade})> facets = [];
  final List<({ui.Path path, double x0, double x1, double w, double k})> beds = [];
  final List<({ui.Path path, double w})> cracks = [];
  final List<({ui.Offset at, double r})> pits = [];
}

class Art {
  Art._();
  static final Art instance = Art._();

  /// Grass and pebbles reach this far right, past the widest wall with lanes.
  static const double groundRight = Wall.left + maxLanes * Wall.right + 420;

  bool _ready = false;
  late final Baked tile, snowTile;

  /// A soft round snowflake, a strip of mist and a painted trail blaze.
  late final Baked flake, mist, blaze;
  late final List<CloudSprite> clouds;
  late final List<Star> stars;
  late final List<Tuft> tufts;
  late final List<Pebble> pebbles;

  static const List<CloudPlace> cloudPlaces = [
    // sorted far to near (by parallax)
    CloudPlace(7, 0.05, 300, 0.3, 0.9, 1.5, 0.75),
    CloudPlace(5, 0.45, 340, 0.3, 0.45, 2.6, 0.7),
    CloudPlace(4, 0.78, 265, 0.34, 0.5, 2.3, 0.75),
    CloudPlace(3, 0.15, 215, 0.36, 0.55, 2.0, 0.8),
    CloudPlace(2, 0.6, 390, 0.4, 0.75, 2.8, 0.95),
    CloudPlace(1, 0.3, 235, 0.42, 0.85, 3.8, 1),
    CloudPlace(0, 0.92, 175, 0.46, 0.8, 3.2, 1),
    CloudPlace(6, 0.62, 150, 0.5, 1.0, 1.2, 0.9),
  ];

  /// Builds everything on first use. Needs a running Flutter binding.
  void ensure() {
    if (_ready) return;
    _ready = true;
    tile = _makeTile();
    snowTile = _makeSnowTile();
    flake = _makeFlake();
    mist = _makeMist();
    blaze = _makeBlaze();
    // clouds in grey: the scene tints them with the hour's light
    const near = _CloudPal(
      ui.Color(0xFFFFFFFF), ui.Color(0xFFEDEEF2), ui.Color(0xFFDADCE3), ui.Color(0xFFC9CCD6),
      ui.Color.fromRGBO(120, 124, 140, 0.16), ui.Color.fromRGBO(255, 255, 255, 0.45),
      ui.Color.fromRGBO(255, 255, 255, 0.18), ui.Color.fromRGBO(214, 218, 228, 0.6));
    const far = _CloudPal(
      ui.Color(0xFFF7F8FA), ui.Color(0xFFE6E8EE), ui.Color(0xFFD6D9E1), ui.Color(0xFFCCD0DA),
      ui.Color.fromRGBO(130, 134, 150, 0.14), ui.Color.fromRGBO(255, 255, 255, 0.35),
      ui.Color.fromRGBO(255, 255, 255, 0.14), ui.Color.fromRGBO(220, 224, 232, 0.45));
    const streak = _CloudPal(
      ui.Color(0xFFFFFFFF), ui.Color(0xFFF0F1F4), ui.Color(0xFFE2E4EA), ui.Color(0xFFD5D8E0),
      ui.Color.fromRGBO(140, 144, 160, 0.2), ui.Color.fromRGBO(255, 255, 255, 0.35),
      ui.Color.fromRGBO(255, 255, 255, 0.2), ui.Color.fromRGBO(230, 232, 240, 0.5));
    clouds = [
      _makeCloud(11, 250, 110, near), _makeCloud(23, 300, 120, near), _makeCloud(37, 220, 100, near),
      _makeCloud(41, 200, 86, far), _makeCloud(53, 240, 96, far), _makeCloud(67, 180, 78, far),
      _makeCloud(71, 380, 56, streak, streak: true), _makeCloud(83, 320, 50, streak, streak: true),
    ];
    final rs = Rng(5);
    stars = [for (var i = 0; i < 60; i++) Star(rs(), rs(), 0.6 + rs() * 1.4, rs() * 6)];
    final rg = Rng(31);
    final t = <Tuft>[];
    for (var x = -420.0; x < 780; x += 9 + rg() * 16) {
      t.add(Tuft(x, 5 + rg() * 9, 2 + (rg() * 3).floor(), (rg() - 0.5) * 0.8));
    }
    tufts = t;
    pebbles = [
      for (var i = 0; i < 70; i++) Pebble(-420 + rg() * 1200, -8 - rg() * 60, 1.5 + rg() * 4, 1 + rg() * 2.2, rg() > 0.5),
    ];
    // more of both for a wall with lanes, after the ones above so those stay the same
    for (var x = t.last.x + 9 + rg() * 16; x < groundRight; x += 9 + rg() * 16) {
      t.add(Tuft(x, 5 + rg() * 9, 2 + (rg() * 3).floor(), (rg() - 0.5) * 0.8));
    }
    final more = ((groundRight - 780) / 1200 * 70).round();
    pebbles.addAll([
      for (var i = 0; i < more; i++) Pebble(780 + rg() * (groundRight - 780), -8 - rg() * 60, 1.5 + rg() * 4, 1 + rg() * 2.2, rg() > 0.5),
    ]);
  }

  /// Size of the rock texture in pixels. It is drawn at 0.55 units per pixel,
  /// so it repeats every ~5.6 m.
  static const double tileSize = 1024;

  /// The rock tile's average brightness. The scene tints it by multiplying
  /// with the mountain's rock colour divided by this, so on average the wall
  /// is exactly that colour.
  static const double tileMean = 0.72;

  /// The rock in grey: soft blotches, planes with lit and shaded edges, beds
  /// of rock with little shelves, cracks, pits and grit. Everything wraps
  /// around, so the texture tiles without seams and the wall costs one
  /// textured rectangle per frame. The scene draws it upside down (the world
  /// has y up), so "up" here is +y and the light comes from the lower left.
  Baked _makeTile() => bake(tileSize.toInt(), tileSize.toInt(), (c) => _drawTile(c, _rock));

  /// Snow lying on the same rock: on the shelves, in the cracks and pits.
  /// Drawn over the rock with the same scale, so it sits exactly on them.
  Baked _makeSnowTile() => bake(tileSize.toInt(), tileSize.toInt(), (c) => _drawSnowTile(c, _rock));

  late final _RockShape _rock = _RockShape(Rng(99));

  /// Draws [draw] at every copy of the tile that [bounds] touches, so shapes
  /// that cross an edge come back on the other side.
  static void _wrapped(ui.Canvas c, ui.Rect bounds, void Function(ui.Offset o) draw) {
    const size = tileSize;
    for (var ox = -size; ox <= size; ox += size) {
      for (var oy = -size; oy <= size; oy += size) {
        if (bounds.shift(ui.Offset(ox, oy)).overlaps(const ui.Rect.fromLTWH(0, 0, size, size))) draw(ui.Offset(ox, oy));
      }
    }
  }

  void _drawTile(ui.Canvas c, _RockShape rock) {
    final r = Rng(7);
    const size = tileSize;
    const whole = ui.Rect.fromLTWH(0, 0, size, size);
    c.drawRect(whole, ui.Paint()..color = rgba(184, 184, 184, 1));
    final p = ui.Paint();
    // big soft light and dark patches
    for (var i = 0; i < 90; i++) {
      final x = r() * size, y = r() * size, rad = 60 + r() * 200, light = r() > 0.45;
      final col = light ? rgba(255, 255, 255, 0.1 + r() * 0.1) : rgba(20, 20, 20, 0.12 + r() * 0.12);
      _wrapped(c, ui.Rect.fromCircle(center: ui.Offset(x, y), radius: rad), (o) {
        final box = ui.Rect.fromCircle(center: ui.Offset(x, y) + o, radius: rad);
        p.shader = ui.Gradient.radial(box.center, rad, [col, col.withAlpha(0)]);
        c.drawRect(box.intersect(whole), p);
      });
    }
    p.shader = null;
    // planes: each one turned a little toward or away from the light
    for (final f in rock.facets) {
      p.color = f.shade > 0 ? rgba(255, 255, 255, f.shade * 0.12) : rgba(0, 0, 0, -f.shade * 0.15);
      _wrapped(c, f.path.getBounds(), (o) => c.drawPath(f.path.shift(o), p));
    }
    // their edges: a dark line on the shaded side, a light one on the lit side
    final edge = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeJoin = ui.StrokeJoin.round;
    for (final f in rock.facets) {
      _wrapped(c, f.path.getBounds().inflate(2), (o) {
        c.drawPath(f.path.shift(o + const ui.Offset(0.9, -0.9)), edge
          ..strokeWidth = 1.6
          ..color = rgba(0, 0, 0, 0.06));
        c.drawPath(f.path.shift(o + const ui.Offset(-0.6, 0.6)), edge
          ..strokeWidth = 1
          ..color = rgba(255, 255, 255, 0.045));
      });
    }
    // beds: a lit shelf on top, a dark shadow under it
    for (final b in rock.beds) {
      _wrapped(c, b.path.getBounds().inflate(6), (o) {
        final path = b.path.shift(o);
        p
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..shader = ui.Gradient.linear(ui.Offset(b.x0 + o.dx, 0), ui.Offset(b.x1 + o.dx, 0),
              [rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.32 * b.k), rgba(0, 0, 0, 0.32 * b.k), rgba(0, 0, 0, 0)], [0, 0.15, 0.85, 1])
          ..strokeWidth = 2.8 * b.w;
        c.drawPath(path, p);
        p
          ..shader = ui.Gradient.linear(ui.Offset(b.x0 + o.dx, 0), ui.Offset(b.x1 + o.dx, 0),
              [rgba(255, 255, 255, 0), rgba(255, 255, 255, 0.22 * b.k), rgba(255, 255, 255, 0.22 * b.k), rgba(255, 255, 255, 0)],
              [0, 0.15, 0.85, 1])
          ..strokeWidth = 1.6 * b.w;
        c.drawPath(path.shift(ui.Offset(0, 2.4 * b.w)), p);
      });
    }
    p
      ..shader = null
      ..style = ui.PaintingStyle.fill;
    // cracks: dark, with a light lip on the lit side
    final crack = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    for (final k in rock.cracks) {
      _wrapped(c, k.path.getBounds().inflate(4), (o) {
        c.drawPath(k.path.shift(o + const ui.Offset(-1.1, 1.1)), crack
          ..strokeWidth = k.w * 0.8
          ..color = rgba(255, 255, 255, 0.12));
        c.drawPath(k.path.shift(o), crack
          ..strokeWidth = k.w
          ..color = rgba(0, 0, 0, 0.34));
      });
    }
    // pits
    for (final q in rock.pits) {
      _wrapped(c, ui.Rect.fromCircle(center: q.at, radius: q.r + 2), (o) {
        c.drawOval(ui.Rect.fromCenter(center: q.at + o + ui.Offset(-0.6, 0.7), width: q.r * 2.3, height: q.r * 1.9),
            p..color = rgba(255, 255, 255, 0.12));
        c.drawOval(ui.Rect.fromCenter(center: q.at + o, width: q.r * 2, height: q.r * 1.6), p..color = rgba(0, 0, 0, 0.3));
      });
    }
    // grit
    for (var i = 0; i < 18000; i++) {
      final x = r() * size, y = r() * size, s = 0.6 + r() * 1.9, v = r();
      p.color = v < 0.45 ? rgba(0, 0, 0, 0.08 + r() * 0.16) : rgba(255, 255, 255, 0.05 + r() * 0.12);
      c.drawRect(ui.Rect.fromLTWH(x, y, s, s * (0.6 + r() * 0.8)), p);
    }
  }

  void _drawSnowTile(ui.Canvas c, _RockShape rock) {
    final r = Rng(13);
    final shade = ui.Paint()
      ..color = rgba(40, 56, 90, 0.3)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4);
    final fill = ui.Paint();
    // short drifts of snow sitting on each shelf, thicker in the middle
    for (final b in rock.beds) {
      for (final m in b.path.computeMetrics()) {
        for (var d = r() * 40; d < m.length - 12; d += 22 + r() * 70) {
          final len = math.min(m.length - d, 14 + r() * 46), thick = (1.8 + r() * 3.2) * b.w;
          final top = <ui.Offset>[], bottom = <ui.Offset>[];
          for (var i = 0; i <= 8; i++) {
            final u = i / 8, t = m.getTangentForOffset(d + u * len)!;
            final bulge = math.pow(math.sin(u * math.pi), 0.6).toDouble();
            // up on screen is +y here; the shelf's top is 2.4 above the bed line
            final base = t.position + ui.Offset(0, 2.4 * b.w - 0.6);
            bottom.add(base);
            top.add(base + ui.Offset((r() - 0.5) * 0.8, thick * bulge * (0.85 + r() * 0.3)));
          }
          final drift = ui.Path()..moveTo(bottom.first.dx, bottom.first.dy);
          for (final q in top) {
            drift.lineTo(q.dx, q.dy);
          }
          for (final q in bottom.reversed) {
            drift.lineTo(q.dx, q.dy);
          }
          drift.close();
          final box = drift.getBounds();
          _wrapped(c, box.inflate(4), (o) {
            c.drawPath(drift.shift(o + const ui.Offset(0.8, -1.4)), shade);
            fill.shader = ui.Gradient.linear(ui.Offset(0, box.top + o.dy), ui.Offset(0, box.bottom + o.dy),
                [rgba(200, 214, 236, 1), rgba(255, 255, 255, 1)], [0, 0.6]);
            c.drawPath(drift.shift(o), fill);
          });
        }
      }
    }
    fill.shader = null;
    // snow in some of the pits, and a few loose flecks
    for (final q in rock.pits) {
      if (r() < 0.45) continue;
      _wrapped(c, ui.Rect.fromCircle(center: q.at, radius: q.r + 2), (o) {
        c.drawOval(ui.Rect.fromCenter(center: q.at + o + ui.Offset(0, -0.5), width: q.r * 2.1, height: q.r * 1.2),
            fill..color = rgba(255, 255, 255, 0.85));
      });
    }
    for (var i = 0; i < 700; i++) {
      final x = r() * tileSize, y = r() * tileSize, s = 0.7 + r() * 1.3;
      c.drawOval(ui.Rect.fromCenter(center: ui.Offset(x, y), width: s * 1.5, height: s), fill..color = rgba(255, 255, 255, 0.2 + r() * 0.35));
    }
  }

  /// A soft round flake, white, 32 px across.
  Baked _makeFlake() => bake(32, 32, (c) {
        c.drawCircle(const ui.Offset(16, 16), 15,
            ui.Paint()..shader = ui.Gradient.radial(const ui.Offset(16, 16), 15, [rgba(255, 255, 255, 1), rgba(255, 255, 255, 0.85), rgba(255, 255, 255, 0)], [0, 0.35, 1]));
      });

  /// A long strip of soft mist, white, that wraps around left and right.
  Baked _makeMist() => bake(512, 96, (c) {
        final r = Rng(17);
        final p = ui.Paint()..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10);
        for (var i = 0; i < 26; i++) {
          final x = r() * 512, y = 40 + (r() - 0.5) * 30, w = 80 + r() * 160, h = 12 + r() * 20;
          p.color = rgba(255, 255, 255, 0.25 + r() * 0.35);
          for (final ox in const [-512.0, 0.0, 512.0]) {
            c.drawOval(ui.Rect.fromCenter(center: ui.Offset(x + ox, y), width: w, height: h), p);
          }
        }
      });

  /// Red, white, red: the paint that marks a route, a little worn. 40 x 36 px.
  Baked _makeBlaze() => bake(40, 36, (c) {
        final r = Rng(23);
        final p = ui.Paint();
        for (var k = 0; k < 3; k++) {
          final y0 = 4 + k * 9.4, path = ui.Path()..moveTo(4 + r() * 1.5, y0 + r());
          for (var x = 8.0; x <= 36; x += 4) {
            path.lineTo(x, y0 + (r() - 0.5) * 1.2);
          }
          for (var x = 36.0; x >= 4; x -= 4) {
            path.lineTo(x + (r() - 0.5), y0 + 9 + (r() - 0.5) * 1.2);
          }
          path.close();
          c.drawPath(path, p..color = k == 1 ? hex(0xF4F1E8) : hex(0xC42A1C));
        }
        // worn spots where the rock shows through
        for (var i = 0; i < 26; i++) {
          c.drawCircle(ui.Offset(4 + r() * 32, 4 + r() * 28), 0.5 + r() * 1.1, p..color = rgba(120, 120, 120, 0.55));
        }
      });

  CloudSprite _makeCloud(int seed, double w, double h, _CloudPal pal, {bool streak = false}) {
    final rng = Rng(seed);
    const res = 1.25;
    final rec = ui.PictureRecorder();
    final x = ui.Canvas(rec);
    x.scale(res, res);
    final puffs = <({double x, double y, double r, double e})>[];
    final base = h * 0.86;
    if (streak) {
      const n = 9;
      for (var i = 0; i < n; i++) {
        final u = i / (n - 1), b = math.pow(math.sin(u * math.pi), 0.7).toDouble();
        puffs.add((
          x: w * (0.08 + 0.84 * u) + (rng() - 0.5) * w * 0.03,
          y: base - h * 0.14 - b * h * 0.18 + (rng() - 0.5) * h * 0.06,
          r: h * (0.1 + 0.18 * b) * (0.8 + rng() * 0.4),
          e: 3.6 + rng() * 1.4,
        ));
      }
    } else {
      final n = 7 + (rng() * 3).floor(); // bottom row
      for (var i = 0; i < n; i++) {
        final u = (i + 0.5) / n, b = math.sin(math.pi * u), r = h * (0.1 + 0.13 * b) * (0.85 + rng() * 0.35);
        puffs.add((x: w * (0.07 + 0.86 * u) + (rng() - 0.5) * w * 0.03, y: base - r * 0.45, r: r, e: 1.25));
      }
      final m = 3 + (rng() * 2).floor(); // body
      for (var i = 0; i < m; i++) {
        final u = (i + 0.5) / m, b = math.sin(math.pi * (0.15 + 0.7 * u)), r = h * (0.17 + 0.12 * b) * (0.85 + rng() * 0.3);
        puffs.add((x: w * (0.2 + 0.6 * u) + (rng() - 0.5) * w * 0.06, y: base - h * 0.2 - b * h * 0.2 - r * 0.25, r: r, e: 1.1));
      }
      final k = 4 + (rng() * 4).floor(); // small puffs on the crown
      for (var i = 0; i < k; i++) {
        final u = 0.18 + rng() * 0.64, b = math.sin(math.pi * u), r = h * (0.07 + rng() * 0.07);
        puffs.add((x: w * u, y: base - h * 0.32 - b * h * 0.32 - r * 0.2, r: r, e: 1));
      }
    }
    puffs.sort((a, b) => ((a.y - a.r * 0.3) - (b.y - b.r * 0.3)).sign.toInt()); // high puffs sit behind
    ui.Path oval(double cx, double cy, double rx, double ry) =>
        ui.Path()..addOval(ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2));
    ui.Path union(double grow) {
      final p = ui.Path();
      for (final q in puffs) {
        p.addOval(ui.Rect.fromCenter(center: ui.Offset(q.x, q.y), width: (q.r + grow) * q.e * 2, height: (q.r + grow) * 2));
      }
      return p;
    }

    var top = h;
    for (final q in puffs) {
      top = math.min(top, q.y - q.r);
    }
    // one tone ramp for the whole cloud, so the body reads as one soft mass
    final body = ui.Gradient.linear(ui.Offset(w * 0.1, base), ui.Offset(w * 0.6, top),
        [pal.rim, pal.warm, pal.mid, pal.top], [0, 0.18, 0.5, 1]);
    final paint = ui.Paint();
    x.save();
    x.clipRect(ui.Rect.fromLTWH(0, 0, w, base));
    paint.color = pal.top.withAlpha((0.2 * 255).round());
    x.drawPath(union(2.4), paint); // soft edge
    x.save();
    x.clipPath(union(0));
    for (final q in puffs) {
      // the puff throws a little shade on the puffs behind it, which draws the folds
      paint
        ..shader = null
        ..color = pal.edge;
      final g = q.r * 0.02;
      x.drawPath(oval(q.x + q.r * 0.05 * q.e, q.y - q.r * 0.09, (q.r + g) * q.e, q.r + g), paint);
      final shape = oval(q.x, q.y, q.r * q.e, q.r);
      paint
        ..color = const ui.Color(0xFF000000)
        ..shader = body;
      x.drawPath(shape, paint);
      // soft light on the side that faces the sun
      paint.shader = ui.Gradient.radial(ui.Offset(q.x - q.r * 0.45 * q.e, q.y + q.r * 0.35), q.r * 1.1 * q.e,
          [pal.hi, rgba(255, 255, 255, 0)]);
      x.drawPath(shape, paint);
    }
    x.restore();
    // glow from the sun, low on the left, only where there is cloud
    paint
      ..color = const ui.Color(0xFF000000)
      ..shader = ui.Gradient.radial(ui.Offset(-w * 0.15, base + h * 0.1), w * 0.9, [pal.glow, rgba(255, 255, 255, 0)])
      ..blendMode = ui.BlendMode.srcATop;
    x.drawRect(ui.Rect.fromLTWH(0, 0, w, h), paint);
    paint.shader = ui.Gradient.linear(ui.Offset(0, base - h * 0.12), ui.Offset(0, base), [rgba(255, 255, 255, 0), pal.under]);
    x.drawRect(ui.Rect.fromLTWH(0, base - h * 0.12, w, h * 0.12), paint); // bright, flat underside
    x.restore();
    return CloudSprite(Baked(rec.endRecording(), (w * res).ceil(), (h * res).ceil()), w, h);
  }
}
