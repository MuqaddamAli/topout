// Draws a climber, seen from behind: cel shaded, with a helmet, hair,
// harness, quickdraws, chalk bag and climbing shoes. The colours and the hair
// come from the climber's [Look].
//
// All coordinates are world units with y pointing up. The same code draws the
// shadow (sil = true), which fills every shape in black.
import 'dart:math' as math;
import 'dart:ui';

import 'art.dart';
import 'body.dart';
import 'core.dart';
import 'palette.dart';

final Paint _fill = Paint();
final Paint _stroke = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final Paint _sil = Paint()..color = const Color(0xFF000000);
final Paint _silStroke = Paint()
  ..color = const Color(0xFF000000)
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = 2;

void _fillPath(Canvas c, Path p, Color col) => c.drawPath(p, _fill..color = col);
void _strokePath(Canvas c, Path p, Color col, double w) => c.drawPath(
    p,
    _stroke
      ..color = col
      ..strokeWidth = w);
void _oval(Canvas c, double x, double y, double rx, double ry, Color col) =>
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2), _fill..color = col);

/// A tapered limb from [a] (radius [ra]) to [b] (radius [rb]), with a soft bulge.
Path limbPath(Pt a, Pt b, double ra, double rb, [double bul = 0]) {
  final dx = b.x - a.x, dy = b.y - a.y;
  var l = hypot(dx, dy);
  if (l == 0) l = 1e-6;
  final ux = dx / l, uy = dy / l, nx = -uy, ny = ux;
  final mx = a.x + dx * 0.4, my = a.y + dy * 0.4, rm = (ra + (rb - ra) * 0.4 + bul) * 1.08, an = math.atan2(uy, ux);
  return Path()
    ..moveTo(a.x + nx * ra, a.y + ny * ra)
    ..quadraticBezierTo(mx + nx * rm, my + ny * rm, b.x + nx * rb, b.y + ny * rb)
    ..arcTo(Rect.fromCircle(center: Offset(b.x, b.y), radius: rb), an + math.pi / 2, -math.pi, false)
    ..quadraticBezierTo(mx - nx * rm, my - ny * rm, a.x - nx * ra, a.y - ny * ra)
    ..arcTo(Rect.fromCircle(center: Offset(a.x, a.y), radius: ra), an - math.pi / 2, -math.pi, false)
    ..close();
}

/// Cel shading: dark outline, a light edge toward the low sun (upper left)
/// and a shade edge on the lower right. [pal] is base, shade, light.
void cel(Canvas c, Path p, List<Color> pal, bool sil, {double fx = 1, double kl = 1.1, double kd = 2.1, double ow = 2.6}) {
  if (sil) {
    c.drawPath(p, _sil);
    return;
  }
  _strokePath(c, p, Pal.outline, ow);
  _fillPath(c, p, pal[2]);
  c.save();
  c.translate(kl * fx, -kl);
  c.clipPath(p);
  c.translate(-kl * fx, kl);
  _fillPath(c, p, pal[1]);
  c.translate(-kd * fx, kd);
  _fillPath(c, p, pal[0]);
  c.restore();
}

final Path _shirt = Path()
  ..moveTo(-5, 32.5)
  ..cubicTo(-9, 31.5, -13.5, 29.8, -16, 26.6)
  ..cubicTo(-18.2, 23.5, -17.6, 18, -16.4, 14.5)
  ..cubicTo(-14.6, 6, -12.2, -2, -12.4, -8)
  ..cubicTo(-12.8, -12, -14, -15.5, -14.2, -18)
  ..cubicTo(-6, -20.2, 6, -20.2, 14.2, -18)
  ..cubicTo(14, -15.5, 12.8, -12, 12.4, -8)
  ..cubicTo(12.2, -2, 14.6, 6, 16.4, 14.5)
  ..cubicTo(17.6, 18, 18.2, 23.5, 16, 26.6)
  ..cubicTo(13.5, 29.8, 9, 31.5, 5, 32.5)
  ..cubicTo(2.5, 30.6, -2.5, 30.6, -5, 32.5)
  ..close();
