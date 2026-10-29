// The holds as features of the rock: jugs are deep pockets with a lip,
// crimps thin flakes, slopers smooth bulges and foot steps small knobs.
// Each kind comes in three shapes, drawn once in grey into one atlas; the
// scene tints them with the mountain's hold colour and stamps every hold in
// view with one drawRawAtlas call. Chalk and snow are a second layer that
// is not tinted (and the snow can shrink as a hand brushes it off).
//
// Everything here is in world units with y pointing up, around the hold's
// point (0, 0). The atlas cells are not flipped; the scene's flip turns them
// the right way up.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'art.dart';
import 'core.dart';
import 'palette.dart';

/// The three layers of the atlas.
enum HoldLayer { rock, chalk, snow }

class HoldArt {
  const HoldArt._();

  static const double px = 5; // atlas pixels per world unit
  static const double cellW = 42, cellH = 34, cellL = 21, cellB = 15; // a cell around the hold, in units
  static const int variants = 3, _cols = 6;
  static const List<HoldType> kinds = [HoldType.jug, HoldType.crimp, HoldType.sloper, HoldType.chip];

  static Baked? _atlas;
  static Baked get atlas => _atlas ??= _make();

  /// Which of the three shapes hold [k] has.
  static int variantOf(int k) => (k * 7 + (k >> 2)) % variants;

  static int _kind(HoldType t) => switch (t) { HoldType.jug => 0, HoldType.crimp => 1, HoldType.sloper => 2, _ => 3 };

  /// The atlas cell of a layer, kind and shape, in atlas pixels (left, top).
  static (double, double) cell(HoldLayer layer, HoldType t, int v) {
    final n = layer.index * kinds.length * variants + _kind(t) * variants + v;
    return ((n % _cols) * cellW * px, (n ~/ _cols) * cellH * px);
  }

  static Baked _make() {
    final rows = (HoldLayer.values.length * kinds.length * variants / _cols).ceil();
    return bake((_cols * cellW * px).ceil(), (rows * cellH * px).ceil(), (c) {
      for (final layer in HoldLayer.values) {
        for (final t in kinds) {
          for (var v = 0; v < variants; v++) {
            final (x, y) = cell(layer, t, v);
            c.save();
            c.translate(x + cellL * px, y + cellB * px);
            c.scale(px, px);
            final shape = _Shape(t, v);
            switch (layer) {
              case HoldLayer.rock:
                shape.paintRock(c);
              case HoldLayer.chalk:
                shape.paintChalk(c);
              case HoldLayer.snow:
                shape.paintSnow(c);
            }
            c.restore();
          }
        }
      }
    });
  }

  /// The outline of a hold at (x, y), for the dark veil on holds out of reach.
  static ui.Path outline(HoldType t, double x, double y, [int v = 0]) => _Shape(t, v).body.shift(ui.Offset(x, y));
}

/// A smooth closed path through [pts] (Catmull-Rom turned into curves).
ui.Path smoothLoop(List<ui.Offset> pts) {
  final n = pts.length, p = ui.Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return p..close();
}

/// An uneven oval: [rx] by [ry] around ([cx], [cy]), its edge moved in and
/// out by up to [rough] of its size.
List<ui.Offset> lumpyOval(Rng r, double cx, double cy, double rx, double ry, double rough, {int n = 14, double squashTop = 0}) {
  final waves = [for (var k = 2; k <= 5; k++) (a: (r() - 0.5) * 2 * rough / (k - 1), f: r() * math.pi * 2, k: k)];
  return [
    for (var i = 0; i < n; i++)
      () {
        final t = i / n * math.pi * 2;
        var m = 1.0;
        for (final w in waves) {
          m += w.a * math.sin(t * w.k + w.f);
        }
        var y = math.sin(t) * ry * m;
        if (y > 0) y *= 1 - squashTop; // a flatter top
        return ui.Offset(cx + math.cos(t) * rx * m, cy + y);
      }(),
  ];
}

ui.Color _g(double v, [double a = 1]) => rgba((v * 255).round(), (v * 255).round(), (v * 255).round(), a);

final ui.Paint _p = ui.Paint();
ui.Paint _blur(ui.Color c, double sigma) => ui.Paint()
  ..color = c
  ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
