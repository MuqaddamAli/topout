// Draws a climber, seen from behind, in their own build and clothes: the
// shape of the body, the top (T-shirt, tank top, hoodie or rolled sleeves),
// the legs (pants, three quarter pants, leggings or joggers) and the head
// (helmet, beanie, headband or sweatband) all come from the climber's
// [Look]. Parts are softly shaded with the light from the upper left and
// have a thin outline in a darker shade of their own colour. Each arm and
// each leg is drawn as one shape: all its outlines first, then its fills,
// so elbows and knees show no seams.
//
// All coordinates are world units with y pointing up. Parts that never change
// shape (torso, shoes, chalk bag) are drawn once per look into small images
// and stamped; the rest is drawn every frame. The scene makes the shadow by
// drawing the same recording again through a colour filter.
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
final Paint _sprite = Paint()..filterQuality = FilterQuality.medium;

/// The outline width, in world units: fine, so it shows the shape without boxing it in.
const double _ow = 0.85;

/// Where the light comes from (upper left; y is up).
const Offset _light = Offset(-0.55, 0.83);

/// A part's outline colour: a darker shade of its own colour.
Color inkOf(List<Color> pal) => Color.lerp(pal[1], const Color(0xFF0D0F17), 0.55)!;

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

/// Soft shading across a part from its lit side ([from]) to its shaded side
/// ([to]): light, base, base, shade. [pal] is base, shade, light.
Shader _shade(Offset from, Offset to, List<Color> pal) =>
    Gradient.linear(from, to, [pal[2], pal[0], pal[0], pal[1]], const [0, 0.36, 0.62, 1]);

/// The outline of [p]: a stroke twice the outline's width, drawn before the
/// fill covers its inner half.
void _line(Canvas c, Path p, List<Color> pal, [double w = _ow]) => _strokePath(c, p, inkOf(pal), w * 2);

/// [p] with its outline and soft shading over [box] (lit at the upper left).
void soft(Canvas c, Path p, List<Color> pal, {Rect? box, double w = _ow, bool lite = false}) {
  _line(c, p, pal, w);
  if (lite) {
    _fillPath(c, p, pal[0]);
    return;
  }
  final b = box ?? p.getBounds();
  c.drawPath(
      p,
      _fill
        ..shader = _shade(Offset(b.left, b.bottom), Offset(b.right, b.top), pal)
        ..color = const Color(0xFF000000));
  _fill.shader = null;
}

/// One piece of an arm or a leg: from [a] to [b], radius [ra] to [rb].
class _Seg {
  _Seg(this.a, this.b, this.ra, this.rb, this.pal, [this.bul = 0]) : path = limbPath(a, b, ra, rb, bul);
  final Pt a, b;
  final double ra, rb, bul;
  final List<Color> pal;
  final Path path;

}

/// Draws pieces as one shape: every outline first, then every fill. All the
/// pieces of one colour share one shading, across the whole limb from its
/// first point to its last, so where they meet (an elbow, a knee) shows no
/// edge.
void _group(Canvas c, List<_Seg> segs, {bool lite = false}) {
  for (final s in segs) {
    _line(c, s.path, s.pal);
  }
  final a = segs.first.a, b = segs.last.b, dx = b.x - a.x, dy = b.y - a.y, l = math.max(1e-6, hypot(dx, dy));
  var n = Offset(-dy / l, dx / l);
  if (n.dx * _light.dx + n.dy * _light.dy < 0) n = -n;
  final m = Offset(a.x + dx * 0.5, a.y + dy * 0.5);
  final shaders = <List<Color>, Shader>{};
  for (final s in segs) {
    if (lite) {
      _fillPath(c, s.path, s.pal[0]);
    } else {
      // across the limb at this piece, with the limb's one direction
      final r = math.max(s.ra, s.rb) + s.bul, mid = Offset((s.a.x + s.b.x) / 2, (s.a.y + s.b.y) / 2);
      final along = (mid - m).dx * dx / l + (mid - m).dy * dy / l;
      final centre = m + Offset(dx / l, dy / l) * along;
      final shader = segs.length == 1 ? _shade(centre + n * r, centre - n * r, s.pal) : shaders.putIfAbsent(s.pal, () => _shade(m + n * r * 1.1, m - n * r * 1.1, s.pal));
      c.drawPath(
          s.path,
          _fill
            ..shader = shader
            ..color = const Color(0xFF000000));
    }
  }
  _fill.shader = null;
}

Pt _along(Pt a, Pt b, double t) => Pt(lerpD(a.x, b.x, t), lerpD(a.y, b.y, t));

/// A band round a limb from [a] to [b], between [t0] and [t1] of the way,
/// [r0] to [r1] wide: a cuff, a hem or a wristband. Its ends are straight
/// across, not round, so it reads as cloth and not as a joint.
void _band(Canvas c, Pt a, Pt b, double t0, double t1, double r0, double r1, List<Color> pal, {bool lite = false}) {
  final dx = b.x - a.x, dy = b.y - a.y, l = math.max(1e-6, hypot(dx, dy)), nx = -dy / l, ny = dx / l;
  final p0 = _along(a, b, t0), p1 = _along(a, b, t1);
  final path = Path()
    ..moveTo(p0.x + nx * r0, p0.y + ny * r0)
    ..lineTo(p1.x + nx * r1, p1.y + ny * r1)
    ..quadraticBezierTo(p1.x + dx / l * r1 * 0.35, p1.y + dy / l * r1 * 0.35, p1.x - nx * r1, p1.y - ny * r1)
    ..lineTo(p0.x - nx * r0, p0.y - ny * r0)
    ..quadraticBezierTo(p0.x + dx / l * r0 * 0.35, p0.y + dy / l * r0 * 0.35, p0.x + nx * r0, p0.y + ny * r0)
    ..close();
  _line(c, path, pal, 0.75);
  if (lite) {
    _fillPath(c, path, pal[0]);
    return;
  }
  var n = Offset(nx, ny);
  if (n.dx * _light.dx + n.dy * _light.dy < 0) n = -n;
  final m = Offset((p0.x + p1.x) / 2, (p0.y + p1.y) / 2), r = math.max(r0, r1);
  c.drawPath(
      path,
      _fill
        ..shader = _shade(m + n * r, m - n * r, pal)
        ..color = const Color(0xFF000000));
  _fill.shader = null;
}