final Path _pants = Path()
  ..moveTo(-13.8, -14)
  ..cubicTo(-15.2, -22, -15, -30, -11.5, -34.5)
  ..cubicTo(-7, -37.5, 7, -37.5, 11.5, -34.5)
  ..cubicTo(15, -30, 15.2, -22, 13.8, -14)
  ..close();
final Path _belt = Path()
  ..moveTo(-14.6, -14.2)
  ..cubicTo(-6, -16.6, 6, -16.6, 14.6, -14.2)
  ..lineTo(14.4, -19.6)
  ..cubicTo(6, -22, -6, -22, -14.4, -19.6)
  ..close();
final Path _neck = limbPath(Pt(0, 27), Pt(0, 37), 3.9, 3.6);

/// A deep shell that covers the back of the head.
final Path _helmet = Path()
  ..moveTo(-10.9, -5.0)
  ..cubicTo(-12.6, 3.5, -8.6, 13.8, 0, 14)
  ..cubicTo(8.6, 13.8, 12.6, 3.5, 10.9, -5.0)
  ..cubicTo(6.5, -7.2, -6.5, -7.2, -10.9, -5.0)
  ..close();
final Path _hairBase = ellipsePath(0, -3.8, 7.9, 5.4);
final Path _hairShort = ellipsePath(0, -3.3, 7.5, 4.5);

/// Toe points to +x, origin under the ball of the foot.
final Path _shoe = Path()
  ..moveTo(-6.8, 7.2)
  ..cubicTo(-4.5, 9.8, -0.5, 9.8, 1.2, 8.4)
  ..cubicTo(3.5, 6.6, 6.5, 4.6, 8.2, 2.6)
  ..cubicTo(9.2, 1.3, 8.6, -0.6, 7.2, -1.0)
  ..cubicTo(4.0, -1.8, -2.0, -1.6, -5.0, -0.6)
  ..cubicTo(-7.4, 0.2, -8.2, 3.2, -7.6, 5.2)
  ..close();
final Path _bagBody = Path()
  ..moveTo(-5.2, -1.4)
  ..lineTo(5.2, -1.4)
  ..cubicTo(6.4, -6, 6.6, -10.5, 4.6, -12.6)
  ..cubicTo(2, -14, -2, -14, -4.6, -12.6)
  ..cubicTo(-6.6, -10.5, -6.4, -6, -5.2, -1.4)
  ..close();

class ClimberPainter {
  const ClimberPainter();

  /// Draws the whole climber. With [sil] every shape is filled black (the shadow).
  void draw(Canvas c, Pose p, Gear gear, Look look, {bool sil = false}) {
    _leg(c, p.legs[0], 2, look, sil);
    _leg(c, p.legs[1], 3, look, sil);
    _torso(c, p, look, sil);
    _risers(c, p, sil);
    _quickdraws(c, p, gear, sil);
    _chalkBag(c, p, gear, look, sil);
    _arm(c, p.arms[0], 0, p, look, sil);
    _arm(c, p.arms[1], 1, p, look, sil);
    _hair(c, gear, look, sil);
    _head(c, p, look, sil);
  }