ui.Paint _line(ui.Color c, double w, {double blur = 0}) => ui.Paint()
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = ui.StrokeCap.round
  ..strokeJoin = ui.StrokeJoin.round
  ..color = c
  ..maskFilter = blur > 0 ? ui.MaskFilter.blur(ui.BlurStyle.normal, blur) : null;

/// Snow: white on top, a little blue where it curls under.
const ui.Color _snowTop = ui.Color(0xFFFFFFFF), _snowUnder = ui.Color(0xFFC9D6EA);

class _Shape {
  _Shape(this.t, this.v) : r = Rng(101 + v * 17 + HoldArt._kind(t) * 53) {
    switch (t) {
      case HoldType.jug:
        final pts = lumpyOval(r, 0, 0.6, 12.5 + r() * 1.5, 9 + r(), 0.09, squashTop: 0.12);
        body = smoothLoop(pts);
        // the lip: the edge your fingers curl over. Under it the hold is in
        // its own deep shadow (the undercut), above it the lit top.
        final b = body.getBounds(), lipY = 0.4 + (r() - 0.5) * 0.8, arch = 1.6 + r() * 1.2;
        final top = <ui.Offset>[];
        for (var i = 0; i <= 10; i++) {
          final u = i / 10, x = b.left - 1 + u * (b.width + 2);
          top.add(ui.Offset(x, lipY + arch * math.sin(u * math.pi) + (r() - 0.5) * 0.35));
        }
        lip = top;
        pocket = ui.Path()
          ..addPolygon([...top, ui.Offset(b.right + 1, b.top - 2), ui.Offset(b.left - 1, b.top - 2)], true);
      case HoldType.crimp:
        final len = 18 + r() * 4, tilt = (r() - 0.5) * 0.12;
        final top = <ui.Offset>[], bottom = <ui.Offset>[];
        for (var i = 0; i <= 8; i++) {
          final u = i / 8, x = -len / 2 + u * len, taper = math.sin(u * math.pi);
          top.add(ui.Offset(x, 1.6 + (r() - 0.5) * 0.6 * taper + x * tilt));
          bottom.add(ui.Offset(x + (r() - 0.5) * 0.8, 1.6 - (1.2 + 3.2 * math.pow(taper, 0.6)) + x * tilt));
        }
        edge = top;
        body = smoothLoop([...top, ...bottom.reversed]);
      case HoldType.sloper:
        final w = 15 + r() * 2, h = 9.5 + r() * 1.5;
        final pts = <ui.Offset>[];
        for (var i = 0; i <= 10; i++) {
          final a = math.pi * i / 10; // over the top, right to left
          pts.add(ui.Offset(math.cos(a) * w * (1 + (r() - 0.5) * 0.06), -4 + math.sin(a) * h * (1 + (r() - 0.5) * 0.08)));
        }
        pts.add(ui.Offset(-w * 0.7, -5.2 - r()));
        pts.add(ui.Offset(0, -5.8 - r() * 0.6));
        pts.add(ui.Offset(w * 0.7, -5.2 - r()));
        body = smoothLoop(pts);
      default: // chip: a small knob with a flat top
        final w = 6 + r() * 1.2;
        body = smoothLoop([
          ui.Offset(-w, -1.8),
          ui.Offset(-w * 0.8, 1.6 + r() * 0.8),
          ui.Offset(-w * 0.1, 2.8 + r() * 0.6),
          ui.Offset(w * 0.75, 2.2 + r() * 0.6),
          ui.Offset(w, -1.2),
          ui.Offset(w * 0.3, -3.4 - r() * 0.6),
          ui.Offset(-w * 0.45, -3.2),
        ]);
    }
  }

  final HoldType t;
  final int v;
  final Rng r;
  late final ui.Path body;
  ui.Path? pocket;
  List<ui.Offset>? edge, lip;