/// A part drawn once at [px] pixels per unit into an image, with the box
/// [box] (local units, y up). Drawn back with [stamp].
class _Sprite {
  _Sprite(this.box, void Function(Canvas c) draw, {double px = 8})
      : _baked = bake((box.width * px).ceil(), (box.height * px).ceil(), (c) {
          // not flipped: image rows grow with y, and the scene's y flip turns it upright
          c.scale(px, px);
          c.translate(-box.left, -box.top);
          draw(c);
        });
  final Rect box;
  final Baked _baked;

  void stamp(Canvas c) {
    final image = _baked.image;
    c.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), box, _sprite);
  }
}

/// The parts of one look that never change shape.
class _Sprites {
  _Sprites(Look look)
      : torso = _Sprite(const Rect.fromLTRB(-24, -40, 24, 44), (c) => _drawTorso(c, look)),
        liteTorso = _Sprite(const Rect.fromLTRB(-24, -40, 24, 44), (c) => _drawTorso(c, look, lite: true), px: 5),
        shoes = [
          for (final side in const [-1.0, 1.0])
            _Sprite(const Rect.fromLTRB(-10.5, -3.5, 11, 11.5), (c) => _drawShoe(c, look, side), px: 10),
        ],
        bag = _Sprite(const Rect.fromLTRB(-8.5, -16, 10, 1), (c) => _drawBag(c, look), px: 10);
  final _Sprite torso, liteTorso, bag;
  final List<_Sprite> shoes;

  static final Map<Look, _Sprites> _cache = {};
  static _Sprites of(Look look) => _cache.putIfAbsent(look, () => _Sprites(look));
}