  void _leg(Canvas c, LegGeo l, int i, Look look, bool sil) {
    cel(c, limbPath(l.h, l.k, 7.6, 5.8, 0.9), look.pants, sil);
    cel(c, limbPath(l.k, l.a, 5.8, 3.9, 1.3), look.pants, sil);
    if (!sil) {
      final ux = l.k.x - l.h.x, uy = l.k.y - l.h.y;
      var len = hypot(ux, uy);
      if (len == 0) len = 1;
      final nx = -uy / len, ny = ux / len;
      // leg loop of the harness
      final lp = Pt(l.h.x + ux * 0.34, l.h.y + uy * 0.34);
      const w = 7.6;
      final loop = Path()
        ..moveTo(lp.x - nx * w, lp.y - ny * w)
        ..lineTo(lp.x + nx * w, lp.y + ny * w);
      _strokePath(c, loop, Pal.outline, 4.4);
      _strokePath(c, loop, Body.harness[0], 2.6);
      // knee patch
      final ca = math.atan2(l.a.y - l.k.y, l.a.x - l.k.x);
      cel(c, ellipsePath(l.k.x, l.k.y, 3.7, 3.0, ca), look.patch, false, ow: 1.3, kl: 0.6, kd: 1);
      // rolled cuff
      final c0 = Pt(lerpD(l.k.x, l.a.x, 0.8), lerpD(l.k.y, l.a.y, 0.8));
      cel(c, limbPath(c0, l.a, 4.7, 4.5), look.patch, false, ow: 1.8, kl: 0.6, kd: 1.1);
    }
    _shoeAt(c, l, i, look, sil);
  }

  void _shoeAt(Canvas c, LegGeo l, int i, Look look, bool sil) {
    final side = sideOf[i];
    final calf = math.atan2(l.a.y - l.k.y, l.a.x - l.k.x);
    final tilt = l.free ? -0.6 : clampD((calf + math.pi / 2) * side * 0.25, -0.3, 0.3);
    c.save();
    c.translate(l.e.x, l.e.y);
    c.scale(side, 1);
    c.rotate(tilt);
    cel(c, _shoe, look.shoe, sil, fx: side, ow: 2.4, kl: 0.8, kd: 1.4);
    if (!sil) {
      c.save();
      c.clipPath(_shoe);
      _fill.color = hex(0x1d1e24);
      c.drawRect(const Rect.fromLTWH(-10, -3, 20, 4.7), _fill);
      _oval(c, 7.1, 1.6, 3.5, 3.1, hex(0x1d1e24));
      _oval(c, -7.3, 3.4, 2.1, 3.3, hex(0x1d1e24));
      c.drawRect(const Rect.fromLTWH(-6, 1.2, 12, 0.7), _fill..color = rgba(255, 255, 255, 0.18));
      c.restore();
      for (final s in const [
        [-2.4, 8.4, 1.4, 4.0],
        [0.9, 7.4, 4.4, 3.4],
      ]) {
        final strap = Path()
          ..moveTo(s[0], s[1])
          ..lineTo(s[2], s[3]);
        _strokePath(c, strap, Pal.outline, 3.4);
        _strokePath(c, strap, hex(0xe4f4ef), 2);
      }
      c.drawRRect(roundRect(-8.2, 6.2, 1.8, 2.8, 0.8), _fill..color = look.stripe);
    }
    c.restore();
  }

