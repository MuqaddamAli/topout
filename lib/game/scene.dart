// Draws the world: sky, clouds, mountains, the rock wall, holds, ledges and
// lamps, the subtle markers while you aim, particles and the climber.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'art.dart';
import 'climber.dart';
import 'core.dart';
import 'effects.dart';
import 'game.dart';
import 'palette.dart';
import 'remote.dart';

class ScenePainter extends CustomPainter {
  ScenePainter(this.g) : super(repaint: g.frameTick);
  final Game g;
  static const ClimberPainter climber = ClimberPainter();

  final Paint _p = Paint();
  final Paint _s = Paint()..style = PaintingStyle.stroke;
  TextPainter? _label; // the best-height label, kept while its text stays
  ImageShader? _tileShader;
  ui.Image? _tileImage;

  // gradients that only change with the screen size or the route
  ui.Gradient? _vignetteG;
  Size? _vignetteFor;
  ui.Gradient? _lightG;
  ClimbRoute? _lightFor;

  /// Every kind of small hold (with and without chalk and snow) drawn once
  /// into one image; a frame stamps all holds in view with one drawRawAtlas.
  static Baked? _atlas;
  static const double _atlasPx = 5; // atlas pixels per world unit
  static const double _cellL = 18, _cellB = 19, _cellW = 39, _cellH = 32; // a cell around the hold, in units
  Float32List _xf = Float32List(256), _rects = Float32List(256);
  final List<int> _ledges = [];
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.medium;

  /// Other players' climbers are drawn see-through, each in a layer only as big as it.
  final Paint _ghost = Paint()..color = const Color(0x9EFFFFFF);

  /// The lane numbers on the crash pads (yours and the others'), made once.
  final Map<(int, bool), TextPainter> _laneMarks = {};

  /// Name tags of the other climbers, kept while the name stays the same.
  final Map<String, (String, TextPainter)> _names = {};

  /// Turns whatever is drawn into the layer into a see-through black shadow.
  final Paint _shadowLayer = Paint()..colorFilter = const ColorFilter.mode(Color(0x3D000000), BlendMode.srcIn);
  static final ui.Gradient _jug = ui.Gradient.radial(
      Offset.zero, 13, [hex(0xe8e3da), hex(0x8a857d)], null, TileMode.clamp, null, const Offset(-4, 4), 1);
  static final ui.Gradient _crimp = ui.Gradient.linear(const Offset(0, 3), const Offset(0, -3), [hex(0xefeae0), hex(0x79746d)]);
  static final ui.Gradient _sloper = ui.Gradient.radial(
      const Offset(-1, -1), 18, [hex(0xece7dd), hex(0x7c776f)], null, TileMode.clamp, null, const Offset(-5, 3), 1);
  static final ui.Gradient _chip = ui.Gradient.linear(const Offset(0, 3), const Offset(0, -3), [hex(0xc4beb3), hex(0x6f6a63)]);
  static final ui.Gradient _ledge = ui.Gradient.linear(Offset.zero, const Offset(0, -11), [hex(0xa8a39b), hex(0x5f5b56)]);
  static final ui.Gradient _glass =
      ui.Gradient.linear(const Offset(-4, 0), const Offset(4, 0), [hex(0xfff1c4), hex(0xffd27a), hex(0xf2a548)], [0, 0.5, 1]);
  static final ui.Gradient _ledgeShadow =
      ui.Gradient.linear(const Offset(0, -10), const Offset(0, -30), [rgba(8, 10, 16, 0.45), rgba(8, 10, 16, 0)]);
  static final ui.Gradient _footShade =
      ui.Gradient.linear(Offset.zero, const Offset(0, 90), [rgba(8, 10, 16, 0.45), rgba(8, 10, 16, 0)]);
  static final ui.Gradient _earth = ui.Gradient.linear(Offset.zero, const Offset(0, -140), [Pal.earthTop, hex(0x1b1815)]);