double _smooth(double a, double b, double x) {
  final t = clampD((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
}

/// A point of the torso, made wider at the chest or the waist by [b]: the
/// shoulders take [Build.chest], the waist and hips [Build.waist].
Offset _sh(Build b, double x, double y) => Offset(x * lerpD(b.waist, b.chest, _smooth(-8, 20, y)), y);

/// The shirt's outline (without sleeves; the arms carry those).
Path _shirtPath(Build b) {
  Offset p(double x, double y) => _sh(b, x, y);
  final path = Path();
  void move(Offset o) => path.moveTo(o.dx, o.dy);
  void cubic(Offset a, Offset b2, Offset e) => path.cubicTo(a.dx, a.dy, b2.dx, b2.dy, e.dx, e.dy);
  move(p(-5, 32.5));
  cubic(p(-9, 31.5), p(-13.5, 29.8), p(-16, 26.6));
  cubic(p(-18.2, 23.5), p(-17.6, 18), p(-16.4, 14.5));
  cubic(p(-14.6, 6), p(-12.2, -2), p(-12.4, -8));
  cubic(p(-12.8, -12), p(-14, -15.5), p(-14.2, -18));
  cubic(p(-6, -20.2), p(6, -20.2), p(14.2, -18));
  cubic(p(14, -15.5), p(12.8, -12), p(12.4, -8));
  cubic(p(12.2, -2), p(14.6, 6), p(16.4, 14.5));
  cubic(p(17.6, 18), p(18.2, 23.5), p(16, 26.6));
  cubic(p(13.5, 29.8), p(9, 31.5), p(5, 32.5));
  cubic(p(2.5, 30.6), p(-2.5, 30.6), p(-5, 32.5));
  return path..close();
}

/// A racerback tank top: the shoulder blades stay bare.
Path _tankPath(Build b) {
  Offset p(double x, double y) => _sh(b, x, y);
  final path = Path();
  void cubic(Offset a, Offset b2, Offset e) => path.cubicTo(a.dx, a.dy, b2.dx, b2.dy, e.dx, e.dy);
  void quad(Offset a, Offset e) => path.quadraticBezierTo(a.dx, a.dy, e.dx, e.dy);
  final s = p(-3.6, 31.2);
  path.moveTo(s.dx, s.dy);
  quad(p(-5.4, 21), p(-13.2, 12.5));
  cubic(p(-12.6, 4), p(-12.2, -2), p(-12.4, -8));
  cubic(p(-12.8, -12), p(-14, -15.5), p(-14.2, -18));
  cubic(p(-6, -20.2), p(6, -20.2), p(14.2, -18));
  cubic(p(14, -15.5), p(12.8, -12), p(12.4, -8));
  cubic(p(12.2, -2), p(12.6, 4), p(13.2, 12.5));
  quad(p(5.4, 21), p(3.6, 31.2));
  quad(p(0, 30.4), s);
  return path..close();
}

Path _pantsPath(Build b) {
  final w = b.waist;
  return Path()
    ..moveTo(-13.8 * w, -14)
    ..cubicTo(-15.2 * w, -22, -15 * w, -30, -11.5 * w, -34.5)
    ..cubicTo(-7 * w, -37.5, 7 * w, -37.5, 11.5 * w, -34.5)
    ..cubicTo(15 * w, -30, 15.2 * w, -22, 13.8 * w, -14)
    ..close();
}

Path _beltPath(Build b) {
  final w = b.waist;
  return Path()
    ..moveTo(-14.6 * w, -14.2)
    ..cubicTo(-6 * w, -16.6, 6 * w, -16.6, 14.6 * w, -14.2)
    ..lineTo(14.4 * w, -19.6)
    ..cubicTo(6 * w, -22, -6 * w, -22, -14.4 * w, -19.6)
    ..close();
}

/// A deep shell that covers the back of the head.
final Path _helmet = Path()
  ..moveTo(-10.9, -5.0)
  ..cubicTo(-12.6, 3.5, -8.6, 13.8, 0, 14)
  ..cubicTo(8.6, 13.8, 12.6, 3.5, 10.9, -5.0)
  ..cubicTo(6.5, -7.2, -6.5, -7.2, -10.9, -5.0)
  ..close();

/// The back of a head of hair, without a helmet.
final Path _hairDome = Path()
  ..moveTo(-9.4, -5.6)
  ..cubicTo(-11.2, 3.6, -7.6, 13.2, 0, 13.4)
  ..cubicTo(7.6, 13.2, 11.2, 3.6, 9.4, -5.6)
  ..cubicTo(5.5, -8.2, -5.5, -8.2, -9.4, -5.6)
  ..close();

/// A knitted beanie, and the folded cuff round its bottom.
final Path _beanie = Path()
  ..moveTo(-10.4, -1.2)
  ..cubicTo(-11.8, 7.4, -7.6, 15.6, 0, 15.9)
  ..cubicTo(7.6, 15.6, 11.8, 7.4, 10.4, -1.2)
  ..cubicTo(6, -2.8, -6, -2.8, -10.4, -1.2)
  ..close();
final Path _beanieCuff = Path()
  ..moveTo(-10.9, -3)
  ..cubicTo(-6, -4.8, 6, -4.8, 10.9, -3)
  ..lineTo(10.6, 3)
  ..cubicTo(6, 1.6, -6, 1.6, -10.6, 3)
  ..close();
final Path _hairBase = ellipsePath(0, -3.8, 7.9, 5.4);
final Path _hairNape = ellipsePath(0, -4.2, 7.2, 3.6);

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

  /// Draws the whole climber in world units. [lite] is the cheap version
  /// for other players' see-through climbers: flat colours with no
  /// shading, and no quickdraws or small details. The shape, the clothes
  /// and the colours stay.
  void draw(Canvas c, Pose p, Gear gear, Look look, {bool lite = false}) {
    final sp = _Sprites.of(look);
    _leg(c, p.legs[0], 2, look, sp, lite);
    _leg(c, p.legs[1], 3, look, sp, lite);
    c.save();
    c.translate(p.c.x, p.c.y);
    c.rotate(p.tilt);
    c.scale(1 + 0.012 * p.br, 1 + 0.006 * p.br); // breathing
    (lite ? sp.liteTorso : sp.torso).stamp(c);
    c.restore();
    if (!lite) {
      _risers(c, p, look);
      _quickdraws(c, p, gear);
    }
    final a = bagAnchor(p), b = gear.bag;
    c.save();
    c.translate(a.x, a.y);
    c.rotate(math.atan2(b.x - a.x, a.y - b.y) + p.tilt * 0.3);
    sp.bag.stamp(c);
    c.restore();
    _arm(c, p.arms[0], 0, p, look, lite);
    _arm(c, p.arms[1], 1, p, look, lite);
    if (look.hairStyle == HairStyle.ponytail || look.hairStyle == HairStyle.braid) _tail(c, gear, look, lite: lite);
    _head(c, p, look, lite);
  }

  void _leg(Canvas c, LegGeo l, int i, Look look, _Sprites sp, bool lite) {
    final k = look.build.limb * (look.legs == LegStyle.leggings ? 0.93 : 1), loose = look.legs == LegStyle.joggers ? 1.1 : 1.0;
    final pants = look.pants;
    final thigh = _Seg(l.h, l.k, 7.6 * k * loose, 5.8 * k * loose, pants, 0.9);
    switch (look.legs) {
      case LegStyle.capris:
        // pants to mid-shin, a bare shin, then socks
        final hem = _along(l.k, l.a, 0.5);
        _group(c, [_Seg(l.k, l.a, 5.4 * k, 3.8 * k, look.skin, 1.2)], lite: lite);
        _group(c, [thigh, _Seg(l.k, hem, 5.8 * k * loose, 5.6 * k, pants)], lite: lite);
        _band(c, l.k, l.a, 0.42, 0.52, 6 * k, 5.8 * k, [pants[1], Color.lerp(pants[1], const Color(0xFF000000), 0.2)!, pants[0]], lite: lite);
        _band(c, l.k, l.a, 0.8, 1.02, 4.4 * k, 4.3 * k, look.patch, lite: lite);
      case LegStyle.leggings:
        final shin = _Seg(l.k, l.a, 5.8 * k, 3.9 * k, pants, 1.3);
        _group(c, [thigh, shin], lite: lite);
        if (!lite) {
          // a stripe down the outer side
          final side = sideOf[i], stripe = Path();
          for (final s in [thigh, shin]) {
            final dx = s.b.x - s.a.x, dy = s.b.y - s.a.y, len = math.max(1e-6, hypot(dx, dy));
            var nx = -dy / len, ny = dx / len;
            if (nx * side < 0) {
              nx = -nx;
              ny = -ny;
            }
            stripe
              ..moveTo(s.a.x + nx * s.ra * 0.62, s.a.y + ny * s.ra * 0.62)
              ..lineTo(s.b.x + nx * s.rb * 0.62, s.b.y + ny * s.rb * 0.62);
          }
          _strokePath(c, stripe, look.patch[0], 1.3);
        }
      case LegStyle.joggers:
        _group(c, [thigh, _Seg(l.k, l.a, 6.3 * k, 4.6 * k, pants, 1.4)], lite: lite);
        // gathered at the ankle
        _band(c, l.k, l.a, 0.84, 1.02, 4.9 * k, 4.6 * k, look.patch, lite: lite);
      case LegStyle.pants:
        _group(c, [thigh, _Seg(l.k, l.a, 5.8 * k, 3.9 * k, pants, 1.3)], lite: lite);
        // a rolled cuff
        _band(c, l.k, l.a, 0.8, 0.97, 4.7 * k, 4.5 * k, look.patch, lite: lite);
    }
    if (!lite) {
      // the leg loop of the harness
      final ux = l.k.x - l.h.x, uy = l.k.y - l.h.y, len = math.max(1.0, hypot(ux, uy));
      final nx = -uy / len, ny = ux / len, lp = _along(l.h, l.k, 0.34), w = 7.6 * k * loose;
      final loop = Path()
        ..moveTo(lp.x - nx * w, lp.y - ny * w)
        ..lineTo(lp.x + nx * w, lp.y + ny * w);
      _strokePath(c, loop, inkOf(Body.harness), 3.6);
      _strokePath(c, loop, Body.harness[2], 2.2);
    }
    // the shoe
    final side = sideOf[i];
    final calf = math.atan2(l.a.y - l.k.y, l.a.x - l.k.x);
    final tilt = l.free ? -0.6 : clampD((calf + math.pi / 2) * side * 0.25, -0.3, 0.3);
    c.save();
    c.translate(l.e.x, l.e.y);
    c.scale(side, 1);
    c.rotate(tilt);
    sp.shoes[side < 0 ? 0 : 1].stamp(c);
    c.restore();
  }

  void _risers(Canvas c, Pose p, Look look) {
    for (var k = 0; k < 2; k++) {
      final l = p.legs[k], a = rot(p.c, p.tilt, (k == 1 ? 1 : -1) * 5.6 * look.build.waist, -20.6);
      final lp = _along(l.h, l.k, 0.34);
      final path = Path()
        ..moveTo(a.x, a.y)
        ..quadraticBezierTo((a.x + lp.x) / 2, (a.y + lp.y) / 2 - 2, lp.x, lp.y);
      _strokePath(c, path, inkOf(Body.harness), 2.6);
      _strokePath(c, path, Body.harness[2], 1.5);
    }
  }

  void _quickdraws(Canvas c, Pose p, Gear gear) {
    for (var k = 0; k < gear.qd.length; k++) {
      final a = qdAnchor(p, k), q = gear.qd[k].p;
      final dx = q.x - a.x, dy = q.y - a.y;
      var len = hypot(dx, dy);
      if (len == 0) len = 1;
      final ux = dx / len, uy = dy / len;
      final s0 = Pt(a.x + ux * 3, a.y + uy * 3), s1 = Pt(q.x - ux * 3, q.y - uy * 3);
      final sling = [Body.quickdraws[k], Color.lerp(Body.quickdraws[k], const Color(0xFF000000), 0.3)!, Body.quickdraws[k]];
      _line(c, limbPath(s0, s1, 1.2, 1.2), sling, 0.6);
      _fillPath(c, limbPath(s0, s1, 1.2, 1.2), sling[0]);
      final ang = math.atan2(uy, ux) - math.pi / 2;
      for (final (at, r) in [(a, 2.3), (q, 2.7)]) {
        c.save();
        c.translate(at.x, at.y);
        c.rotate(ang);
        final ring = Path()..addOval(Rect.fromCenter(center: Offset(0, -r * 0.2), width: r * 1.24, height: r * 2));
        _strokePath(c, ring, hex(0x4a5060), 1.9);
        _strokePath(c, ring, hex(0xc9d0da), 0.9);
        c.restore();
      }
    }
  }

  void _arm(Canvas c, ArmGeo a, int i, Pose p, Look look, bool lite) {
    final k = look.build.limb, skin = look.skin, shirt = look.shirt;
    switch (look.top) {
      case TopStyle.hoodie:
        // long sleeves to the wrist, with a ribbed cuff
        _group(c, [_Seg(a.s, a.m, 6 * k, 5 * k, shirt, 0.5), _Seg(a.m, a.w, 5.2 * k, 4 * k, shirt, 0.9)], lite: lite);
        _band(c, a.m, a.w, 0.82, 1.03, 4.4 * k, 4.2 * k, [shirt[1], Color.lerp(shirt[1], const Color(0xFF000000), 0.2)!, shirt[0]], lite: lite);
      case TopStyle.tank:
        _group(c, [_Seg(a.s, a.m, 5.4 * k, 4.4 * k, skin, 0.5), _Seg(a.m, a.w, 4.6 * k, 3.3 * k, skin, 0.9)], lite: lite);
      case TopStyle.tee:
      case TopStyle.rolledTee:
        _group(c, [_Seg(a.s, a.m, 5.4 * k, 4.4 * k, skin, 0.5), _Seg(a.m, a.w, 4.6 * k, 3.3 * k, skin, 0.9)], lite: lite);
        final rolled = look.top == TopStyle.rolledTee, end = rolled ? 0.36 : 0.46;
        final hem = _along(a.s, a.m, end);
        _group(c, [_Seg(a.s, hem, 5.9 * k, 5.6 * k, shirt, 0.2)], lite: lite);
        if (rolled) _band(c, a.s, a.m, end - 0.1, end + 0.02, 6 * k, 5.9 * k, [shirt[2], shirt[0], shirt[0]], lite: lite);
    }
    if (!lite) {
      final band = look.band;
      if (band != null) {
        // a sweatband on the wrist
        _band(c, a.m, a.w, 0.76, 0.98, 4 * k, 3.8 * k, [band, Color.lerp(band, const Color(0xFF000000), 0.25)!, Color.lerp(band, const Color(0xFFFFFFFF), 0.3)!]);
      } else if (look.top == TopStyle.tank && i == 0) {
        // a watch on the left wrist
        _band(c, a.m, a.w, 0.84, 0.96, 3.8 * k, 3.6 * k, [hex(0x2a2d36), hex(0x181a20), hex(0x4a4f5c)]);
      }
    }
    _hand(c, a, i, p, look, lite);
  }

  void _hand(Canvas c, ArmGeo a, int i, Pose p, Look look, bool lite) {
    final w = a.w, e = a.e, dir = a.dir, nx = -dir.y, ny = dir.x, hs = look.build.hand;
    var tin = ((p.c.x - w.x) * nx + (p.c.y - w.y) * ny).sign;
    if (tin == 0) tin = -sideOf[i];
    final sk = look.skin;
    final fingers = <Path>[];
    Path palm;
    if (a.style == HandStyle.grip || a.style == HandStyle.fist) {
      final kind = a.style == HandStyle.fist ? HoldType.jug : a.kind;
      final crimp = kind == HoldType.crimp, slop = kind == HoldType.sloper;
      final back = crimp ? 1.2 : 2.0, top = Pt(e.x - dir.x * back, e.y - dir.y * back);
      palm = limbPath(w, top, 3.4 * hs, (slop ? 4.6 : (crimp ? 3.7 : 4.1)) * hs, 0.2);
      final sp = (slop ? 2.35 : (crimp ? 1.85 : 2.05)) * hs, lift = crimp ? 1.0 : (slop ? -0.2 : 0.4);
      for (var f = 0; f < 4; f++) {
        final o = (f - 1.5) * sp, l = lift - (f - 1.5).abs() * 0.35;
        final cx = top.x + nx * o + dir.x * l, cy = top.y + ny * o + dir.y * l;
        fingers.add(slop
            ? ellipsePath(cx, cy, 1.15 * hs, 2.2 * hs, math.atan2(dir.y, dir.x) + math.pi / 2)
            : (Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: 1.45 * hs))));
      }
      final tb = Pt(w.x + nx * tin * 3 * hs + dir.x * 2.2, w.y + ny * tin * 3 * hs + dir.y * 2.2);
      final tl = (crimp ? 4.2 : 2.8) * hs;
      final tt = Pt(tb.x + nx * tin * 1.2 + dir.x * tl, tb.y + ny * tin * 1.2 + dir.y * tl);
      fingers.add(limbPath(tb, tt, 1.5 * hs, 1.2 * hs));
    } else {
      final pe = Pt(w.x + dir.x * 4.2 * hs, w.y + dir.y * 4.2 * hs);
      palm = limbPath(w, pe, 3.2 * hs, 3.7 * hs, 0.1);
      for (var f = 0; f < 4; f++) {
        final o = f - 1.5, spread = o * 0.13, cs = math.cos(spread), sn = math.sin(spread);
        final dx = dir.x * cs - dir.y * sn, dy = dir.x * sn + dir.y * cs;
        final b = Pt(pe.x + nx * o * 1.7 * hs, pe.y + ny * o * 1.7 * hs), len = (f == 1 || f == 2 ? 5.0 : 4.3) * hs;
        fingers.add(limbPath(b, Pt(b.x + dx * len, b.y + dy * len), 0.95 * hs, 0.8 * hs));
      }
      final tb = Pt(w.x + dir.x * 1.6 + nx * tin * 2.8 * hs, w.y + dir.y * 1.6 + ny * tin * 2.8 * hs);
      fingers.add(limbPath(
          tb, Pt(tb.x + (nx * tin * 0.7 + dir.x * 0.7) * 4 * hs, tb.y + (ny * tin * 0.7 + dir.y * 0.7) * 4 * hs), 1.1 * hs, 0.9 * hs));
    }
    // the hand is one shape too: all outlines, then the fills
    final ink = inkOf(sk);
    _strokePath(c, palm, ink, _ow * 2);
    for (final f in fingers) {
      _strokePath(c, f, ink, _ow * 1.6);
    }
    _fillPath(c, palm, sk[0]);
    for (final f in fingers) {
      _fillPath(c, f, sk[0]);
    }
    if (lite) return;
    if (look.tape) {
      // white tape on the two middle fingers
      for (final f in fingers.skip(1).take(2)) {
        _fillPath(c, f, rgba(246, 244, 238, 0.92));
      }
    }
    if (a.style == HandStyle.grip) {
      // chalk on the fingers
      for (final f in fingers.take(4)) {
        _fillPath(c, f, rgba(255, 255, 255, 0.4));
      }
    }
  }

  /// A ponytail or a braid that swings: a strip around the gear's hair chain.
  void _tail(Canvas c, Gear gear, Look look, {bool lite = false}) {
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
      // a braid tapers; a ponytail is thin at its tie, full, then thin again
      final u = k / (n - 1), r = braid ? lerpD(2.5, 1.2, u) : 0.8 + 2.5 * math.sin(math.pow(u, 0.7) * math.pi * 0.92);
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
    soft(c, p, look.hair, lite: lite);
    if (lite) return;
    if (braid) {
      // the crossings of the braid
      final cross = Path();
      for (var k = 1; k < n - 1; k++) {
        cross
          ..moveTo(left[k].x, left[k].y)
          ..lineTo(lerpD(right[k].x, right[k + 1].x, 0.5), lerpD(right[k].y, right[k + 1].y, 0.5));
      }
      _strokePath(c, cross, look.hair[1], 0.7);
      final end = pts[n - 2];
      c.drawCircle(Offset(end.x, end.y), 1.5, _fill..color = look.stripe);
    } else {
      final strand = Path()..moveTo(pts[0].x - 0.6, pts[0].y);
      for (var k = 1; k < n - 1; k++) {
        strand.lineTo(pts[k].x - 0.6, pts[k].y);
      }
      _strokePath(c, strand, look.hair[2].withValues(alpha: 0.6), 0.8);
    }
    final tie = Rect.fromCenter(center: Offset(pts[0].x, pts[0].y - 0.6), width: braid ? 4.6 : 5.4, height: 3.2);
    c.drawOval(tie, _fill..color = braid ? look.helmet[0] : look.shoe[0]);
    c.drawOval(
        tie,
        _stroke
          ..color = inkOf(look.shoe)
          ..strokeWidth = 0.7);
  }

  void _ears(Canvas c, double lx, Look look) {
    for (final s in const [-1.0, 1.0]) {
      final toward = lx * s > 0, ex = s * (8.3 - (toward ? lx.abs() * 0.55 : -lx.abs() * 0.2));
      final ear = ellipsePath(ex, -5.6, 1.8, 2.7);
      _line(c, ear, look.skin, 0.7);
      _fillPath(c, ear, look.skin[0]);
    }
    if (lx.abs() > 0.8) {
      // a glimpse of the cheek when the head turns
      final s = lx.sign, cheek = ellipsePath(s * 7.6, -7.2, 0.5 + lx.abs() * 0.5, 2.6);
      _line(c, cheek, look.skin, 0.7);
      _fillPath(c, cheek, look.skin[0]);
    }
  }

  void _head(Canvas c, Pose p, Look look, bool lite) {
    final b = look.build, lx = p.lookX, at = rot(p.head, p.tilt, 0, b.neck);
    c.save();
    c.translate(at.x, at.y);
    c.rotate(p.tilt * 0.5);
    c.scale(b.head);
    final dark = hex(0x2b2f3a);
    switch (look.headwear) {
      case Headwear.helmet:
        soft(c, look.hairStyle == HairStyle.short ? _hairNape : _hairBase, look.hair, lite: lite);
        _ears(c, lx, look);
        soft(c, _helmet, look.helmet, lite: lite);
        final sx = -lx * 0.8;
        c.save();
        c.clipPath(_helmet);
        c.drawRect(Rect.fromLTWH(sx - 1.9, -6, 3.8, 22), _fill..color = look.stripe);
        if (!lite) {
          c.drawRRect(roundRect(sx - 1.1, 7.2, 2.2, 4.8, 1.1), _fill..color = dark);
          for (final s in const [-1.0, 1.0]) {
            c.save();
            c.translate(sx + s * 5.6, 6.6);
            c.rotate(-s * 0.42);
            c.drawRRect(roundRect(-1, -2.2, 2, 4.4, 1), _fill..color = dark);
            c.restore();
          }
          // rim of the shell
          _strokePath(c, Path()..moveTo(-11, -4.4)..cubicTo(-6.5, -6.6, 6.5, -6.6, 11, -4.4), rgba(120, 108, 96, 0.5), 1.4);
        }
        c.restore();
        if (!lite) {
          // chin straps and the fit dial
          for (final s in const [-1.0, 1.0]) {
            _strokePath(c, Path()..moveTo(s * 10.2, -4.4)..lineTo(s * 8.2, -10.6), dark, 1.1);
          }
          c.drawRRect(roundRect(sx - 2.6, -8.3, 5.2, 2.4, 1.1), _fill..color = dark);
          _oval(c, sx, -7.1, 0.8, 0.8, hex(0x8b93a3));
        }
      case Headwear.beanie:
        soft(c, _hairNape, look.hair, lite: lite);
        _ears(c, lx, look);
        soft(c, _beanie, look.helmet, lite: lite);
        if (!lite) {
          // knitted ribs, bending round the head as it turns
          c.save();
          c.clipPath(_beanie);
          final ribs = Path();
          for (var x = -12.0; x <= 12; x += 2.4) {
            final x0 = x - lx * 0.8;
            ribs
              ..moveTo(x0, -2)
              ..quadraticBezierTo(x0 * 0.9, 9, x0 * 0.35, 16);
          }
          _strokePath(c, ribs, look.helmet[1].withValues(alpha: 0.55), 0.6);
          c.restore();
        }
        soft(c, _beanieCuff, [look.helmet[1], Color.lerp(look.helmet[1], const Color(0xFF000000), 0.2)!, look.helmet[0]], lite: lite);
        // the pompom
        final pom = Offset(-lx * 0.6, 16.8);
        if (!lite) {
          for (var k = 0; k < 9; k++) {
            final a = k / 9 * math.pi * 2;
            c.drawCircle(pom + Offset(math.cos(a) * 2.6, math.sin(a) * 2.4), 1.5, _fill..color = inkOf([look.stripe, look.stripe, look.stripe]));
          }
        }
        c.drawCircle(pom, 3.4, _fill..color = look.stripe);
        if (!lite) c.drawCircle(pom + const Offset(-0.9, 1), 1.4, _fill..color = Color.lerp(look.stripe, const Color(0xFFFFFFFF), 0.35)!);
      case Headwear.headband:
        _ears(c, lx, look);
        soft(c, _hairDome, look.hair, lite: lite);
        if (!lite) {
          // the shine of straight black hair, and a parting
          _strokePath(c, Path()..moveTo(-5.5, 8.6)..quadraticBezierTo(-1, 11.6, 4.4, 9.4), look.hair[2].withValues(alpha: 0.7), 1.1);
          _strokePath(c, Path()..moveTo(-lx * 0.7, 13)..quadraticBezierTo(-lx * 0.5 - 0.4, 4, -lx * 0.4, -4), look.hair[1], 0.6);
        }
        final band = Path()
          ..moveTo(-10.6, 3.8)
          ..quadraticBezierTo(0, 7.4, 10.6, 3.8)
          ..lineTo(10.3, 7.6)
          ..quadraticBezierTo(0, 11.2, -10.3, 7.6)
          ..close();
        c.save();
        c.clipPath(_hairDome.shift(Offset.zero));
        soft(c, band, look.helmet, lite: lite);
        c.restore();
        // a little bow where the band is tied
        if (!lite) {
          final knot = Offset(-lx * 0.9 + 2.5, 7.6);
          soft(c, ellipsePath(knot.dx - 1.4, knot.dy - 1.2, 1.5, 0.9, 0.6), look.helmet, w: 0.6);
          soft(c, ellipsePath(knot.dx + 1.3, knot.dy - 1.4, 1.4, 0.85, -0.5), look.helmet, w: 0.6);
        }
      case Headwear.sweatband:
        _ears(c, lx, look);
        soft(c, _hairDome, look.hair, lite: lite);
        if (!lite) {
          // short, a bit messy
          final strands = Path();
          for (var k = 0; k < 6; k++) {
            final x = -7 + k * 2.8 - lx * 0.6;
            strands
              ..moveTo(x, 12)
              ..quadraticBezierTo(x * 1.1, 6, x * 1.2 + 0.8, -3);
          }
          _strokePath(c, strands, look.hair[1].withValues(alpha: 0.6), 0.6);
        }
        final band = Path()
          ..moveTo(-10.9, 0.4)
          ..quadraticBezierTo(0, 3.4, 10.9, 0.4)
          ..lineTo(10.6, 4.8)
          ..quadraticBezierTo(0, 8, -10.6, 4.8)
          ..close();
        c.save();
        c.clipPath(Path()..addRect(const Rect.fromLTRB(-13, -9, 13, 14.4)));
        soft(c, band, look.helmet, lite: lite);
        if (!lite) {
          // terry cloth
          for (var x = -9.0; x <= 9; x += 1.8) {
            c.drawCircle(Offset(x - lx * 0.5, 3.1 + 1.4 * (1 - (x / 10) * (x / 10))), 0.35, _fill..color = look.helmet[1]);
          }
        }
        c.restore();
        // the top knot, tied with a band
        final knot = Offset(-lx * 0.7, 15.6);
        soft(c, ellipsePath(knot.dx, knot.dy, 4.7, 4.1), look.hair, lite: lite);
        c.drawRRect(roundRect(knot.dx - 2.6, knot.dy - 4.6, 5.2, 1.8, 0.9), _fill..color = look.helmet[0]);
    }
    c.restore();
  }
}