  void _torso(Canvas c, Pose p, Look look, bool sil) {
    c.save();
    c.translate(p.c.x, p.c.y);
    c.rotate(p.tilt);
    c.scale(1 + 0.012 * p.br, 1 + 0.006 * p.br);
    cel(c, _neck, look.skin, sil, ow: 2.2);
    cel(c, _pants, look.pants, sil);
    if (!sil) {
      final seam = rgba(10, 12, 24, 0.45);
      _strokePath(c, Path()..moveTo(0, -21)..quadraticBezierTo(0.6, -30, 0, -36.5), seam, 1);
      for (final s in const [-1.0, 1.0]) {
        final pocket = roundRect(s * 6.5 - 3.4, -29.5, 6.8, 5.6, 1.6);
        c.drawRRect(pocket, _fill..color = rgba(10, 12, 24, 0.22));
        c.drawRRect(
            pocket,
            _stroke
              ..color = seam
              ..strokeWidth = 1);
      }
    }
    cel(c, _shirt, look.shirt, sil);
    if (!sil) {
      final fold = Color.lerp(look.shirt[1], const Color(0xFF000000), 0.42)!.withAlpha(89);
      for (final s in const [-1.0, 1.0]) {
        final blade = ellipseArc(s * 7.6, 16.5, 5.6, 7.4, s * 0.25, s > 0 ? math.pi * 0.55 : math.pi * 0.45,
            s > 0 ? math.pi * 1.3 : -math.pi * 0.3,
            anticlockwise: s < 0);
        _strokePath(c, blade, fold, 1.2);
      }
      _strokePath(c, Path()..moveTo(0, 28.5)..quadraticBezierTo(-0.6, 10, 0, -10), fold, 1.2);
      _strokePath(
          c,
          Path()
            ..moveTo(-11.2, -4)
            ..quadraticBezierTo(-8.4, -7.5, -10.4, -12)
            ..moveTo(11.2, -4)
            ..quadraticBezierTo(8.4, -7.5, 10.4, -12),
          fold,
          1.2);
      // small mountain logo
      _fillPath(
          c,
          Path()
            ..moveTo(-4.4, 19.4)
            ..lineTo(-0.6, 24.6)
            ..lineTo(1.6, 21.8)
            ..lineTo(2.8, 23.2)
            ..lineTo(5.4, 19.4)
            ..close(),
          rgba(255, 244, 232, 0.85));
    }
    cel(c, _belt, Body.harness, sil, ow: 2, kl: 0.6, kd: 1);
    if (!sil) {
      _strokePath(c, Path()..moveTo(-13.6, -17.2)..cubicTo(-6, -19.4, 6, -19.4, 13.6, -17.2), Pal.signal, 1);
      _strokePath(c, Path()..moveTo(-2.6, -14.9)..quadraticBezierTo(0, -10.5, 2.6, -14.9), Body.harness[0], 1.5);
      for (final s in const [-1.0, 1.0]) {
        _strokePath(c, Path()..moveTo(s * 14.2, -18.6)..quadraticBezierTo(s * 15.6, -23.4, s * 8.6, -21.4), Body.harness[0], 1.5);
      }
    }
    c.restore();
  }

  void _risers(Canvas c, Pose p, bool sil) {
    for (var k = 0; k < 2; k++) {
      final l = p.legs[k], a = rot(p.c, p.tilt, (k == 1 ? 1 : -1) * 5.6, -20.6);
      final lp = Pt(l.h.x + (l.k.x - l.h.x) * 0.34, l.h.y + (l.k.y - l.h.y) * 0.34);
      final path = Path()
        ..moveTo(a.x, a.y)
        ..quadraticBezierTo((a.x + lp.x) / 2, (a.y + lp.y) / 2 - 2, lp.x, lp.y);
      if (sil) {
        c.drawPath(path, _silStroke);
        continue;
      }
      _strokePath(c, path, Pal.outline, 3.2);
      _strokePath(c, path, Body.harness[2], 1.7);
    }
  }

  void _quickdraws(Canvas c, Pose p, Gear gear, bool sil) {
    for (var k = 0; k < gear.qd.length; k++) {
      final a = qdAnchor(p, k), q = gear.qd[k].p;
      final dx = q.x - a.x, dy = q.y - a.y;
      var len = hypot(dx, dy);
      if (len == 0) len = 1;
      final ux = dx / len, uy = dy / len;
      final s0 = Pt(a.x + ux * 3, a.y + uy * 3), s1 = Pt(q.x - ux * 3, q.y - uy * 3);
      if (sil) {
        c.drawPath(limbPath(s0, s1, 1.2, 1.2), _sil);
        continue;
      }
      final col = Body.quickdraws[k];
      cel(c, limbPath(s0, s1, 1.25, 1.25), [col, col, col], false, ow: 1.8);
      final ang = math.atan2(uy, ux) - math.pi / 2;
      for (final (at, r) in [(a, 2.3), (q, 2.7)]) {
        c.save();
        c.translate(at.x, at.y);
        c.rotate(ang);
        final ring = Path()..addOval(Rect.fromCenter(center: Offset(0, -r * 0.2), width: r * 1.24, height: r * 2));
        _strokePath(c, ring, Pal.outline, 2.4);
        _strokePath(c, ring, hex(0xc3cad5), 1.1);
        c.restore();
      }
    }
  }