  /// The hold in grey: its shadow on the rock, the body lit from the upper
  /// left, the shaded lower right, and the parts the hand finds.
  void paintRock(ui.Canvas c) {
    final b = body.getBounds();
    final soft = t == HoldType.sloper ? 2.2 : 1.5;
    // contact shade and the cast shadow toward the lower right
    c.drawPath(body.shift(const ui.Offset(0.6, -0.8)), _blur(rgba(0, 0, 0, 0.34), soft + 1.2));
    c.drawPath(body.shift(const ui.Offset(2.4, -3.0)), _blur(rgba(0, 0, 0, 0.42), soft));
    // the body
    final lightAt = ui.Offset(b.left + b.width * 0.32, b.top + b.height * 0.78); // y up: top is the larger y
    final hi = switch (t) { HoldType.chip => 0.86, HoldType.crimp => 0.88, _ => 0.97 };
    _p
      ..shader = ui.Gradient.radial(lightAt, math.max(b.width, b.height) * 0.85, [_g(hi), _g(hi * 0.78), _g(hi * 0.52)], [0, 0.55, 1])
      ..color = const ui.Color(0xFF000000);
    c.drawPath(body, _p);
    _p.shader = null;
    c.save();
    c.clipPath(body);
    // a shaded edge on the lower right and a lit one on the upper left (an
    // outline moved the other way, seen through the body)
    c.drawPath(body.shift(const ui.Offset(-1.5, 1.6)), _line(rgba(0, 0, 0, 0.32), 3.2, blur: 0.9));
    c.drawPath(body.shift(const ui.Offset(1.2, -1.2)), _line(rgba(255, 255, 255, 0.34), 1.8, blur: 0.6));
    // grain
    for (var i = 0; i < 40; i++) {
      final x = b.left + r() * b.width, y = b.bottom - r() * b.height;
      c.drawCircle(ui.Offset(x, y), 0.18 + r() * 0.3, _p..color = r() < 0.5 ? rgba(0, 0, 0, 0.18) : rgba(255, 255, 255, 0.2));
    }
    switch (t) {
      case HoldType.jug:
        // the undercut: darkest right under the lip, a little light
        // bouncing back near the bottom
        final pk = pocket!, pb = pk.getBounds(), l = lip!;
        _p
          ..shader = ui.Gradient.linear(ui.Offset(0, l[5].dy), ui.Offset(0, b.top), [_g(0.05, 0.96), _g(0.16, 0.9), _g(0.3, 0.85)], [0, 0.55, 1])
          ..color = const ui.Color(0xFF000000);
        c.drawPath(pk, _p);
        _p.shader = null;
        c.drawPath(pk.shift(const ui.Offset(0, -1.4)), _blur(rgba(0, 0, 0, 0.35), 1.2));
        // the rounded lip catching the light, brightest in the middle
        final edgeLine = ui.Path()..moveTo(l[1].dx, l[1].dy);
        for (final q in l.skip(2).take(l.length - 3)) {
          edgeLine.lineTo(q.dx, q.dy + 0.2);
        }
        c.drawPath(edgeLine.shift(const ui.Offset(0, 0.9)), _line(rgba(255, 255, 255, 0.28), 2.2, blur: 0.6));
        c.drawPath(
            edgeLine,
            _line(rgba(255, 255, 255, 0.85), 1.1)
              ..shader = ui.Gradient.linear(ui.Offset(pb.left, 0), ui.Offset(pb.right, 0),
                  [rgba(255, 255, 255, 0.1), rgba(255, 255, 255, 0.85), rgba(255, 255, 255, 0.35)], [0, 0.4, 1]));
      case HoldType.crimp:
        // the thin top edge, catching the light
        final e = edge!, path = ui.Path()..moveTo(e.first.dx + 1, e.first.dy - 0.3);
        for (final q in e.skip(1).take(e.length - 2)) {
          path.lineTo(q.dx, q.dy - 0.3);
        }
        path.lineTo(e.last.dx - 1, e.last.dy - 0.3);
        c.drawPath(path, _line(rgba(255, 255, 255, 0.95), 1.2));
        c.drawPath(path.shift(const ui.Offset(0, -1.4)), _line(rgba(0, 0, 0, 0.18), 0.8));
      case HoldType.sloper:
        // a broad soft sheen high on the left
        c.drawOval(ui.Rect.fromCenter(center: ui.Offset(b.left + b.width * 0.36, b.top + b.height * 0.62), width: b.width * 0.42, height: b.height * 0.3),
            _blur(rgba(255, 255, 255, 0.32), 1.6));
      default:
        // the flat top of the knob
        c.drawPath(
            ui.Path()
              ..moveTo(b.left + 1.2, b.top + b.height * 0.68)
              ..quadraticBezierTo(b.center.dx, b.top + b.height * 0.95, b.right - 1.4, b.top + b.height * 0.72),
            _line(rgba(255, 255, 255, 0.6), 0.9));
    }
    c.restore();
  }