// ---------------------------------------------------------------- sprites

/// Torso in its own frame (centre at 0, 0): neck, trousers, the top and the
/// harness belt, in the climber's build.
void _drawTorso(Canvas c, Look look, {bool lite = false}) {
  final b = look.build, shirt = look.shirt;
  soft(c, limbPath(Pt(0, 27), Pt(0, 37 + b.neck), 3.9 * b.limb, 3.6 * b.limb), look.skin, lite: lite);
  final pants = _pantsPath(b);
  soft(c, pants, look.pants, lite: lite);
  if (!lite) {
    final seam = Color.lerp(look.pants[1], const Color(0xFF000000), 0.35)!.withValues(alpha: 0.7);
    _strokePath(c, Path()..moveTo(0, -21)..quadraticBezierTo(0.6, -30, 0, -36.5), seam, 0.8);
    for (final s in const [-1.0, 1.0]) {
      final pocket = roundRect(s * 6.5 * b.waist - 3.4, -29.5, 6.8, 5.6, 1.6);
      c.drawRRect(pocket, _fill..color = look.pants[1].withValues(alpha: 0.5));
      c.drawRRect(
          pocket,
          _stroke
            ..color = seam
            ..strokeWidth = 0.8);
    }
  }
  final body = _shirtPath(b), box = body.getBounds();
  switch (look.top) {
    case TopStyle.tank:
      // bare shoulders, then the racerback
      soft(c, body, look.skin, box: box, lite: lite);
      if (!lite) {
        for (final s in const [-1.0, 1.0]) {
          // shoulder blades
          _strokePath(c, ellipseArc(s * 7.4 * b.chest, 19, 5, 6.4, s * 0.25, s > 0 ? math.pi * 0.6 : math.pi * 0.4,
              s > 0 ? math.pi * 1.25 : -math.pi * 0.25,
              anticlockwise: s < 0), look.skin[1].withValues(alpha: 0.6), 0.8);
        }
      }
      soft(c, _tankPath(b), shirt, box: box, lite: lite);
    case TopStyle.tee:
    case TopStyle.rolledTee:
    case TopStyle.hoodie:
      soft(c, body, shirt, box: box, lite: lite);
  }
  if (!lite) {
    final fold = Color.lerp(shirt[1], const Color(0xFF000000), 0.35)!.withValues(alpha: 0.45);
    switch (look.top) {
      case TopStyle.tee:
        for (final s in const [-1.0, 1.0]) {
          final blade = ellipseArc(s * 7.6 * b.chest, 16.5, 5.6, 7.4, s * 0.25, s > 0 ? math.pi * 0.55 : math.pi * 0.45,
              s > 0 ? math.pi * 1.3 : -math.pi * 0.3,
              anticlockwise: s < 0);
          _strokePath(c, blade, fold, 1);
        }
        _strokePath(c, Path()..moveTo(0, 28.5)..quadraticBezierTo(-0.6, 10, 0, -10), fold, 1);
        // a small mountain on the back
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
      case TopStyle.rolledTee:
        // a loose shirt: folds at the sides, and a bolt on the back
        _strokePath(c, Path()..moveTo(-11 * b.waist, 4)..quadraticBezierTo(-7, -2, -9 * b.waist, -12), fold, 1);
        _strokePath(c, Path()..moveTo(11 * b.waist, 4)..quadraticBezierTo(7, -2, 9 * b.waist, -12), fold, 1);
        final bolt = Path()
          ..moveTo(1.6, 26)
          ..lineTo(-4, 15.5)
          ..lineTo(0.2, 15.5)
          ..lineTo(-2.2, 6)
          ..lineTo(4.6, 18)
          ..lineTo(0.4, 18)
          ..close();
        _line(c, bolt, [shirt[1], shirt[1], shirt[1]], 0.6);
        _fillPath(c, bolt, rgba(255, 250, 236, 0.95));
      case TopStyle.hoodie:
        // the hood lying on the back, its lining showing, and a ribbed hem
        Offset p(double x, double y) => _sh(b, x, y);
        final hood = Path()
          ..moveTo(p(-11.5, 28.6).dx, 28.6)
          ..cubicTo(p(-12.8, 20).dx, 20, p(-6.4, 12.6).dx, 12.6, 0, 12.2)
          ..cubicTo(p(6.4, 12.6).dx, 12.6, p(12.8, 20).dx, 20, p(11.5, 28.6).dx, 28.6)
          ..cubicTo(p(6, 31.4).dx, 31.4, p(-6, 31.4).dx, 31.4, p(-11.5, 28.6).dx, 28.6)
          ..close();
        soft(c, hood, [shirt[1], Color.lerp(shirt[1], const Color(0xFF000000), 0.25)!, shirt[0]]);
        final lining = Path()
          ..moveTo(p(-8.6, 28.4).dx, 28.4)
          ..cubicTo(p(-7, 23).dx, 23, p(7, 23).dx, 23, p(8.6, 28.4).dx, 28.4)
          ..cubicTo(p(5, 30.2).dx, 30.2, p(-5, 30.2).dx, 30.2, p(-8.6, 28.4).dx, 28.4)
          ..close();
        _fillPath(c, lining, look.patch[1]);
        _strokePath(c, Path()..moveTo(0, 12.6)..lineTo(0, 22.8), fold, 0.8);
        final hem = Path()
          ..moveTo(-14.3 * b.waist, -18)
          ..cubicTo(-6, -20.2, 6, -20.2, 14.3 * b.waist, -18)
          ..lineTo(14 * b.waist, -15)
          ..cubicTo(6, -17, -6, -17, -14 * b.waist, -15)
          ..close();
        _fillPath(c, hem, shirt[1]);
      case TopStyle.tank:
        _strokePath(c, Path()..moveTo(0, 24)..quadraticBezierTo(-0.5, 8, 0, -10), fold, 0.9);
    }
  }
  final belt = _beltPath(b);
  soft(c, belt, Body.harness, w: 0.7, lite: lite);
  if (lite) return;
  _strokePath(c, Path()..moveTo(-13.6 * b.waist, -17.2)..cubicTo(-6, -19.4, 6, -19.4, 13.6 * b.waist, -17.2), look.stripe, 0.9);
  _strokePath(c, Path()..moveTo(-2.6, -14.9)..quadraticBezierTo(0, -10.5, 2.6, -14.9), Body.harness[2], 1.3);
  for (final s in const [-1.0, 1.0]) {
    _strokePath(c, Path()..moveTo(s * 14.2 * b.waist, -18.6)..quadraticBezierTo(s * 15.6 * b.waist, -23.4, s * 8.6, -21.4), Body.harness[2], 1.3);
  }
}