  void _chalkBag(Canvas c, Pose p, Gear gear, Look look, bool sil) {
    final a = bagAnchor(p), b = gear.bag, th = math.atan2(b.x - a.x, a.y - b.y);
    c.save();
    c.translate(a.x, a.y);
    c.rotate(th + p.tilt * 0.3);
    if (sil) {
      c.drawPath(_bagBody, _sil);
      c.restore();
      return;
    }
    cel(c, _bagBody, look.bag, false, ow: 2.2, kl: 0.8, kd: 1.4);
    final band = roundRect(-5.6, -4.2, 11.2, 2.8, 1.2);
    c.drawRRect(band, _fill..color = Body.harness[0]);
    c.drawRRect(
        band,
        _stroke
          ..color = Pal.outline
          ..strokeWidth = 1);
    _oval(c, -1.8, -1.2, 2.6, 0.9, rgba(255, 255, 255, 0.75));
    _strokePath(c, Path()..moveTo(5.4, -5)..quadraticBezierTo(7.6, -7.5, 5.6, -9.6), Body.harness[0], 1.2);
    c.restore();
  }

  void _arm(Canvas c, ArmGeo a, int i, Pose p, Look look, bool sil) {
    cel(c, limbPath(a.s, a.m, 5.4, 4.4, 0.5), look.skin, sil);
    final sl = Pt(lerpD(a.s.x, a.m.x, 0.42), lerpD(a.s.y, a.m.y, 0.42));
    cel(c, limbPath(a.s, sl, 5.9, 5.5, 0.3), look.shirt, sil);
    cel(c, limbPath(a.m, a.w, 4.6, 3.3, 0.9), look.skin, sil);
    _hand(c, a, i, p, look, sil);
  }

