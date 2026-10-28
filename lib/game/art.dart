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

class Art {
  Art._();
  static final Art instance = Art._();

  bool _ready = false;
  late final Baked tile;
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
    const near = _CloudPal(
      ui.Color(0xFF7F6C9E), ui.Color(0xFFC48AA2), ui.Color(0xFFF2A98F), ui.Color(0xFFFFD4AE),
      ui.Color.fromRGBO(92, 72, 128, 0.4), ui.Color.fromRGBO(255, 214, 180, 0.4),
      ui.Color.fromRGBO(255, 196, 150, 0.3), ui.Color.fromRGBO(255, 224, 186, 0.7));
    const far = _CloudPal(
      ui.Color(0xFF9180AD), ui.Color(0xFFC290A8), ui.Color(0xFFE3AA9D), ui.Color(0xFFF2C8B5),
      ui.Color.fromRGBO(110, 90, 140, 0.35), ui.Color.fromRGBO(255, 214, 190, 0.28),
      ui.Color.fromRGBO(255, 186, 150, 0.22), ui.Color.fromRGBO(250, 210, 190, 0.5));
    const streak = _CloudPal(
      ui.Color(0xFFA986A6), ui.Color(0xFFD99A9F), ui.Color(0xFFF6B795), ui.Color(0xFFFFD8B4),
      ui.Color.fromRGBO(130, 96, 140, 0.25), ui.Color.fromRGBO(255, 224, 190, 0.35),
      ui.Color.fromRGBO(255, 205, 160, 0.35), ui.Color.fromRGBO(255, 226, 190, 0.55));
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
  }

  /// Size of the rock texture in pixels. It is drawn at 0.55 units per pixel,
  /// so it repeats every ~5.6 m.
  static const double tileSize = 1024;

  /// The rock: blotches, specks of grit and the big light and dark facets that
  /// give the wall its shape. Everything wraps around, so the texture tiles
  /// without seams, and the wall costs one textured rectangle per frame.
  Baked _makeTile() => bake(tileSize.toInt(), tileSize.toInt(), _drawTile);

  void _drawTile(ui.Canvas c) {
    final r = Rng(99);
    const size = tileSize;
    const whole = ui.Rect.fromLTWH(0, 0, size, size);
    c.drawRect(whole, ui.Paint()..color = hex(0x5a6070));
    final p = ui.Paint();
    for (var i = 0; i < 80; i++) {
      final x = r() * size, y = r() * size, rad = 50 + r() * 150, light = r() > 0.5;
      for (var ox = -size; ox <= size; ox += size) {
        for (var oy = -size; oy <= size; oy += size) {
          final box = ui.Rect.fromCircle(center: ui.Offset(x + ox, y + oy), radius: rad);
          if (!box.overlaps(whole)) continue;
          p.shader = ui.Gradient.radial(box.center, rad, [
            light ? rgba(170, 170, 190, 0.11) : rgba(28, 30, 40, 0.13),
            rgba(0, 0, 0, 0),
          ]);
          c.drawRect(box.intersect(whole), p);
        }
      }
    }
    p.shader = null;
    // facets on a jittered grid that wraps around (cells of ~62 units)
    const n = 9, cell = size / n;
    final pts = [
      for (var j = 0; j < n; j++)
        [for (var i = 0; i < n; i++) ui.Offset(i * cell + (r() - 0.5) * cell * 0.75, j * cell + (r() - 0.5) * cell * 0.75)],
    ];
    ui.Offset at(int i, int j) => pts[j % n][i % n] + ui.Offset((i ~/ n) * size, (j ~/ n) * size);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final a = at(i, j), b = at(i + 1, j), cc = at(i, j + 1), d = at(i + 1, j + 1), flip = r() < 0.5;
        for (final t in flip ? [[a, b, d], [a, d, cc]] : [[a, b, cc], [b, d, cc]]) {
          final sh = (r() * 2 - 1) * 0.8 + 0.2;
          p.color = sh > 0 ? rgba(255, 232, 205, sh * 0.085) : rgba(10, 12, 22, -sh * 0.13);
          final tri = ui.Path()
            ..moveTo(t[0].dx, t[0].dy)
            ..lineTo(t[1].dx, t[1].dy)
            ..lineTo(t[2].dx, t[2].dy)
            ..close();
          for (var ox = -size; ox <= 0; ox += size) {
            for (var oy = -size; oy <= 0; oy += size) {
              c.drawPath(tri.shift(ui.Offset(ox, oy)), p);
            }
          }
        }
      }
    }
    for (var i = 0; i < 16800; i++) {
      final x = r() * size, y = r() * size, s = 0.6 + r() * 2, v = r();
      p.color = v < 0.42
          ? rgba(18, 20, 26, 0.12 + r() * 0.2)
          : v < 0.86
              ? rgba(215, 215, 222, 0.07 + r() * 0.13)
              : rgba(226, 170, 150, 0.12 + r() * 0.16);
      c.drawRect(ui.Rect.fromLTWH(x, y, s, s * (0.6 + r() * 0.8)), p);
    }
  }

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
          [pal.hi, rgba(255, 220, 190, 0)]);
      x.drawPath(shape, paint);
    }
    x.restore();
    // glow from the sun, low on the left, only where there is cloud
    paint
      ..color = const ui.Color(0xFF000000)
      ..shader = ui.Gradient.radial(ui.Offset(-w * 0.15, base + h * 0.1), w * 0.9, [pal.glow, rgba(255, 170, 120, 0)])
      ..blendMode = ui.BlendMode.srcATop;
    x.drawRect(ui.Rect.fromLTWH(0, 0, w, h), paint);
    paint.shader = ui.Gradient.linear(ui.Offset(0, base - h * 0.12), ui.Offset(0, base), [rgba(255, 214, 170, 0), pal.under]);
    x.drawRect(ui.Rect.fromLTWH(0, base - h * 0.12, w, h * 0.12), paint); // bright, flat underside
    x.restore();
    return CloudSprite(Baked(rec.endRecording(), (w * res).ceil(), (h * res).ceil()), w, h);
  }
}