/// A shoe, toe toward +x. The light is mirrored with the shoe ([side]), so
/// both shoes are lit from the upper left.
void _drawShoe(Canvas c, Look look, double side) {
  final b = _shoe.getBounds();
  _line(c, _shoe, look.shoe, 0.8);
  c.drawPath(
      _shoe,
      _fill
        ..shader = _shade(Offset(side > 0 ? b.left : b.right, b.bottom), Offset(side > 0 ? b.right : b.left, b.top), look.shoe)
        ..color = const Color(0xFF000000));
  _fill.shader = null;
  c.save();
  c.clipPath(_shoe);
  _fill.color = hex(0x1d1e24);
  c.drawRect(const Rect.fromLTWH(-10, -3, 20, 4.4), _fill);
  _oval(c, 7.1, 1.6, 3.5, 3.1, hex(0x1d1e24));
  _oval(c, -7.3, 3.4, 2.1, 3.3, hex(0x1d1e24));
  c.drawRect(const Rect.fromLTWH(-6, 1.2, 12, 0.6), _fill..color = rgba(255, 255, 255, 0.16));
  c.restore();
  for (final s in const [
    [-2.4, 8.4, 1.4, 4.0],
    [0.9, 7.4, 4.4, 3.4],
  ]) {
    final strap = Path()
      ..moveTo(s[0], s[1])
      ..lineTo(s[2], s[3]);
    _strokePath(c, strap, inkOf(look.shoe), 2.6);
    _strokePath(c, strap, hex(0xe8f0ee), 1.6);
  }
  c.drawRRect(roundRect(-8.2, 6.2, 1.8, 2.8, 0.8), _fill..color = look.stripe);
}

/// The chalk bag hanging from its loop (the loop is at 0, 0).
void _drawBag(Canvas c, Look look) {
  soft(c, _bagBody, look.bag, w: 0.8);
  final band = roundRect(-5.6, -4.2, 11.2, 2.8, 1.2);
  c.drawRRect(band, _fill..color = Body.harness[0]);
  _oval(c, -1.8, -1.2, 2.6, 0.9, rgba(255, 255, 255, 0.75));
  _strokePath(c, Path()..moveTo(5.4, -5)..quadraticBezierTo(7.6, -7.5, 5.6, -9.6), Body.harness[2], 1.1);
}
