// Art that is made once: the rock texture, the clouds, stars, grass, and the
// rock facets of each route. Everything is drawn in code, no image files.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'core.dart';
import 'palette.dart';

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

/// Cuts a path into dashes ([pattern] is on, off, on, off...).
ui.Path dashed(ui.Path src, List<double> pattern) {
  final out = ui.Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0;
    var k = 0;
    while (d < m.length) {
      final len = pattern[k % pattern.length];
      if (k.isEven) out.addPath(m.extractPath(d, math.min(d + len, m.length)), ui.Offset.zero);
      d += len;
      k++;
    }
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

class Facet {
  Facet(this.path, this.color, this.y0, this.y1, this.x0, this.x1);
  final ui.Path path;
  final ui.Color color;
  final double y0, y1, x0, x1;
}

class CloudSprite {
  CloudSprite(this.image, this.w, this.h);
  final ui.Image image;
  final double w, h;
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
  late final ui.Image tile;
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

  ui.Image _makeTile() {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final r = Rng(99);
    const size = 512.0;
    c.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), ui.Paint()..color = hex(0x5a6070));
    final p = ui.Paint();
    for (var i = 0; i < 20; i++) {
      final x = r() * size, y = r() * size, rad = 50 + r() * 150, light = r() > 0.5;
      for (var ox = -size; ox <= size; ox += size) {
        for (var oy = -size; oy <= size; oy += size) {
          p.shader = ui.Gradient.radial(ui.Offset(x + ox, y + oy), rad, [
            light ? rgba(170, 170, 190, 0.11) : rgba(28, 30, 40, 0.13),
            rgba(0, 0, 0, 0),
          ]);
          c.drawRect(const ui.Rect.fromLTWH(0, 0, size, size), p);
        }
      }
    }
    p.shader = null;
    for (var i = 0; i < 4200; i++) {
      final x = r() * size, y = r() * size, s = 0.6 + r() * 2, v = r();
      p.color = v < 0.42
          ? rgba(18, 20, 26, 0.12 + r() * 0.2)
          : v < 0.86
              ? rgba(215, 215, 222, 0.07 + r() * 0.13)
              : rgba(226, 170, 150, 0.12 + r() * 0.16);
      c.drawRect(ui.Rect.fromLTWH(x, y, s, s * (0.6 + r() * 0.8)), p);
    }
    return rec.endRecording().toImageSync(size.toInt(), size.toInt());
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
      paint.shader = body;
      x.drawPath(shape, paint);
      // soft light on the side that faces the sun
      paint.shader = ui.Gradient.radial(ui.Offset(q.x - q.r * 0.45 * q.e, q.y + q.r * 0.35), q.r * 1.1 * q.e,
          [pal.hi, rgba(255, 220, 190, 0)]);
      x.drawPath(shape, paint);
    }
    x.restore();
    // glow from the sun, low on the left, only where there is cloud
    paint
      ..shader = ui.Gradient.radial(ui.Offset(-w * 0.15, base + h * 0.1), w * 0.9, [pal.glow, rgba(255, 170, 120, 0)])
      ..blendMode = ui.BlendMode.srcATop;
    x.drawRect(ui.Rect.fromLTWH(0, 0, w, h), paint);
    paint.shader = ui.Gradient.linear(ui.Offset(0, base - h * 0.12), ui.Offset(0, base), [rgba(255, 214, 170, 0), pal.under]);
    x.drawRect(ui.Rect.fromLTWH(0, base - h * 0.12, w, h * 0.12), paint); // bright, flat underside
    x.restore();
    final img = rec.endRecording().toImageSync((w * res).ceil(), (h * res).ceil());
    return CloudSprite(img, w, h);
  }

  /// The light and dark facets that give the rock its shape. Made once per route.
  List<Facet> facetsFor(ClimbRoute r) {
    final cached = r.facets;
    if (cached is List<Facet>) return cached;
    final rng = Rng((r.topY * 7 + r.id.length * 131).toInt());
    const step = 62.0;
    final cols = (1220 / step).ceil() + 1, rows = ((r.topY + 300) / step).ceil() + 1;
    final pts = <List<ui.Offset>>[];
    for (var j = 0; j < rows; j++) {
      final row = <ui.Offset>[];
      for (var i = 0; i < cols; i++) {
        final px = -430 + i * step + (rng() - 0.5) * step * 0.75;
        final py = -60 + j * step + (rng() - 0.5) * step * 0.75;
        row.add(ui.Offset(px, py));
      }
      pts.add(row);
    }
    final out = <Facet>[];
    for (var j = 0; j < rows - 1; j++) {
      for (var i = 0; i < cols - 1; i++) {
        final a = pts[j][i], b = pts[j][i + 1], c = pts[j + 1][i], d = pts[j + 1][i + 1], flip = rng() < 0.5;
        final tris = flip
            ? [
                [a, b, d],
                [a, d, c],
              ]
            : [
                [a, b, c],
                [b, d, c],
              ];
        for (final t in tris) {
          final s = (rng() * 2 - 1) * 0.8 + 0.2;
          final col = s > 0 ? rgba(255, 232, 205, s * 0.085) : rgba(10, 12, 22, -s * 0.13);
          final path = ui.Path()
            ..moveTo(t[0].dx, t[0].dy)
            ..lineTo(t[1].dx, t[1].dy)
            ..lineTo(t[2].dx, t[2].dy)
            ..close();
          final ys = t.map((o) => o.dy), xs = t.map((o) => o.dx);
          out.add(Facet(path, col, ys.reduce(math.min), ys.reduce(math.max), xs.reduce(math.min), xs.reduce(math.max)));
        }
      }
    }
    r.facets = out;
    return out;
  }
}