  void _fill(Canvas c, Rect r, Color col) => c.drawRect(r, _p..shader = null..color = col);
  void _oval(Canvas c, double x, double y, double rx, double ry, Color col) =>
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2), _p..shader = null..color = col);
  Paint _line(Color col, double w, {StrokeCap cap = StrokeCap.butt}) => _s
    ..color = col
    ..strokeWidth = w
    ..strokeCap = cap
    ..shader = null;

  @override
  void paint(Canvas canvas, Size size) {
    final menu = g.phase == Phase.menu;
    final r = menu ? g.menuRoute : g.route;
    Art.instance.ensure();
    _fill(canvas, Offset.zero & size, Pal.ink);
    if (r == null) return;
    final s = g.scale;
    final sx = g.camShake > 0 ? math.sin(g.clock * 70) * g.camShake : 0.0;
    final sy = g.camShake > 0 ? math.cos(g.clock * 63) * g.camShake : 0.0;
    _sky(canvas, r);
    canvas.save();
    canvas.translate(g.cw / 2 - g.camX * s + sx, g.ch / 2 + g.camY * s + sy);
    canvas.scale(s, -s);
    _wall(canvas, r);
    _ground(canvas, r);
    _holds(canvas, r, menu);
    double? bestY;
    if (!menu) {
      bestY = _bestLine(canvas, r);
      if (g.drag != null) _dragAids(canvas);
      _catchAids(canvas);
    }
    final others = !menu && g.onlineClimb ? _remotes(canvas) : const <RemoteClimber>[];
    final pose = g.pose, gear = g.gear;
    if (pose != null && gear != null) {
      // The climber is recorded once and drawn twice: first as the cast
      // shadow on the rock (sun from the upper left), then for real. The
      // shadow layer is only as big as the climber; an unbounded one would
      // cost a full-screen pass.
      final rec = ui.PictureRecorder();
      climber.draw(Canvas(rec), pose, gear, g.outfit);
      final body = rec.endRecording();
      canvas.saveLayer(_bounds(pose, gear).shift(const Offset(7, -10)), _shadowLayer);
      canvas.translate(7, -10);
      canvas.drawPicture(body);
      canvas.restore();
      canvas.drawPicture(body);
      if (!menu) {
        _rings(canvas, pose);
        _hang(canvas);
        _hint(canvas, pose);
        _catchReach(canvas, pose);
      }
    }
    _catchFlash(canvas);
    _parts(canvas);
    canvas.restore();
    _motes(canvas, r);
    if (others.isNotEmpty || _names.isNotEmpty) _nameTags(canvas, others);
    _vignette(canvas, size);
    if (g.slipFlash > 0) _slipGlow(canvas, size);
    if (!menu) {
      if (bestY != null) _bestLabel(canvas, r, bestY);
      _finger(canvas);
      _catchLabel(canvas);
    }
    if (g.curtain > 0) _fill(canvas, Offset.zero & size, Pal.ink.withAlpha((g.curtain * g.curtain * 235).round()));
  }

  /// The other climbers near the view, behind yours and without a shadow.
  /// Returns the ones drawn.
  List<RemoteClimber> _remotes(Canvas canvas) {
    final v = g.viewRange(), drawn = <RemoteClimber>[];
    for (final o in g.remotes.all) {
      final p = o.pose, gear = o.gear, look = o.look;
      if (p == null || gear == null || look == null) continue;
      // far outside the view: skip it (a climber is about 1.6 m tall)
      if (p.c.x < v.x0 - 100 || p.c.x > v.x1 + 100 || p.c.y < v.y0 - 120 || p.c.y > v.y1 + 120) continue;
      canvas.saveLayer(_bounds(p, gear), _ghost);
      climber.draw(canvas, p, gear, look, lite: true);
      canvas.restore();
      drawn.add(o);
    }
    return drawn;
  }

  /// A name above each climber drawn, in screen space so it stays upright.
  void _nameTags(Canvas canvas, List<RemoteClimber> drawn) {
    _names.removeWhere((id, _) => !g.remotes.byId.containsKey(id));
    for (final o in drawn) {
      var e = _names[o.id];
      if (e == null || e.$1 != o.name) {
        e?.$2.dispose();
        final tp = TextPainter(
          text: TextSpan(text: o.name, style: TextStyle(fontFamily: 'Atkinson', fontSize: 13, fontWeight: FontWeight.w700, color: Pal.chalk)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 140);
        e = _names[o.id] = (o.name, tp);
      }
      final tp = e.$2, head = o.pose!.head, at = g.w2s(head.x, head.y + 20);
      final box = Rect.fromCenter(center: at.translate(0, -tp.height / 2), width: tp.width + 14, height: tp.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)), _p..shader = null..color = rgba(13, 15, 21, 0.62));
      tp.paint(canvas, Offset(box.left + 7, box.top + 3));
    }
  }

  /// Everything the climber draws, with a margin for outlines and shoes.
  static Rect _bounds(Pose p, Gear gear) {
    var x0 = p.c.x, x1 = p.c.x, y0 = p.c.y, y1 = p.c.y;
    void add(Pt q) {
      if (q.x < x0) x0 = q.x;
      if (q.x > x1) x1 = q.x;
      if (q.y < y0) y0 = q.y;
      if (q.y > y1) y1 = q.y;
    }

    for (final a in p.arms) {
      add(a.m);
      add(a.e);
    }
    for (final l in p.legs) {
      add(l.k);
      add(l.e);
    }
    add(p.head);
    add(gear.bag);
    gear.tail.forEach(add);
    return Rect.fromLTRB(x0 - 18, y0 - 18, x1 + 18, y1 + 22);
  }

  /// Dust in the evening light. It drifts slowly and moves a little with the view.
  void _motes(Canvas c, ClimbRoute r) {
    if (g.reducedMotion || (r.endless && g.cd.y > snowY - 400)) return;
    final cw = g.cw, ch = g.ch, shift = g.camY * g.scale * 0.25;
    // four brightness steps, one draw each
    final steps = List.generate(4, (_) => <double>[]);
    for (final m in g.effects.motes) {
      final y = (m.y * ch * 1.1 + shift) % (ch * 1.1) - ch * 0.05;
      final a = 0.5 + 0.5 * math.sin(g.clock * m.f + m.ph);
      steps[(a * 3.99).floor()]
        ..add(m.x * cw)
        ..add(y);
    }
    _dot
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 4; k++) {
      if (steps[k].isEmpty) continue;
      _dot.color = rgba(255, 222, 176, 0.08 + 0.2 * (k + 0.5) / 4);
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(steps[k]), _dot);
    }
  }

  /// The edges of the screen glow red for a moment after a hand slips.
  void _slipGlow(Canvas c, Size size) {
    final cw = size.width, ch = size.height, k = g.slipFlash * g.slipFlash;
    _p
      ..color = const Color(0xFF000000)
      ..shader = ui.Gradient.radial(Offset(cw / 2, ch / 2), math.max(cw, ch) * 0.72,
          [rgba(255, 70, 60, 0), rgba(255, 70, 60, 0.26 * k)], [0.55, 1]);
    c.drawRect(Offset.zero & size, _p);
    _p.shader = null;
  }

  // ---------------------------------------------------------------- sky

  void _sky(Canvas c, ClimbRoute r) {
    final cw = g.cw, ch = g.ch, sc = g.scale;
    final crest = (g.camY - r.topY) * sc + ch / 2;
    if (crest <= -40) return;
    final lim = math.min(ch, crest + 100 * sc), d = g.camY - r.topY;
    final skyRect = Rect.fromLTWH(0, 0, cw, lim);
    _p
      ..shader = ui.Gradient.linear(Offset(0, crest - ch * 1.1), Offset(0, crest + 30 * sc),
          [hex(0x0f1530), hex(0x33386a), hex(0x9a627a), hex(0xf6a873)], [0, 0.45, 0.75, 1])
      ..color = const Color(0xFF000000);
    c.drawRect(skyRect, _p);
    _p.shader = null;
    final art = Art.instance;
    for (final st in art.stars) {
      final y = crest - 160 - st.y * ch * 0.9;
      if (y < 0 || y > crest - 120) continue;
      final al = (0.25 + 0.35 * (0.5 + 0.5 * math.sin(g.clock * 1.5 + st.p))) * math.min(1.0, (crest - 120 - y) / 220);
      _fill(c, Rect.fromLTWH(st.x * cw, y, st.s, st.s), rgba(255, 248, 235, al));
    }
    final sunX = cw * 0.2, sunY = ch / 2 + (0.2 * d - 160) * sc;
    _p.color = const Color(0xFF000000);
    _p.shader = ui.Gradient.radial(Offset(sunX, sunY), math.max(cw, ch) * 0.6,
        [rgba(255, 205, 150, 0.6), rgba(255, 160, 120, 0.2), rgba(255, 140, 110, 0)], [0, 0.22, 1]);
    c.drawRect(skyRect, _p);
    _p.shader = null;
    _oval(c, sunX, sunY, 26 * sc, 26 * sc, rgba(255, 226, 190, 0.25));
    _oval(c, sunX, sunY, 15 * sc, 15 * sc, hex(0xffe1b8));
    // clouds, far to near
    final img = Paint()..filterQuality = FilterQuality.medium;
    for (final cl in Art.cloudPlaces) {
      final spr = art.clouds[cl.s], w = spr.w * sc * cl.k, hgt = spr.h * sc * cl.k;
      final y = ch / 2 + (cl.p * d - cl.h) * sc;
      if (y - hgt > crest + 10 || y < -10) continue;
      final span = cw + w + 40, x = ((cl.x * span + g.clock * cl.v * sc) % span) - w - 20;
      img.color = rgba(255, 255, 255, cl.a);
      c.drawImageRect(spr.image, Rect.fromLTWH(0, 0, spr.image.width.toDouble(), spr.image.height.toDouble()),
          Rect.fromLTWH(x, y - hgt, w, hgt), img);
    }
    _birds(c, r, crest);
    const ranges = [
      (0.35, 0x8f6f8c, 85.0, 0.011, 1.7),
      (0.55, 0x5c5079, 105.0, 0.017, 4.1),
      (0.75, 0x373a60, 70.0, 0.026, 7.3),
    ];
    // Big concave anti-aliased paths are slow to fill, so each range is one
    // fill (its warm glow is part of the gradient) and stops just under the
    // summit edge, which dips at most ~111 below the top; the wall covers the rest.
    final bottom = math.min(ch, crest + 130 * sc);
    for (final (p, col, amp, fr, seed) in ranges) {
      final base = ch / 2 + (p * d - (1 - p) * 120) * sc;
      if (base - amp * sc > crest + 100 * sc) continue;
      final path = Path()..moveTo(0, bottom);
      for (var x = 0.0; x <= cw + 10; x += 10) {
        final wx = x / sc + g.camX * p;
        final n = 0.55 + 0.25 * math.sin(wx * fr + seed) + 0.15 * math.sin(wx * fr * 2.7 + seed * 2) + 0.05 * math.sin(wx * fr * 7 + seed);
        path.lineTo(x, base - amp * sc * n);
      }
      path
        ..lineTo(cw, bottom)
        ..close();
      _p
        ..color = const Color(0xFF000000)
        ..shader = ui.Gradient.linear(Offset(0, base - amp * sc * 0.4), Offset(0, base + 30 * sc),
            [hex(col), Color.alphaBlend(rgba(240, 150, 140, 0.22), hex(col))]);
      c.drawPath(path, _p);
      _p.shader = null;
    }
  }

  void _birds(Canvas c, ClimbRoute r, double crest) {
    if (g.effects.birds.isEmpty) return;
    final paint = _line(rgba(42, 32, 64, 0.75), 1.3, cap: StrokeCap.round);
    for (final b in g.effects.birds) {
      final x = b.u * g.cw, y = g.ch / 2 + (0.45 * (g.camY - r.topY) - b.h) * g.scale;
      if (y > crest - 4) continue;
      final s = b.s * g.scale * 0.8, w = math.sin(b.ph) * s * 0.6;
      c.drawPath(
          Path()
            ..moveTo(x - s, y - w)
            ..quadraticBezierTo(x - s * 0.4, y - w * 0.2 - s * 0.2, x, y)
            ..quadraticBezierTo(x + s * 0.4, y - w * 0.2 - s * 0.2, x + s, y - w),
          paint);
    }
  }

  // ---------------------------------------------------------------- wall

  /// The summit: flat where the top ledge is, then the rock falls away to both sides.
  static double wallEdgeY(ClimbRoute r, double x) {
    final a = r.wallLeft + 40, b = r.wallRight - 40;
    final d = x < a ? a - x : (x > b ? x - b : 0.0), f = math.min(1.0, d / 40);
    return r.topY + 1 - math.min(d, 240) * 0.42 + f * (math.sin(x * 0.057 + 1.3) * 7 + math.sin(x * 0.13) * 3);
  }

  void _wall(Canvas c, ClimbRoute r) {
    final v = g.viewRange();
    if (v.y0 > r.topY + 20) return;
    final tile = Art.instance.tile.image;
    if (_tileImage != tile) {
      // first the lazy image, then (on the web) the baked pixels
      _tileImage = tile;
      _tileShader = ImageShader(tile, TileMode.repeated, TileMode.repeated, scaleMatrix(0.55), filterQuality: FilterQuality.low);
    }
    _p
      ..shader = _tileShader
      ..color = const Color(0xFF000000);
    // The summit edge dips at most ~110 below the top. Below that, the whole
    // view is rock, so a plain rectangle does and nothing needs clipping.
    final summit = v.y1 > r.topY - 120;
    c.save();
    if (summit) {
      final edge = Path()..moveTo(v.x0, -500);
      for (var x = v.x0; x <= v.x1 + 8; x += 8) {
        edge.lineTo(x, wallEdgeY(r, x));
      }
      edge
        ..lineTo(v.x1 + 8, -500)
        ..close();
      c.drawPath(edge, _p);
      c.clipPath(edge);
    } else {
      c.drawRect(Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), _p);
    }
    _p.shader = null;
    // warm light from the low sun on the upper left, shade toward the foot
    final top = math.max(-60.0, v.y0), bottom = math.min(r.topY + 200, v.y1);
    if (_lightFor != r) {
      _lightFor = r;
      // across the whole wall, so the lanes have no seam between them
      _lightG = ui.Gradient.linear(Offset(-220, r.topY + 120), Offset(r.wallRight + 220, -60),
          [rgba(255, 170, 115, 0.26), rgba(255, 170, 115, 0.05), rgba(20, 24, 46, 0.30)], [0, 0.5, 1]);
    }
    _p
      ..color = const Color(0xFF000000)
      ..shader = _lightG;
    c.drawRect(Rect.fromLTRB(v.x0, top, v.x1, bottom), _p);
    _p.shader = null;
    if (r.endless) {
      final a = clampD(((v.y0 + v.y1) / 2 - snowY + 600) / 1800, 0, 0.2);
      if (a > 0) _fill(c, Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), rgba(205, 225, 255, a));
    }
    if (v.y0 < 90) {
      _p
        ..color = const Color(0xFF000000)
        ..shader = _footShade;
      c.drawRect(Rect.fromLTRB(v.x0, 0, v.x1, 90), _p);
      _p.shader = null;
    }
    c.restore();
    if (v.y1 > r.topY - 110) {
      final crest = Path();
      var first = true;
      for (var x = v.x0; x <= v.x1 + 8; x += 8) {
        final y = wallEdgeY(r, x);
        if (first) {
          crest.moveTo(x, y);
          first = false;
        } else {
          crest.lineTo(x, y);
        }
      }
      c.drawPath(crest, _line(rgba(255, 196, 150, 0.7), 2.2));
    }
  }

  void _ground(Canvas c, ClimbRoute r) {
    final v = g.viewRange();
    if (v.y0 > 40) return;
    // the crash pad's place in a lane, mirrored in a mirrored lane
    double padX(Lane l, double x) => l.mirrored ? l.x1 - x : l.x0 + x;
    _p
      ..color = const Color(0xFF000000)
      ..shader = _earth;
    c.drawRect(Rect.fromLTRB(v.x0, -500, v.x1, 0), _p);
    _p.shader = null;
    _fill(c, Rect.fromLTRB(v.x0, -5, v.x1, 0), rgba(0, 0, 0, 0.3));
    final art = Art.instance;
    for (final p in art.pebbles) {
      if (p.x < v.x0 || p.x > v.x1) continue;
      _oval(c, p.x, p.y, p.rx, p.ry, p.light ? hex(0x6b645a) : hex(0x4a443d));
    }
    // grass, swaying a little in the wind
    final grass = Path(), still = g.reducedMotion;
    for (final t in art.tufts) {
      if (t.x < v.x0 || t.x > v.x1) continue;
      final l = r.laneAt(t.x), lx = l.mirrored ? l.x1 - t.x : t.x - l.x0;
      if (lx > 108 && lx < 256) continue;
      final sway = still ? 0.0 : math.sin(g.clock * 1.6 + t.x * 0.05) * 1.6 + math.sin(g.clock * 3.7 + t.x * 0.13) * 0.5;
      for (var k = 0; k < t.n; k++) {
        grass
          ..moveTo(t.x + k * 2, 0)
          ..quadraticBezierTo(t.x + k * 2 + t.lean * 4 + sway * 0.4, t.h * 0.6,
              t.x + k * 2 + t.lean * 7 + (k - 1) * 2 + sway, t.h - sway.abs() * 0.15);
      }
    }
    c.drawPath(grass, _line(Pal.grass, 1.3, cap: StrokeCap.round));
    // a crash pad in each lane
    for (final l in r.lanes) {
      final x = math.min(padX(l, 112), padX(l, 252));
      if (x > v.x1 || x + 140 < v.x0) continue;
      final seam = math.min(padX(l, 181), padX(l, 183));
      _fill(c, Rect.fromLTWH(math.min(padX(l, 114), padX(l, 252)), -24, 138, 6), rgba(0, 0, 0, 0.35));
      c.drawRRect(roundRect(x, -22, 140, 18, 4), _p..color = Pal.pad);
      c.drawRRect(roundRect(x, -6, 140, 7, 3), _p..color = Pal.padTop);
      _fill(c, Rect.fromLTWH(x, -14, 140, 2.2), rgba(242, 237, 228, 0.55));
      _fill(c, Rect.fromLTWH(seam, -22, 2, 16), rgba(0, 0, 0, 0.25));
      if (r.lanes.length > 1) _laneMark(c, l.index, x + 70, l.index == g.spawn?.lane);
    }
  }

  /// "LANE 2" on the front of a lane's crash pad, in orange on your own lane.
  void _laneMark(Canvas c, int lane, double cx, bool yours) {
    final tp = _laneMarks[(lane, yours)] ??= TextPainter(
      text: TextSpan(
        text: 'LANE ${lane + 1}',
        style: TextStyle(
            fontFamily: 'BigShoulders', fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: yours ? Pal.signal : rgba(242, 237, 228, 0.8)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 10;
    c.save();
    c.translate(cx, -13);
    c.scale(1, -1); // the world has y up; text is drawn the right way round
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: tp.height + 2), const Radius.circular(3)),
        _p..color = rgba(13, 15, 21, yours ? 0.8 : 0.55));
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  // ---------------------------------------------------------------- holds

  void _holds(Canvas c, ClimbRoute r, bool menu) {
    final v = g.viewRange(), idx = r.byY, atlas = (_atlas ??= _makeAtlas()).image;
    var n = 0;
    final ledges = _ledges..clear();
    for (var i = r.firstAtOrAbove(v.y0 - 30); i < idx.length; i++) {
      final k = idx[i], h = r.holds[k];
      if (h.y > v.y1 + 60) break;
      if (h.t == HoldType.ground) continue;
      if (h.t.wide) {
        // the lamp's ring of light reaches about 70 past the ledge
        if (h.x2! > v.x0 - 80 && h.x < v.x1 + 80) ledges.add(k);
        continue;
      }
      if (h.x < v.x0 - 20 || h.x > v.x1 + 20) continue;
      final chalk = !menu && g.chalked.contains(k) && h.t != HoldType.chip, snow = r.endless && h.y > snowY;
      // a hold you just grabbed gives a little
      final e = 1 + 0.07 * (menu ? 0.0 : g.grabPulse(k)), k2 = e / _atlasPx;
      if ((n + 1) * 4 > _xf.length) {
        _xf = Float32List(_xf.length * 2)..setAll(0, _xf);
        _rects = Float32List(_rects.length * 2)..setAll(0, _rects);
      }
      final cell = _cellOf(h.t, chalk, snow), cx = (cell % 4) * _cellW * _atlasPx, cy = (cell ~/ 4) * _cellH * _atlasPx;
      _xf
        ..[n * 4] = k2
        ..[n * 4 + 1] = 0
        ..[n * 4 + 2] = h.x - _cellL * e
        ..[n * 4 + 3] = h.y - _cellB * e;
      _rects
        ..[n * 4] = cx
        ..[n * 4 + 1] = cy
        ..[n * 4 + 2] = cx + _cellW * _atlasPx
        ..[n * 4 + 3] = cy + _cellH * _atlasPx;
      n++;
    }
    if (n > 0) {
      c.drawRawAtlas(atlas, Float32List.sublistView(_xf, 0, n * 4), Float32List.sublistView(_rects, 0, n * 4), null, null,
          null, _atlasPaint);
    }
    for (final k in ledges) {
      _ledgeAt(c, r, r.holds[k], k, menu);
    }
  }

  static int _cellOf(HoldType t, bool chalk, bool snow) {
    final type = switch (t) { HoldType.jug => 0, HoldType.crimp => 1, HoldType.sloper => 2, _ => 3 };
    return type * 4 + (chalk ? 1 : 0) + (snow ? 2 : 0);
  }

  /// Draws each small hold into its cell of the atlas. The world has y up and
  /// the scene flips it; the cells are not flipped, so the two flips cancel.
  Baked _makeAtlas() => bake((4 * _cellW * _atlasPx).ceil(), (4 * _cellH * _atlasPx).ceil(), (c) {
    for (final t in const [HoldType.jug, HoldType.crimp, HoldType.sloper, HoldType.chip]) {
      for (final chalk in const [false, true]) {
        for (final snow in const [false, true]) {
          final cell = _cellOf(t, chalk, snow);
          c.save();
          c.translate(((cell % 4) * _cellW + _cellL) * _atlasPx, ((cell ~/ 4) * _cellH + _cellB) * _atlasPx);
          c.scale(_atlasPx, _atlasPx);
          _drawHold(c, t, chalk && t != HoldType.chip, snow);
          c.restore();
        }
      }
    }
  });

  static Path holdPath(HoldType t, double x, double y) {
    switch (t) {
      case HoldType.jug:
        return Path()..addOval(Rect.fromCenter(center: Offset(x, y), width: 24, height: 18));
      case HoldType.crimp:
        return Path()..addRRect(roundRect(x - 10, y - 3, 20, 6, 3));
      case HoldType.sloper:
        return Path()
          ..addArc(Rect.fromCenter(center: Offset(x, y - 4), width: 32, height: 20), 0, math.pi)
          ..close();
      case HoldType.chip:
        return Path()
          ..moveTo(x - 6.5, y - 2.5)
          ..lineTo(x + 6.5, y - 2.5)
          ..lineTo(x + 2, y + 3.2)
          ..lineTo(x - 2.5, y + 3)
          ..close();
      default:
        return Path();
    }
  }

  /// One hold at (0, 0) with its shadow, highlights, chalk and snow.
  void _drawHold(Canvas c, HoldType t, bool chalk, bool snow) {
    c.drawPath(holdPath(t, 2.6, -3.4), _p..color = rgba(8, 10, 16, 0.42));
    final shape = holdPath(t, 0, 0);
    _p
      ..shader = switch (t) {
        HoldType.jug => _jug,
        HoldType.crimp => _crimp,
        HoldType.sloper => _sloper,
        _ => _chip,
      }
      ..color = const Color(0xFF000000);
    c.drawPath(shape, _p);
    _p.shader = null;
    c.drawPath(shape, _line(rgba(20, 20, 26, 0.45), 0.8));
    switch (t) {
      case HoldType.jug:
        _oval(c, 0.6, 1.8, 7.6, 3.9, hex(0x25242b));
        c.drawPath(ellipseArc(0.6, 1.8, 7.6, 3.9, 0, math.pi * 1.08, math.pi * 1.92), _line(rgba(255, 255, 255, 0.92), 1.7));
        _oval(c, -3, 5.5, 4, 1.6, rgba(255, 255, 255, 0.22));
      case HoldType.crimp:
        _fill(c, const Rect.fromLTWH(-8.5, 1.4, 17, 1.6), rgba(255, 255, 255, 0.9));
        _fill(c, const Rect.fromLTWH(-8, -2.9, 16, 1.2), rgba(25, 25, 30, 0.55));
      case HoldType.sloper:
        _oval(c, -2.5, 3.5, 8.5, 2.6, rgba(255, 255, 255, 0.38));
      case HoldType.chip:
        _oval(c, 0, 2.4, 4.2, 1.1, rgba(15, 15, 18, 0.5));
      default:
        break;
    }
    if (chalk) {
      // chalk left by your hands
      final white = rgba(255, 255, 255, 0.55);
      if (t == HoldType.jug) {
        _oval(c, -2, 4.4, 5.5, 1.8, white);
        _oval(c, 3.5, 4.8, 2.4, 1.2, white);
      } else if (t == HoldType.crimp) {
        _oval(c, -1, 2.4, 6.5, 1.1, white);
      } else {
        _oval(c, 0, 4.6, 8, 2.2, white);
      }
    }
    if (snow) {
      final white = rgba(248, 250, 255, 0.92);
      switch (t) {
        case HoldType.jug:
          _oval(c, -1, 8, 9, 2.6, white);
        case HoldType.crimp:
          c.drawRRect(roundRect(-9.5, 2, 19, 2.6, 1.3), _p..color = white);
        case HoldType.sloper:
          _oval(c, 0, 5.2, 12, 3, white);
        case HoldType.chip:
          _oval(c, 0, 3.4, 5, 1.3, white);
        default:
          break;
      }
    }
  }

  void _ledgeAt(Canvas c, ClimbRoute r, Hold h, int k, bool menu) {
    final x2 = h.x2!, w = x2 - h.x, isTop = h.t == HoldType.top;
    c.save();
    c.translate(0, h.y);
    _p
      ..color = const Color(0xFF000000)
      ..shader = _ledgeShadow;
    c.drawRect(Rect.fromLTWH(h.x - 4, -30, w + 8, 21), _p);
    _p.shader = null;
    final plank = Path()
      ..moveTo(h.x - 3, 0)
      ..lineTo(x2 + 3, 0)
      ..lineTo(x2 - 1, -10)
      ..lineTo(h.x + 2, -11)
      ..close();
    _p
      ..shader = _ledge
      ..color = const Color(0xFF000000);
    c.drawPath(plank, _p);
    _p.shader = null;
    c.drawPath(plank, _line(rgba(20, 20, 26, 0.5), 0.8));
    _fill(c, Rect.fromLTWH(h.x - 2, -2.6, w + 4, 2.6), rgba(255, 255, 255, 0.88));
    if (r.endless && h.y > snowY) c.drawRRect(roundRect(h.x - 3, -1, w + 6, 4.5, 2.2), _p..color = rgba(248, 250, 255, 0.95));
    c.save();
    c.clipRect(Rect.fromLTWH(h.x, -9, w, 6));
    final hatch = _line(isTop ? rgba(255, 122, 47, 0.8) : rgba(242, 237, 228, 0.2), 2);
    // only the stripes in view (the top runs across every lane)
    final v = g.viewRange(), lines = Path();
    final skip = math.max(0.0, ((v.x0 - h.x) / 9).floorToDouble());
    for (var x = h.x - 10 + skip * 9; x < math.min(x2 + 10, v.x1 + 10); x += 9) {
      lines
        ..moveTo(x, -9)
        ..lineTo(x + 6, -3);
    }
    c.drawPath(lines, hatch);
    c.restore();
    c.restore();
    if (isTop) {
      // a flag over each lane, where the lane's own top ends
      for (final l in r.lanes) {
        final fx = l.mirrored ? l.x0 + 54 : l.x1 - 54;
        if (fx > v.x0 - 40 && fx < v.x1 + 10) _flag(c, fx, h.y);
      }
    } else if (!r.endless) {
      final mirrored = r.laneAt(h.x).mirrored;
      _lamp(c, mirrored ? x2 - 16 : h.x + 16, h.y, !menu && g.lit.contains(k), k);
    }
  }

  void _flag(Canvas c, double fx, double y) {
    final wave = g.reducedMotion ? 0.0 : 1.0;
    _fill(c, Rect.fromLTWH(fx, y, 2.2, 50), hex(0xd9d2c6));
    final flag = Path()..moveTo(fx + 2.2, y + 50);
    for (var i = 1; i <= 6; i++) {
      flag.lineTo(fx + 2.2 + i * 4.5, y + 50 - i * 1.2 + math.sin(g.clock * 5 - i) * 1.6 * wave);
    }
    for (var i = 6; i >= 1; i--) {
      flag.lineTo(fx + 2.2 + i * 4.5, y + 36 + i * 0.6 + math.sin(g.clock * 5 - i) * 1.6 * wave);
    }
    flag
      ..lineTo(fx + 2.2, y + 34)
      ..close();
    c.drawPath(flag, _p..color = Pal.signal);
  }

  void _lamp(Canvas c, double x, double y, bool lit, int k) {
    final since = lit ? g.clock - (g.litAt[k] ?? -9) : 0.0, on = lit ? clampD(since * 2.5, 0, 1) : 0.0;
    if (lit && since < 1.4 && !g.reducedMotion) {
      // a ring of light spreads out as the lamp comes on
      final e = 1 - math.pow(1 - since / 1.4, 3).toDouble();
      c.drawCircle(Offset(x, y + 7), 10 + e * 56, _line(rgba(255, 210, 122, (1 - e) * 0.55), 1.6));
    }
    if (on > 0) {
      final fl = 1.0 + (g.reducedMotion ? 0.0 : 0.06 * math.sin(g.clock * 13 + k) + 0.03 * math.sin(g.clock * 29 + k * 2));
      final glow = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(x, y + 7), 46 * fl,
            [rgba(255, 200, 110, 0.42 * on), rgba(255, 160, 80, 0.14 * on), rgba(255, 140, 60, 0)], [0, 0.35, 1]);
      c.drawOval(Rect.fromCircle(center: Offset(x, y + 7), radius: 46 * fl), glow);
    }
    final metal = hex(0x3a3d46);
    c.drawRRect(roundRect(x - 4, y + 0.5, 10, 13, 2), _p..color = rgba(8, 10, 16, 0.4));
    c.drawRRect(roundRect(x - 5.2, y, 10.4, 2.4, 1), _p..color = metal);
    final glass = roundRect(x - 3.8, y + 2.4, 7.6, 8.4, 1.2);
    if (on > 0) {
      c.save();
      c.translate(x, 0);
      c.drawRRect(glass.shift(Offset(-x, 0)), _p..shader = _glass..color = const Color(0xFF000000));
      _p.shader = null;
      c.restore();
      _oval(c, x, y + 5.2, 1.3, 2.3, rgba(255, 246, 218, on));
    } else {
      c.drawRRect(glass, _p..color = hex(0x2a3040));
      _fill(c, Rect.fromLTWH(x - 2.6, y + 3.4, 1.2, 6.2), rgba(200, 215, 240, 0.25));
    }
    final frame = _line(metal, 1);
    c.drawPath(
        Path()
          ..moveTo(x - 1.3, y + 2.4)
          ..lineTo(x - 1.3, y + 10.8)
          ..moveTo(x + 1.3, y + 2.4)
          ..lineTo(x + 1.3, y + 10.8),
        frame);
    c.drawPath(
        Path()
          ..moveTo(x - 4.6, y + 10.6)
          ..lineTo(x + 4.6, y + 10.6)
          ..lineTo(x + 2.4, y + 13.4)
          ..lineTo(x - 2.4, y + 13.4)
          ..close(),
        _p..color = metal);
    c.drawPath(Path()..addArc(Rect.fromCircle(center: Offset(x, y + 14.4), radius: 2.2), 0, math.pi), _line(metal, 1.2));
  }

  // ---------------------------------------------------------------- aiming

  /// Subtle markers while you aim: thin rings on holds you can reach, nothing else.
  void _dragAids(Canvas c) {
    final d = g.drag!, h = g.holds, j = g.jointAt(d.i);
    final f = g.reducedMotion ? 1.0 : clampD(d.age / 0.18, 0, 1), fade = 1 - (1 - f) * (1 - f);
    c.drawPath(dashCircle(j.x, j.y, g.climber.reach[d.i], 2, 6), _line(rgba(242, 237, 228, 0.16), 1.2));
    for (final entry in d.status.entries) {
      final hold = h[entry.key], st = entry.value;
      if (hold.t == HoldType.ground || st == HoldStatus.no) continue;
      if (st == HoldStatus.far) {
        if (hold.t.wide) {
          _fill(c, Rect.fromLTWH(hold.x - 3, hold.y - 11, hold.x2! - hold.x + 6, 11), rgba(14, 16, 24, 0.3));
        } else {
          c.drawPath(holdPath(hold.t, hold.x, hold.y), _p..color = rgba(24, 27, 36, 0.4));
        }
        continue;
      }
      if (st == HoldStatus.dyno && holdDist(hold, d.px, d.py) > 90) continue; // jump holds show only near your finger
      final col = st == HoldStatus.good ? Pal.good : (st == HoldStatus.weak ? Pal.weak : Pal.jump);
      final paint = _line(col.withAlpha(((st == HoldStatus.dyno ? 0.6 : 0.55) * 255 * fade).round()), 1.3);
      final rr = hold.t == HoldType.sloper ? 16.0 : 13.5;
      if (hold.t.wide) {
        c.drawPath(
            st == HoldStatus.dyno
                ? dashLine(hold.x, hold.y - 13, hold.x2!, hold.y - 13, 3, 3)
                : (Path()
                  ..moveTo(hold.x, hold.y - 13)
                  ..lineTo(hold.x2!, hold.y - 13)),
            paint);
      } else if (st == HoldStatus.dyno) {
        c.drawPath(dashCircle(hold.x, hold.y, rr, 3, 3), paint);
      } else {
        c.drawCircle(Offset(hold.x, hold.y), rr * (0.85 + 0.15 * fade), paint);
      }
    }
    final pt = d.candPt;
    if (d.candDyno != null && pt != null) {
      final cx = (j.x + pt.x) / 2, cy = math.max(j.y, pt.y) + 40;
      for (var k = 2; k < 13; k++) {
        final u = k / 14;
        final x = (1 - u) * (1 - u) * j.x + 2 * (1 - u) * u * cx + u * u * pt.x;
        final y = (1 - u) * (1 - u) * j.y + 2 * (1 - u) * u * cy + u * u * pt.y;
        _oval(c, x, y, 1.1, 1.1, rgba(124, 200, 255, 0.55));
      }
    }
    if (d.cand >= 0 && h[d.cand].t != HoldType.ground) {
      final hold = h[d.cand], at = d.candOk ? d.candPt! : attachPoint(hold, d.i, d.px);
      c.drawCircle(Offset(at.x, at.y), 17 + math.sin(g.clock * 7) * 1.2,
          _line(d.candOk ? rgba(242, 237, 228, 0.9) : rgba(255, 90, 90, 0.75), 1.8));
      if (d.candOk) {
        final q = d.candDyno != null ? null : quality(hold, d.i);
        final col = q == Quality.good ? Pal.good : (q == Quality.weak ? Pal.weak : Pal.jump);
        _oval(c, at.x + 12, at.y + 12, 2.6, 2.6, col);
      }
    }
  }

  void _rings(Canvas c, Pose pose) {
    for (var i = 0; i < 2; i++) {
      if (g.limbs[i].h == null || g.grip[i] >= 75) continue;
      final e = pose.arms[i].e, f = g.grip[i] / 100, col = f > 0.6 ? Pal.good : (f > 0.3 ? Pal.weak : Pal.bad);
      final rect = Rect.fromCircle(center: Offset(e.x, e.y), radius: 10);
      c.drawCircle(rect.center, 10, _line(rgba(12, 14, 20, 0.35), 2.6));
      c.drawArc(rect, math.pi / 2, -math.pi * 2 * f, false, _line(col, 1.6));
    }
  }

  void _hang(Canvas c) {
    if (!(g.hangT > 0)) return;
    final at = Offset(g.cd.x, g.cd.y), f = clampD(g.hangT / g.hangMax, 0, 1);
    c.drawCircle(at, 44, _line(rgba(12, 14, 20, 0.4), 3));
    c.drawArc(Rect.fromCircle(center: at, radius: 44), math.pi / 2, -math.pi * 2 * f, false, _line(Pal.bad, 2));
  }

  // ---------------------------------------------------------------- catching a fall

  /// How deep the fall is in slow motion, 0 to 1 (the veil and glow fade with it).
  double get _slowness {
    final f = g.fall;
    if (f == null) return 0;
    return clampD((1 - f.slow) / (1 - g.mode.slowMo), 0, 1);
  }

  /// While a falling climber can catch a hold, the wall dims and the holds in
  /// reach glow: green is fine, yellow leaves little grip, red cannot be held
  /// (dashed). The easiest one is the brightest. Wide holds glow along the lip.
  void _catchAids(Canvas c) {
    final f = g.fall, w = _slowness;
    if (f == null || w <= 0) return;
    final v = g.viewRange();
    _fill(c, Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), Pal.ink.withAlpha((72 * w).round()));
    if (!f.window) return;
    final best = f.best, pulse = g.reducedMotion ? 0.0 : math.sin(g.clock * 10) * 2;
    for (final o in f.options) {
      final h = g.holds[o.hold], top = identical(o, best);
      final col = o.left <= 0 ? Pal.bad : (o.left < 30 ? Pal.weak : Pal.good);
      final alpha = (top ? 0.95 : 0.6) * w, width = (h.t.wide ? 3.0 : 1.5) + (top ? 1.0 : 0.0);
      // a soft halo (a wide faint stroke, no blur), then the line itself
      for (final (a, wd) in [(alpha * 0.22, width + 6), (alpha, width)]) {
        final paint = _line(col.withAlpha((a * 255).round()), wd, cap: StrokeCap.round);
        if (h.t.wide) {
          final x0 = math.max(h.x, o.pt.x - Game.catchLip), x1 = math.min(h.x2!, o.pt.x + Game.catchLip);
          if (o.left <= 0 && wd == width) {
            c.drawPath(dashLine(x0, h.y + 2, x1, h.y + 2, 6, 5), paint);
          } else {
            c.drawLine(Offset(x0, h.y + 2), Offset(x1, h.y + 2), paint);
          }
        } else {
          final rad = (h.t == HoldType.sloper ? 17.0 : 15.0) + pulse;
          if (o.left <= 0 && wd == width) {
            c.drawPath(dashCircle(o.pt.x, o.pt.y, rad, 3, 3), paint);
          } else {
            c.drawCircle(Offset(o.pt.x, o.pt.y), rad, paint);
          }
        }
      }
    }
  }

  /// Over the climber: a faint line from the reaching hand to the easiest
  /// hold, and an arc that empties as the fall gets too fast to catch.
  void _catchReach(Canvas c, Pose pose) {
    final f = g.fall, w = _slowness;
    if (f == null || !f.window) return;
    final best = f.best;
    if (best != null) {
      final e = pose.arms[best.i].e;
      c.drawPath(dashLine(e.x, e.y, best.pt.x, best.pt.y, 3, 4), _line(rgba(242, 237, 228, 0.5 * w), 1.2));
    }
    final at = Offset(g.cd.x, g.cd.y), left = clampD(1 + f.v / snatchMaxSpeed, 0, 1);
    c.drawArc(Rect.fromCircle(center: at, radius: 52), math.pi / 2, -math.pi * 2 * left, false,
        _line(rgba(242, 237, 228, 0.7 * w), 2, cap: StrokeCap.round));
  }

  /// A white ring where a falling hand caught a hold.
  void _catchFlash(Canvas c) {
    final cf = g.catchFlash;
    if (cf == null) return;
    final u = clampD(cf.t / 0.4, 0, 1);
    c.drawCircle(Offset(cf.at.x, cf.at.y), 6 + 26 * (1 - (1 - u) * (1 - u)), _line(rgba(255, 255, 255, 0.9 * (1 - u)), 2.4));
  }

  TextPainter? _catchText;

  /// Until the player has caught a fall once, say what to do.
  void _catchLabel(Canvas c) {
    final f = g.fall, best = f?.best;
    if (f == null || !f.window || best == null || g.store.getBool('tip.catch', false)) return;
    final tp = _catchText ??= TextPainter(
      text: TextSpan(
          text: 'Tap a glowing hold!',
          style: TextStyle(fontFamily: 'Atkinson', fontWeight: FontWeight.w700, fontSize: 15, color: Pal.chalk)),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = g.w2s(best.pt.x, best.pt.y);
    final x = clampD(p.dx - tp.width / 2, 16, g.cw - tp.width - 16), y = clampD(p.dy - 64, 120, g.ch - 220);
    c.drawRRect(roundRect(x - 10, y - 6, tp.width + 20, tp.height + 12, 10), _p
      ..shader = null
      ..color = rgba(12, 14, 20, 0.82 * _slowness));
    tp.paint(c, Offset(x, y));
  }

  /// First move of the lesson: a finger shows the drag.
  void _hint(Canvas c, Pose pose) {
    final r = g.route;
    if (r == null || !r.tutorial || g.moves != 0 || g.drag != null || g.phase != Phase.climb || g.spawn != null) return;
    // the step is the start cluster's, in the lane you are in (mirrored there too)
    final l = r.laneAt(g.cd.x), from = pose.legs[l.mirrored ? 0 : 1].e, u = (g.clock % 2.2) / 1.6;
    if (u > 1) return;
    final tx = l.mirrored ? l.x1 - 210 : l.x0 + 210;
    final e = u * u * (3 - 2 * u), x = lerpD(from.x, tx, e), y = lerpD(from.y, 102, e);
    final a = math.sin(math.min(1.0, u * 1.15) * math.pi);
    c.drawPath(dashLine(from.x, from.y, x, y, 2, 4), _line(rgba(242, 237, 228, 0.35 * a), 1.5));
    _oval(c, x, y, 8, 8, rgba(242, 237, 228, 0.55 * a));
  }

  double? _bestLine(Canvas c, ClimbRoute r) {
    final hb = g.bestHeight(r);
    if (hb < 0.5) return null;
    if (!r.endless && hb * unitsPerMetre + 100 >= r.topY - 30) return null;
    final y = hb * unitsPerMetre + 100, v = g.viewRange();
    if (y < v.y0 || y > v.y1) return null;
    // dashes stay fixed on the wall as the view moves
    final x0 = (v.x0 / 21).floorToDouble() * 21;
    c.drawPath(dashLine(x0, y, v.x1, y, 12, 9), _line(rgba(124, 200, 255, 0.55), 1.6));
    return y;
  }

  void _bestLabel(Canvas c, ClimbRoute r, double y) {
    final p = g.w2s(0, y);
    if (p.dy < 100 || p.dy > g.ch - 140) return;
    final text = 'Best ${g.bestHeight(r).toStringAsFixed(1)} m';
    var tp = _label;
    if (tp == null || tp.plainText != text) {
      tp?.dispose();
      tp = _label = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontFamily: 'Atkinson', fontWeight: FontWeight.w700, fontSize: 12, color: Pal.jump)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    c.drawRRect(roundRect(10, p.dy - 22, tp.width + 14, 18, 6), _p..color = rgba(12, 14, 20, 0.78));
    tp.paint(c, Offset(17, p.dy - 13 - tp.height / 2));
  }

  /// Particles grouped by look (kind, size step, alpha step), so all of them
  /// take a handful of drawRawPoints calls instead of one call each.
  final Paint _dot = Paint();

  void _parts(Canvas c) {
    if (g.effects.parts.isEmpty) return;
    final batches = <int, List<double>>{};
    for (final p in g.effects.parts) {
      final k = 1 - p.t / p.max;
      // size in steps of half a unit, alpha in eighths
      final double size = switch (p.kind) {
        PartKind.chalk => p.r * (1 + p.t * 3) * 2,
        PartKind.dust => p.r * (1 + p.t * 2.5) * 2,
        PartKind.snow || PartKind.pebble => p.r,
        PartKind.spark => 2.4,
      };
      final alpha = p.kind == PartKind.snow ? 8 : (k * 8).ceil().clamp(1, 8);
      final key = (p.kind.index * 64 + (size * 2).round().clamp(1, 63)) * 16 + alpha;
      (batches[key] ??= [])
        ..add(p.x)
        ..add(p.y);
    }
    batches.forEach((key, pts) {
      final alpha = (key % 16) / 8, size = (key ~/ 16 % 64) / 2, kind = PartKind.values[key ~/ 16 ~/ 64];
      _dot
        ..strokeWidth = size
        ..strokeCap = kind == PartKind.chalk || kind == PartKind.dust ? StrokeCap.round : StrokeCap.square
        ..color = switch (kind) {
          PartKind.chalk => rgba(250, 248, 242, 0.55 * alpha),
          PartKind.dust => rgba(150, 140, 128, 0.45 * alpha),
          PartKind.snow => rgba(245, 248, 255, 0.8),
          PartKind.spark => rgba(255, 200, 110, alpha),
          PartKind.pebble => rgba(120, 116, 110, alpha),
        };
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), _dot);
    });
  }

  void _vignette(Canvas c, Size size) {
    final cw = size.width, ch = size.height;
    if (_vignetteFor != size) {
      _vignetteFor = size;
      _vignetteG = ui.Gradient.radial(Offset(cw / 2, ch * 0.5), math.max(cw, ch) * 0.75,
          [rgba(6, 8, 14, 0), rgba(6, 8, 14, 0.5)], null, TileMode.clamp, null, Offset(cw / 2, ch * 0.45), math.min(cw, ch) * 0.35);
    }
    _p
      ..color = const Color(0xFF000000)
      ..shader = _vignetteG;
    c.drawRect(Offset.zero & size, _p);
    _p.shader = null;
  }

  void _finger(Canvas c) {
    final d = g.drag, f = d?.finger, aim = d?.aim;
    if (f == null || aim == null) return;
    c.drawPath(dashLine(f.dx, f.dy, aim.dx, aim.dy, 3, 4), _line(rgba(242, 237, 228, 0.3), 1.5));
    c.drawCircle(f, 20, _p..color = rgba(242, 237, 228, 0.14));
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) => oldDelegate.g != g;
}