  /// Chalk left by your hands, a little grainy.
  void paintChalk(ui.Canvas c) {
    final b = body.getBounds(), white = rgba(255, 255, 255, 0.5);
    switch (t) {
      case HoldType.jug:
        final l = lip!;
        c.drawOval(ui.Rect.fromCenter(center: ui.Offset(-0.5, l[5].dy + 0.6), width: b.width * 0.62, height: 2.8), _blur(white, 0.7));
      case HoldType.crimp:
        c.drawOval(ui.Rect.fromCenter(center: ui.Offset(0, b.top + b.height * 0.75), width: b.width * 0.75, height: 2.2), _blur(white, 0.6));
      case HoldType.sloper:
        c.drawOval(ui.Rect.fromCenter(center: ui.Offset(-1, b.top + b.height * 0.72), width: b.width * 0.55, height: 4.4), _blur(white, 1));
      default:
        return;
    }
    for (var i = 0; i < 26; i++) {
      final x = b.left + b.width * (0.2 + r() * 0.6), y = b.top + b.height * (0.4 + r() * 0.55);
      c.drawCircle(ui.Offset(x, y), 0.2 + r() * 0.35, _p..color = rgba(255, 255, 255, 0.25 + r() * 0.4));
    }
  }

  /// Snow lying on the top of the hold: a cushion that follows its upper
  /// edge and hangs over it a little, blue where it curls under.
  void paintSnow(ui.Canvas c) {
    final b = body.getBounds();
    // the top edge of the hold, from left to right
    final top = <ui.Offset>[];
    for (var i = 0; i <= 12; i++) {
      final x = b.left + 1 + (b.width - 2) * i / 12;
      top.add(ui.Offset(x, _topAt(x)));
    }
    final depth = switch (t) { HoldType.jug => 3.6, HoldType.crimp => 1.9, HoldType.sloper => 4.4, _ => 1.8 };
    final rise = switch (t) { HoldType.crimp => 1.6, HoldType.chip => 1.4, _ => 2.2 };
    final cap = <ui.Offset>[];
    for (var i = 0; i < top.length; i++) {
      final u = i / (top.length - 1), bulge = math.pow(math.sin(u * math.pi), 0.55).toDouble();
      cap.add(top[i] + ui.Offset(0, rise * bulge + (r() - 0.5) * 0.4));
    }
    for (var i = top.length - 1; i >= 0; i--) {
      final u = i / (top.length - 1), bulge = math.pow(math.sin(u * math.pi), 0.8).toDouble();
      cap.add(top[i] - ui.Offset(0, depth * bulge * (0.75 + r() * 0.4)));
    }
    final path = smoothLoop(cap);
    c.drawPath(path.shift(const ui.Offset(0.8, -1.1)), _blur(rgba(30, 40, 70, 0.28), 1));
    final pb = path.getBounds();
    _p
      ..shader = ui.Gradient.linear(ui.Offset(0, pb.top), ui.Offset(0, pb.bottom), [_snowUnder, _snowTop, _snowTop], [0, 0.55, 1])
      ..color = const ui.Color(0xFF000000);
    c.drawPath(path, _p);
    _p.shader = null;
    // a few glints
    for (var i = 0; i < 5; i++) {
      final q = cap[1 + (r() * (top.length - 2)).floor()];
      c.drawCircle(q - ui.Offset(0, 0.6 + r() * 0.8), 0.25 + r() * 0.2, _p..color = rgba(255, 255, 255, 1));
    }
  }

  /// The height of the hold's upper edge at [x].
  double _topAt(double x) {
    final b = body.getBounds();
    for (var y = b.bottom + 0.5; y > b.top; y -= 0.25) {
      if (body.contains(ui.Offset(x, y))) return y;
    }
    return b.center.dy;
  }
}