  void _hand(Canvas c, ArmGeo a, int i, Pose p, Look look, bool sil) {
    final w = a.w, e = a.e, dir = a.dir, nx = -dir.y, ny = dir.x;
    var tin = ((p.c.x - w.x) * nx + (p.c.y - w.y) * ny).sign;
    if (tin == 0) tin = -sideOf[i];
    final sk = look.skin;
    final fingers = <Path>[];
    if (a.style == HandStyle.grip || a.style == HandStyle.fist) {
      final k = a.style == HandStyle.fist ? HoldType.jug : a.kind;
      final crimp = k == HoldType.crimp, slop = k == HoldType.sloper;
      final back = crimp ? 1.2 : 2.0, top = Pt(e.x - dir.x * back, e.y - dir.y * back);
      cel(c, limbPath(w, top, 3.4, slop ? 4.6 : (crimp ? 3.7 : 4.1), 0.2), sk, sil, ow: 2.2, kl: 0.6, kd: 1.1);
      final sp = slop ? 2.35 : (crimp ? 1.85 : 2.05), lift = crimp ? 1.0 : (slop ? -0.2 : 0.4);
      for (var f = 0; f < 4; f++) {
        final o = (f - 1.5) * sp, l = lift - (f - 1.5).abs() * 0.35;
        final cx = top.x + nx * o + dir.x * l, cy = top.y + ny * o + dir.y * l;
        fingers.add(slop
            ? ellipsePath(cx, cy, 1.15, 2.2, math.atan2(dir.y, dir.x) + math.pi / 2)
            : (Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: 1.45))));
      }
      final tb = Pt(w.x + nx * tin * 3 + dir.x * 2.2, w.y + ny * tin * 3 + dir.y * 2.2);
      final tl = crimp ? 4.2 : 2.8;
      final tt = Pt(tb.x + nx * tin * 1.2 + dir.x * tl, tb.y + ny * tin * 1.2 + dir.y * tl);
      fingers.add(limbPath(tb, tt, 1.5, 1.2));
    } else {
      final pe = Pt(w.x + dir.x * 4.2, w.y + dir.y * 4.2);
      cel(c, limbPath(w, pe, 3.2, 3.7, 0.1), sk, sil, ow: 2.2, kl: 0.6, kd: 1.1);
      for (var f = 0; f < 4; f++) {
        final o = f - 1.5, spread = o * 0.13, cs = math.cos(spread), sn = math.sin(spread);
        final dx = dir.x * cs - dir.y * sn, dy = dir.x * sn + dir.y * cs;
        final b = Pt(pe.x + nx * o * 1.7, pe.y + ny * o * 1.7), len = f == 1 || f == 2 ? 5.0 : 4.3;
        fingers.add(limbPath(b, Pt(b.x + dx * len, b.y + dy * len), 0.95, 0.8));
      }
      final tb = Pt(w.x + dir.x * 1.6 + nx * tin * 2.8, w.y + dir.y * 1.6 + ny * tin * 2.8);
      fingers.add(limbPath(
          tb, Pt(tb.x + (nx * tin * 0.7 + dir.x * 0.7) * 4, tb.y + (ny * tin * 0.7 + dir.y * 0.7) * 4), 1.1, 0.9));
    }
    if (sil) {
      for (final f in fingers) {
        c.drawPath(f, _sil);
      }
      return;
    }
    for (final f in fingers) {
      _strokePath(c, f, Pal.outline, 1.8);
    }
    for (final f in fingers) {
      _fillPath(c, f, sk[0]);
    }
    if (a.style == HandStyle.grip) {
      // chalk on the fingers
      for (final f in fingers.take(4)) {
        _fillPath(c, f, rgba(255, 255, 255, 0.5));
      }
    }
  }

  void _hair(Canvas c, Gear gear, Look look, bool sil) {
    switch (look.hairStyle) {
      case HairStyle.ponytail:
      case HairStyle.braid:
        _tail(c, gear, look, sil);
      case HairStyle.bun:
      case HairStyle.short:
        break; // drawn with the head
    }
  }

  /// A ponytail or a braid that swings: a strip around the gear's hair chain.
  void _tail(Canvas c, Gear gear, Look look, bool sil) {
    final pts = gear.tail, n = pts.length;
    if (n < 2) return;
    final braid = look.hairStyle == HairStyle.braid;
    final left = <Pt>[], right = <Pt>[];
    for (var k = 0; k < n; k++) {
      final a = pts[math.max(0, k - 1)], b = pts[math.min(n - 1, k + 1)];
      var dx = b.x - a.x, dy = b.y - a.y;
      var d = hypot(dx, dy);
      if (d == 0) d = 1;
      dx /= d;
      dy /= d;
      final r = braid ? lerpD(2.5, 1.2, k / (n - 1)) : lerpD(3.1, 0.9, k / (n - 1)) * (k == 1 ? 1.2 : 1);
      left.add(Pt(pts[k].x - dy * r, pts[k].y + dx * r));
      right.add(Pt(pts[k].x + dy * r, pts[k].y - dx * r));
    }
    final p = Path()..moveTo(left[0].x, left[0].y);
    for (var k = 1; k < n; k++) {
      p.quadraticBezierTo(left[k - 1].x, left[k - 1].y, (left[k - 1].x + left[k].x) / 2, (left[k - 1].y + left[k].y) / 2);
    }
    p.lineTo(pts[n - 1].x, pts[n - 1].y);
    for (var k = n - 1; k > 0; k--) {
      p.quadraticBezierTo(right[k].x, right[k].y, (right[k - 1].x + right[k].x) / 2, (right[k - 1].y + right[k].y) / 2);
    }
    p
      ..lineTo(right[0].x, right[0].y)
      ..close();
    if (sil) {
      c.drawPath(p, _sil);
      return;
    }
    cel(c, p, look.hair, false, ow: 2, kl: 0.6, kd: 1);
    if (braid) {
      // the crossings of the braid
      final cross = Path();
      for (var k = 1; k < n - 1; k++) {
        cross
          ..moveTo(left[k].x, left[k].y)
          ..lineTo(lerpD(right[k].x, right[k + 1].x, 0.5), lerpD(right[k].y, right[k + 1].y, 0.5));
      }
      _strokePath(c, cross, look.hair[1], 0.8);
      final end = pts[n - 2];
      c.drawCircle(Offset(end.x, end.y), 1.5, _fill..color = look.stripe);
    } else {
      final strand = Path()..moveTo(pts[0].x - 0.6, pts[0].y);
      for (var k = 1; k < n - 1; k++) {
        strand.lineTo(pts[k].x - 0.6, pts[k].y);
      }
      _strokePath(c, strand, rgba(255, 226, 190, 0.45), 0.9);
    }
    final tie = Rect.fromCenter(center: Offset(pts[0].x, pts[0].y - 0.6), width: braid ? 4.6 : 5.4, height: 3.2);
    c.drawOval(tie, _fill..color = look.shoe[0]);
    c.drawOval(
        tie,
        _stroke
          ..color = Pal.outline
          ..strokeWidth = 1);
  }

  void _head(Canvas c, Pose p, Look look, bool sil) {
    final h = p.head, lx = p.lookX;
    c.save();
    c.translate(h.x, h.y);
    c.rotate(p.tilt * 0.5);
    cel(c, look.hairStyle == HairStyle.short ? _hairShort : _hairBase, look.hair, sil, ow: 2.2);
    for (final s in const [-1.0, 1.0]) {
      final toward = lx * s > 0, ex = s * (8.3 - (toward ? lx.abs() * 0.55 : -lx.abs() * 0.2));
      cel(c, ellipsePath(ex, -5.6, 1.8, 2.7), look.skin, sil, ow: 1.8, kl: 0.4, kd: 0.8);
    }
    if (lx.abs() > 0.8) {
      final s = lx.sign;
      cel(c, ellipsePath(s * 7.6, -7.2, 0.5 + lx.abs() * 0.5, 2.6), look.skin, sil, ow: 1.8, kl: 0.4, kd: 0.8);
    }
    if (look.hairStyle == HairStyle.bun) {
      // a round bun low on the back of the head, with a band around it
      final bx = -lx * 0.8;
      cel(c, ellipsePath(bx, -10.4, 4.9, 4.1), look.hair, sil, ow: 2, kl: 0.6, kd: 1);
      if (!sil) {
        _strokePath(c, Path()..moveTo(bx - 3.6, -7.4)..quadraticBezierTo(bx, -8.8, bx + 3.6, -7.4), look.stripe, 1.3);
        _strokePath(c, Path()..moveTo(bx - 2.2, -11.8)..quadraticBezierTo(bx, -13.2, bx + 2.4, -11.4), look.hair[1], 0.8);
      }
    }
    cel(c, _helmet, look.helmet, sil);
    if (!sil) {
      final sx = -lx * 0.8;
      final dark = hex(0x2b2f3a);
      c.save();
      c.clipPath(_helmet);
      c.drawRect(Rect.fromLTWH(sx - 1.9, -6, 3.8, 22), _fill..color = look.stripe);
      c.drawRRect(roundRect(sx - 1.1, 7.2, 2.2, 4.8, 1.1), _fill..color = dark);
      for (final s in const [-1.0, 1.0]) {
        c.save();
        c.translate(sx + s * 5.6, 6.6);
        c.rotate(-s * 0.42);
        c.drawRRect(roundRect(-1, -2.2, 2, 4.4, 1), _fill..color = dark);
        c.restore();
      }
      // rim of the shell
      _strokePath(c, Path()..moveTo(-11, -4.4)..cubicTo(-6.5, -6.6, 6.5, -6.6, 11, -4.4), rgba(120, 108, 96, 0.55), 1.6);
      c.restore();
      // chin straps
      for (final s in const [-1.0, 1.0]) {
        _strokePath(c, Path()..moveTo(s * 10.2, -4.4)..lineTo(s * 8.2, -10.6), dark, 1.2);
      }
      // fit dial
      c.drawRRect(roundRect(sx - 2.6, -8.3, 5.2, 2.4, 1.1), _fill..color = dark);
      _oval(c, sx, -7.1, 0.8, 0.8, hex(0x8b93a3));
    }
    c.restore();
  }
}

