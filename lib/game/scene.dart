// Draws the world: the backdrop (scenery.dart), the rock wall in the
// mountain's colours, holds (holds.dart), ledges and lamps, chalk marks while
// you aim (chalk.dart), particles, the climber, falling snow, frost and the
// headlamp at night.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'art.dart';
import 'chalk.dart';
import 'climber.dart';
import 'core.dart';
import 'effects.dart';
import 'field_book.dart';
import 'game.dart';
import 'holds.dart';
import 'mountain.dart';
import 'palette.dart';
import 'remote.dart';
import 'scenery.dart';

class ScenePainter extends CustomPainter {
  ScenePainter(this.g) : super(repaint: g.frameTick);
  final Game g;
  static const ClimberPainter climber = ClimberPainter();

  final Paint _p = Paint();
  final Paint _s = Paint()..style = PaintingStyle.stroke;
  TextPainter? _label; // the best-height label, kept while its text stays
  ImageShader? _tileShader, _snowShader;
  ui.Image? _tileImage, _snowImage;
  final Backdrop _backdrop = Backdrop();

  /// This frame's light, colours and snow (from the middle of the view).
  late Light _light;
  late Env _env;
  double _snow = 0;

  // gradients that only change with the screen size or the route
  ui.Gradient? _vignetteG;
  Size? _vignetteFor;

  /// The holds in view are stamped from [HoldArt.atlas]: the rock in one
  /// drawRawAtlas call (tinted), then chalk and snow in another.
  Float32List _xf = Float32List(256), _rects = Float32List(256), _xf2 = Float32List(256), _rects2 = Float32List(256);
  Int32List _cols = Int32List(64), _cols2 = Int32List(64);
  final List<int> _ledges = [];
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.medium;

  /// Other players' climbers are drawn see-through, each in a layer only as big as it.
  final Paint _ghost = Paint()..color = const Color(0x9EFFFFFF);

  /// The lane numbers on the crash pads (yours and the others'), made once.
  final Map<(int, bool), TextPainter> _laneMarks = {};

  /// Speech bubble and friend arrow texts, made once each.
  static final Map<String, TextPainter> _bubbleText = {};
  final Map<String, TextPainter> _arrowText = {};

  /// Name tags of the other climbers, kept while the name stays the same.
  final Map<String, (String, TextPainter)> _names = {};

  /// Turns whatever is drawn into the layer into a see-through shadow (its
  /// strength follows the light).
  final Paint _shadowLayer = Paint();
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
    // the mountain where the view is: the title screen keeps a sunset in
    // the valley band, with no snow
    final hour = menu ? 1.9 : Mountain.hourAt(r, g.camY);
    _env = menu ? Mountain.envAt(0.2, hour) : Mountain.env(r, g.camY);
    _light = Light(hour, _env);
    _snow = menu ? 0.0 : Mountain.snow(r, g.camY);
    final sx = g.camShake > 0 ? math.sin(g.clock * 70) * g.camShake : 0.0;
    final sy = g.camShake > 0 ? math.cos(g.clock * 63) * g.camShake : 0.0;
    _sky(canvas, size, r);
    canvas.save();
    canvas.translate(g.cw / 2 - g.camX * s + sx, g.ch / 2 + g.camY * s + sy);
    canvas.scale(s, -s);
    _wall(canvas, r);
    _ground(canvas, r);
    _blazes(canvas, r);
    _holds(canvas, r, menu);
    double? bestY;
    if (!menu) {
      bestY = _bestLine(canvas, r);
      if (g.drag != null) _farHolds(canvas);
      _catchVeil(canvas);
    }
    final others = !menu && g.onlineClimb ? _remotes(canvas) : const <RemoteClimber>[];
    final pose = g.pose, gear = g.gear;
    if (pose != null && gear != null) {
      // The climber is recorded once and drawn three times: twice as the
      // cast shadow on the rock (a soft edge from two offsets, no blur), then
      // for real. The shadow layers are only as big as the climber; an
      // unbounded one would cost a full-screen pass.
      final rec = ui.PictureRecorder();
      climber.draw(Canvas(rec), pose, gear, g.outfit);
      final body = rec.endRecording(), box = _bounds(pose, gear);
      _shadowLayer.colorFilter = ColorFilter.mode(rgba(6, 8, 20, _light.shadow * 0.55), BlendMode.srcIn);
      for (final o in const [Offset(6, -8.5), Offset(8.5, -11.5)]) {
        canvas.saveLayer(box.shift(o), _shadowLayer);
        canvas.translate(o.dx, o.dy);
        canvas.drawPicture(body);
        canvas.restore();
      }
      canvas.drawPicture(body);
      if (!menu) {
        _hang(canvas);
        _hint(canvas, pose);
        _catchReach(canvas, pose);
      }
    }
    _catchFlash(canvas);
    _parts(canvas);
    canvas.restore();
    if (!g.reducedMotion) g.snowfall.paint(canvas, _snow, _light.snow, s);
    _motes(canvas, r);
    if (!menu && _light.night > 0.01) _headlamp(canvas, size, pose);
    if (!menu) {
      _chalkAids(canvas);
      _catchMarks(canvas);
    }
    if (!menu && (others.isNotEmpty || _names.isNotEmpty || g.chatShown != null)) _labels(canvas, others, pose, gear);
    if (!menu) _frost(canvas, size, Mountain.frost(r, g.camY));
    _vignette(canvas, size);
    if (!menu && g.onlineClimb) _friendArrows(canvas, size);
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

  /// A name above each other climber drawn and a speech bubble above anyone
  /// saying a quick chat phrase (you too), in screen space so they stay
  /// upright in every pose. They sit above the whole body (lying down too),
  /// and labels of climbers in the same spot stack instead of overlapping.
  void _labels(Canvas canvas, List<RemoteClimber> drawn, Pose? mine, Gear? myGear) {
    _names.removeWhere((id, _) => !g.remotes.byId.containsKey(id));
    final placed = <Rect>[];
    Rect free(Rect r) {
      var box = r;
      for (var n = 0; n < 8; n++) {
        final hit = placed.where((o) => o.overlaps(box)).firstOrNull;
        if (hit == null) break;
        box = box.shift(Offset(0, hit.top - box.bottom - 2));
      }
      placed.add(box);
      return box;
    }

    /// Above the body: the screen point over its highest part.
    Offset over(Pose p, Gear gear) {
      final b = _bounds(p, gear);
      return g.w2s((b.left + b.right) / 2, math.max(p.head.y + 20, b.bottom - 14));
    }

    void bubble(Offset at, String text, double age) {
      final tp = _bubbleText[text] ??= TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontFamily: 'Atkinson', fontSize: 14, fontWeight: FontWeight.w700, color: Kit.ink)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 200);
      final fade = clampD(math.min(age / 0.15, (chatShow - age) / 0.4), 0, 1);
      if (fade <= 0) return;
      final box = free(Rect.fromCenter(center: at.translate(0, -tp.height / 2 - 10), width: tp.width + 18, height: tp.height + 10));
      final a = (fade * 240).round();
      _p
        ..shader = null
        ..color = Kit.paper.withAlpha(a);
      // a scrap of paper with a little tail
      canvas.drawRect(box.shift(const Offset(0, 3)), Paint()..color = rgba(0, 0, 0, 0.25 * fade));
      canvas.drawRect(box, _p);
      final tail = Path()
        ..moveTo(box.center.dx - 6, box.bottom - 0.5)
        ..lineTo(box.center.dx + 6, box.bottom - 0.5)
        ..lineTo(box.center.dx, box.bottom + 7)
        ..close();
      canvas.drawPath(tail, _p);
      canvas.saveLayer(box.inflate(2), Paint()..color = Color.fromARGB(a, 255, 255, 255));
      tp.paint(canvas, Offset(box.left + 9, box.top + 5));
      canvas.restore();
    }

    if (mine != null && myGear != null) {
      final said = g.chatShown;
      if (said != null) bubble(over(mine, myGear), said, g.clock - g.chatAt);
    }
    for (final o in drawn) {
      var e = _names[o.id];
      if (e == null || e.$1 != o.name) {
        e?.$2.dispose();
        final tp = TextPainter(
          text: TextSpan(text: o.name, style: FbTxt.typed(12.5, bold: true, color: Kit.ink, height: 1.1)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 140);
        e = _names[o.id] = (o.name, tp);
      }
      final tp = e.$2, at = over(o.pose!, o.gear!);
      final box = free(Rect.fromCenter(center: at.translate(0, -tp.height / 2), width: tp.width + 14, height: tp.height + 6));
      // a little paper name tag
      canvas.drawRect(box.shift(const Offset(0, 2)), _p..shader = null..color = rgba(0, 0, 0, 0.25));
      canvas.drawRect(box, _p..color = Kit.paper.withValues(alpha: 0.92));
      tp.paint(canvas, Offset(box.left + 7, box.top + 3));
      final s = o.shown!, said = s.chat;
      if (said != null) {
        final age = (s.t - s.chatStart) / 1000;
        if (age >= 0 && age < chatShow) bubble(Offset(box.center.dx, box.top - 2), quickChat[said], age);
      }
    }
  }

  /// A small arrow at the screen's edge for each other player out of view,
  /// pointing at them, with their name and height. Kept faint and small.
  void _friendArrows(Canvas canvas, Size size) {
    // inside the HUD: below the top bar and the heights, above the bottom bar
    final inner = Rect.fromLTRB(20, 245, size.width - 20, size.height - 250);
    if (inner.width < 40 || inner.height < 40) return;
    final mid = inner.center;
    for (final o in g.remotes.all) {
      final s = o.shown;
      if (s == null) continue;
      final p = g.w2s(s.c.x, s.c.y + 20);
      if (p.dx > -10 && p.dx < size.width + 10 && p.dy > -10 && p.dy < size.height + 10) continue;
      // where the line from the middle toward them leaves the inner box
      final d = p - mid;
      final k = math.min(d.dx == 0 ? double.infinity : (inner.width / 2) / d.dx.abs(),
          d.dy == 0 ? double.infinity : (inner.height / 2) / d.dy.abs());
      final at = mid + d * k, ang = math.atan2(d.dy, d.dx);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(ang);
      final arrow = Path()
        ..moveTo(9, 0)
        ..lineTo(-5, -6.5)
        ..lineTo(-2, 0)
        ..lineTo(-5, 6.5)
        ..close();
      canvas.drawPath(arrow, _p..shader = null..color = rgba(242, 237, 228, 0.78));
      canvas.restore();
      final text = '${o.name} · ${s.metres.toStringAsFixed(1)} m';
      final tp = _arrowText[text] ??= TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontFamily: 'Atkinson', fontSize: 11, fontWeight: FontWeight.w700, color: rgba(242, 237, 228, 0.85))),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      if (_arrowText.length > 64) _arrowText.clear();
      // the label sits on the inner side of the arrow
      final off = Offset(-math.cos(ang) * 16 - tp.width / 2 - math.cos(ang) * tp.width / 2, -math.sin(ang) * 14 - tp.height / 2);
      final box = Rect.fromLTWH(at.dx + off.dx - 5, at.dy + off.dy - 2, tp.width + 10, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(6)), _p..color = rgba(13, 15, 21, 0.5));
      tp.paint(canvas, Offset(box.left + 5, box.top + 2));
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
    if (g.reducedMotion || _snow > 0.2 || _light.night > 0.6) return;
    final k = (1 - _snow * 5) * (1 - _light.night);
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
    for (var n = 0; n < 4; n++) {
      if (steps[n].isEmpty) continue;
      _dot.color = rgba(255, 222, 176, (0.08 + 0.2 * (n + 0.5) / 4) * k);
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(steps[n]), _dot);
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

  void _sky(Canvas c, Size size, ClimbRoute r) {
    final sc = g.scale, crest = (g.camY - r.topY) * sc + g.ch / 2;
    _backdrop.paint(c, size, _light,
        crest: crest,
        d: g.camY - r.topY,
        sc: sc,
        camX: g.camX,
        clock: g.clock,
        still: g.reducedMotion,
        birds: (c, crest) => _birds(c, r, crest),
        behindRanges: g.phase == Phase.menu && g.screen == Screen.menu ? (c) => _brand(c, size) : null);
  }

  TextPainter? _brandText;
  (double, Color)? _brandFor;

  /// The title screen's poster: TOPOUT, huge, between the sky and the
  /// mountains, so the peaks cover the bottom of the letters. Ink by day,
  /// paper at dusk and night.
  void _brand(Canvas c, Size size) {
    final wide = size.width >= 700, big = wide ? (size.width * 0.2).clamp(160.0, 290.0) : (size.width * 0.35).clamp(110.0, 150.0);
    final col = titleInk(_light.dusk > 0.5 || _light.night > 0.5 ? DayTime.dusk : DayTime.day);
    if (_brandFor != (big, col)) {
      _brandText?.dispose();
      _brandFor = (big, col);
      _brandText = TextPainter(
        text: TextSpan(text: wide ? 'TOPOUT' : 'TOP\nOUT', style: FbTxt.label(big, color: col, spacing: 0.01).copyWith(height: 0.84)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _brandText!;
    tp.paint(c, Offset(wide ? 48 : 18, g.padTop + (wide ? 40 : 34)));
  }

  void _birds(Canvas c, ClimbRoute r, double crest) {
    if (g.effects.birds.isEmpty) return;
    final paint = _line(Color.lerp(_env.far, const Color(0xFF101420), 0.7)!.withValues(alpha: 0.75), 1.3, cap: StrokeCap.round);
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

  /// The rock: the grey texture tinted with the mountain's rock colour, the
  /// snow lying on it, the direct light of the hour, and the shade at its foot.
  void _wall(Canvas c, ClimbRoute r) {
    final v = g.viewRange();
    if (v.y0 > r.topY + 20) return;
    final art = Art.instance, tile = art.tile.image, snowTile = art.snowTile.image;
    if (_tileImage != tile) {
      // first the lazy image, then (on the web) the baked pixels
      _tileImage = tile;
      _tileShader = ImageShader(tile, TileMode.repeated, TileMode.repeated, scaleMatrix(0.55), filterQuality: FilterQuality.low);
    }
    if (_snowImage != snowTile) {
      _snowImage = snowTile;
      _snowShader = ImageShader(snowTile, TileMode.repeated, TileMode.repeated, scaleMatrix(0.55), filterQuality: FilterQuality.low);
    }
    final rock = _env.rock;
    double up(double ch) => math.min(1.0, ch / Art.tileMean);
    _p
      ..shader = _tileShader
      ..color = const Color(0xFF000000)
      ..colorFilter = ColorFilter.mode(Color.from(alpha: 1, red: up(rock.r), green: up(rock.g), blue: up(rock.b)), BlendMode.modulate);
    // The summit edge dips at most ~110 below the top. Below that, the whole
    // view is rock, so a plain rectangle does and nothing needs clipping.
    final summit = v.y1 > r.topY - 120;
    Path? edge;
    if (summit) {
      edge = Path()..moveTo(v.x0, -500);
      for (var x = v.x0; x <= v.x1 + 8; x += 8) {
        edge.lineTo(x, wallEdgeY(r, x));
      }
      edge
        ..lineTo(v.x1 + 8, -500)
        ..close();
    }
    void cover() => edge != null ? c.drawPath(edge, _p) : c.drawRect(Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), _p);
    cover();
    _p.colorFilter = null;
    c.save();
    if (edge != null) c.clipPath(edge);
    if (_snow > 0.02) {
      _p
        ..shader = _snowShader
        ..color = Color.fromRGBO(0, 0, 0, math.min(1.0, _snow * 1.15))
        ..colorFilter = ColorFilter.mode(_light.snow, BlendMode.modulate);
      c.drawRect(Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), _p);
      _p.colorFilter = null;
    }
    _p.shader = null;
    // the hour's light from the upper left, shade toward the lower right;
    // across the whole wall, so the lanes have no seam between them
    final top = math.max(-60.0, v.y0), bottom = math.min(r.topY + 200, v.y1);
    final sun = _light.sun, k = _light.sunK;
    _p
      ..color = const Color(0xFF000000)
      ..shader = ui.Gradient.linear(Offset(-220, r.topY + 120), Offset(r.wallRight + 220, -60),
          [sun.withValues(alpha: k * 1.4), sun.withValues(alpha: k * 0.3), rgba(14, 18, 40, 0.26 + 0.1 * _light.night)], [0, 0.5, 1]);
    c.drawRect(Rect.fromLTRB(v.x0, top, v.x1, bottom), _p);
    _p.shader = null;
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
      // the rim catches the sky's light
      c.drawPath(crest, _line(Color.lerp(_env.skyLow, sun, 0.4)!.withValues(alpha: 0.75), 2.2));
    }
  }

  /// Trail blazes: red, white, red, painted on the rock near the edges of a
  /// lane now and then, the way routes are marked.
  void _blazes(Canvas c, ClimbRoute r) {
    final v = g.viewRange(), img = Art.instance.blaze.image;
    const step = 260.0;
    for (var band = math.max(1, (v.y0 / step).floor()); band * step < math.min(v.y1, r.topY - 120); band++) {
      for (final l in r.lanes) {
        final hsh = Mountain.holdHash(r, band * 13 + l.index * 7919);
        if (hsh > 0.5) continue;
        final left = hsh < 0.25, lx = left ? 13 + hsh * 20 : 347 - (hsh - 0.25) * 20;
        final x = l.mirrored ? l.x1 - lx : l.x0 + lx, y = band * step + 40 + hsh * 300;
        if (x < v.x0 - 20 || x > v.x1 + 20) continue;
        c.save();
        c.translate(x, y);
        c.rotate((hsh - 0.25) * 0.6);
        _p.color = rgba(255, 255, 255, 0.82);
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), const Rect.fromLTWH(-6, -5.5, 12, 11), _p);
        c.restore();
      }
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
    c.drawPath(grass, _line(Color.lerp(Pal.grass, _env.near, 0.35)!, 1.3, cap: StrokeCap.round));
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
        style: FbTxt.label(15, spacing: 0.06, color: yours ? Kit.webbing : Kit.blazeWhite.withValues(alpha: 0.8)),
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
    final v = g.viewRange(), idx = r.byY, atlas = HoldArt.atlas.image;
    var n = 0, m = 0;
    final ledges = _ledges..clear();
    final tint = _argb(_env.hold), snowCol = _light.snow;
    for (var i = r.firstAtOrAbove(v.y0 - 30); i < idx.length; i++) {
      final k = idx[i], h = r.holds[k];
      if (h.y > v.y1 + 60) break;
      if (h.t == HoldType.ground) continue;
      if (h.t.wide) {
        // the lamp's ring of light reaches about 70 past the ledge
        if (h.x2! > v.x0 - 80 && h.x < v.x1 + 80) ledges.add(k);
        continue;
      }
      if (h.x < v.x0 - 24 || h.x > v.x1 + 24) continue;
      final variant = HoldArt.variantOf(k);
      final chalk = !menu && g.chalked.contains(k) && h.t != HoldType.chip, snow = menu ? 0.0 : g.snowOn(k);
      // a hold you just grabbed gives a little
      final e = 1 + 0.07 * (menu ? 0.0 : g.grabPulse(k)), k2 = e / HoldArt.px;
      if ((n + 1) * 4 > _xf.length) {
        _xf = Float32List(_xf.length * 2)..setAll(0, _xf);
        _rects = Float32List(_rects.length * 2)..setAll(0, _rects);
        _cols = Int32List(_cols.length * 2)..setAll(0, _cols);
      }
      if ((m + 2) * 4 > _xf2.length) {
        _xf2 = Float32List(_xf2.length * 2)..setAll(0, _xf2);
        _rects2 = Float32List(_rects2.length * 2)..setAll(0, _rects2);
        _cols2 = Int32List(_cols2.length * 2)..setAll(0, _cols2);
      }
      void put(Float32List xf, Float32List rects, int at, HoldLayer layer, double scale) {
        final (cx, cy) = HoldArt.cell(layer, h.t, variant);
        final q = k2 * scale;
        xf
          ..[at * 4] = q
          ..[at * 4 + 1] = 0
          ..[at * 4 + 2] = h.x - HoldArt.cellL * e * scale
          ..[at * 4 + 3] = h.y - HoldArt.cellB * e * scale;
        rects
          ..[at * 4] = cx
          ..[at * 4 + 1] = cy
          ..[at * 4 + 2] = cx + HoldArt.cellW * HoldArt.px
          ..[at * 4 + 3] = cy + HoldArt.cellH * HoldArt.px;
      }

      put(_xf, _rects, n, HoldLayer.rock, 1);
      _cols[n++] = tint;
      if (chalk) {
        put(_xf2, _rects2, m, HoldLayer.chalk, 1);
        _cols2[m++] = 0xFFFFFFFF;
      }
      if (snow > 0) {
        // the snow shrinks toward the hold and fades as it is brushed off
        put(_xf2, _rects2, m, HoldLayer.snow, 0.55 + 0.45 * snow);
        _cols2[m++] = _argb(snowCol, math.min(1.0, snow * 1.6));
      }
    }
    if (n > 0) {
      c.drawRawAtlas(atlas, Float32List.sublistView(_xf, 0, n * 4), Float32List.sublistView(_rects, 0, n * 4),
          Int32List.sublistView(_cols, 0, n), BlendMode.modulate, null, _atlasPaint);
    }
    if (m > 0) {
      c.drawRawAtlas(atlas, Float32List.sublistView(_xf2, 0, m * 4), Float32List.sublistView(_rects2, 0, m * 4),
          Int32List.sublistView(_cols2, 0, m), BlendMode.modulate, null, _atlasPaint);
    }
    for (final k in ledges) {
      _ledgeAt(c, r, r.holds[k], k, menu);
    }
  }

  /// A colour as the 0xAARRGGBB number drawRawAtlas wants, with alpha [a].
  static int _argb(Color col, [double a = 1]) =>
      ((a * 255).round() << 24) | ((col.r * 255).round() << 16) | ((col.g * 255).round() << 8) | (col.b * 255).round();

  /// A ledge is a shelf of the rock: a lit top you can stand on, a front
  /// face with a ragged lower edge and a crack or two, and its shadow below.
  /// Snow lies along its top where there is snow.
  void _ledgeAt(Canvas c, ClimbRoute r, Hold h, int k, bool menu) {
    final x2 = h.x2!, w = x2 - h.x, isTop = h.t == HoldType.top, v = g.viewRange();
    // only the part in view (the top runs across every lane)
    final a = math.max(h.x - 4, v.x0 - 10), b = math.min(x2 + 4, v.x1 + 10);
    c.save();
    c.translate(0, h.y);
    _p
      ..color = const Color(0xFF000000)
      ..shader = _ledgeShadow;
    c.drawRect(Rect.fromLTWH(math.max(h.x - 4, a), -30, math.min(w + 8, b - a), 21), _p);
    _p.shader = null;
    final seed = k * 1.7;
    double under(double x) => -9.5 - 2.2 * math.sin(x * 0.37 + seed) - 1.3 * math.sin(x * 0.93 + seed * 2) - (x - h.x < 8 || x2 - x < 8 ? 2 : 0);
    final face = Path()..moveTo(a, 0);
    if (a <= h.x - 3) face.lineTo(h.x - 3, 0);
    face.lineTo(math.min(b, x2 + 3), 0);
    final step = isTop ? 10.0 : 6.0;
    for (var x = math.min(b, x2 + 1); x >= a; x -= step) {
      face.lineTo(x, under(x));
    }
    face.close();
    final rock = _env.rock, lit = _env.hold;
    _p
      ..color = const Color(0xFF000000)
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, -12),
          [Color.lerp(lit, rock, 0.45)!, Color.lerp(rock, const Color(0xFF000000), 0.3)!]);
    c.drawPath(face, _p);
    _p.shader = null;
    // a crack or two in the face
    final cracks = Path();
    for (var x = h.x + 18 + (k % 5) * 7.0; x < x2 - 10; x += 37 + (k % 3) * 11) {
      if (x < a || x > b) continue;
      cracks
        ..moveTo(x, -1.5)
        ..lineTo(x + 1.5, -5)
        ..lineTo(x - 0.5, under(x) + 1.5);
    }
    c.drawPath(cracks, _line(rgba(0, 0, 0, 0.3), 0.9));
    // the lit top you stand on, and its edge
    _fill(c, Rect.fromLTRB(math.max(a, h.x - 3), -2.6, math.min(b, x2 + 3), 0), Color.lerp(lit, const Color(0xFFFFFFFF), 0.12)!);
    _fill(c, Rect.fromLTRB(math.max(a, h.x - 3), -0.8, math.min(b, x2 + 3), 0), rgba(255, 255, 255, 0.5));
    final snow = menu ? 0.0 : Mountain.snow(r, h.y);
    if (snow > 0.05) {
      final cushion = Path()..moveTo(math.max(a, h.x - 4), -1.2);
      for (var x = math.max(a, h.x - 4); x <= math.min(b, x2 + 4); x += 5) {
        final edge = math.min(1.0, math.min(x - h.x + 4, x2 + 4 - x) / 10);
        cushion.lineTo(x, (1.2 + 2.6 * snow + 0.5 * math.sin(x * 0.5 + seed)) * edge);
      }
      for (var x = math.min(b, x2 + 4); x >= math.max(a, h.x - 4); x -= 7) {
        final drip = math.max(0.0, math.sin(x * 0.29 + seed)) * 2.2 * snow;
        cushion.lineTo(x, -1.6 - drip);
      }
      cushion.close();
      c.drawPath(cushion.shift(const Offset(0.6, -0.8)), _p..color = rgba(30, 40, 70, 0.22));
      c.drawPath(cushion, _p..color = _light.snow);
    }
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
    c.drawPath(flag, _p..color = Kit.webbing);
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

  /// While you aim, holds out of reach go a little darker.
  void _farHolds(Canvas c) {
    final d = g.drag!, h = g.holds;
    for (final entry in d.status.entries) {
      if (entry.value != HoldStatus.far) continue;
      final hold = h[entry.key];
      if (hold.t == HoldType.ground) continue;
      if (hold.t.wide) {
        _fill(c, Rect.fromLTWH(hold.x - 3, hold.y - 11, hold.x2! - hold.x + 6, 11), rgba(14, 16, 24, 0.3));
      } else {
        c.drawPath(HoldArt.outline(hold.t, hold.x, hold.y, HoldArt.variantOf(entry.key)), _p..color = rgba(14, 16, 24, 0.42));
      }
    }
  }

  /// How big chalk marks are: their phone size, grown with the view.
  double get _markK => clampD(g.scale / 1.34, 0.8, 1.7);

  /// Chalk on the rock while you aim, in screen space: a dotted circle of
  /// reach, a small mark on every hold you can reach (ring: good, broken
  /// ring: poor, dots: a jump), chalk dots from where the limb was to the
  /// hold under your finger, and there a big mark with its word. The limb
  /// you move has an orange ring, the others a faint dotted one.
  void _chalkAids(Canvas c) {
    final d = g.drag, pose = g.pose;
    if (d == null) return;
    final h = g.holds, j = g.jointAt(d.i), k = _markK;
    final f = g.reducedMotion ? 1.0 : clampD(d.age / 0.18, 0, 1), fade = 1 - (1 - f) * (1 - f);
    final jc = g.w2s(j.x, j.y);
    c.drawPath(dashCircle(jc.dx, jc.dy, g.climber.reach[d.i] * g.scale, 2, 7), _line(Kit.chalk.withValues(alpha: 0.2 * fade), 1.6, cap: StrokeCap.round));
    for (final entry in d.status.entries) {
      final hold = h[entry.key], st = entry.value;
      if (hold.t == HoldType.ground || st == HoldStatus.no || st == HoldStatus.far || entry.key == d.cand) continue;
      if (st == HoldStatus.dyno && holdDist(hold, d.px, d.py) > 90) continue; // jump holds show only near your finger
      final q = switch (st) { HoldStatus.good => Quality.good, HoldStatus.weak => Quality.weak, _ => null };
      final col = chalkTint(q, (st == HoldStatus.dyno ? 0.6 : 0.5) * fade);
      if (hold.t.wide) {
        final a = g.w2s(hold.x, hold.y + 3), b = g.w2s(hold.x2!, hold.y + 3);
        c.drawPath(dashLine(a.dx, a.dy, b.dx, b.dy, st == HoldStatus.dyno ? 2 : 10, st == HoldStatus.dyno ? 6 : 6), _line(col, 3, cap: StrokeCap.round));
      } else {
        final m = switch (st) { HoldStatus.good => Mark.ring, HoldStatus.weak => Mark.brokenRing, _ => Mark.dots };
        ChalkArt.stamp(c, m, g.w2s(hold.x, hold.y), k * (0.5 + 0.06 * fade), col);
      }
    }
    // the other limbs: a faint dotted ring each; the one you move: orange
    if (pose != null) {
      for (var i = 0; i < 4; i++) {
        if (i == d.i) continue;
        final e = i < 2 ? pose.arms[i].e : pose.legs[i - 2].e, p = g.w2s(e.x, e.y);
        c.drawPath(dashCircle(p.dx, p.dy, 17 * k, 2, 6), _line(Kit.chalk.withValues(alpha: 0.6 * 0.6 * fade), 1.6, cap: StrokeCap.round));
      }
      final e = d.i < 2 ? pose.arms[d.i].e : pose.legs[d.i - 2].e, p = g.w2s(e.x, e.y);
      c.drawCircle(p, 21 * k, _line(Kit.webbing.withValues(alpha: 0.95 * fade), 4));
      c.drawCircle(p, 27 * k, _line(Kit.webbing.withValues(alpha: 0.6 * fade), 1.5));
    }
    final pt = d.candPt;
    if (d.candDyno != null && pt != null) {
      // the jump's arc, in chalk dots
      final cx = (j.x + pt.x) / 2, cy = math.max(j.y, pt.y) + 40;
      for (var n = 2; n < 13; n++) {
        final u = n / 14;
        final x = (1 - u) * (1 - u) * j.x + 2 * (1 - u) * u * cx + u * u * pt.x;
        final y = (1 - u) * (1 - u) * j.y + 2 * (1 - u) * u * cy + u * u * pt.y;
        c.drawCircle(g.w2s(x, y), 1.8 * k, _p..color = Kit.chalk.withValues(alpha: 0.7));
      }
    }
    if (d.cand >= 0 && h[d.cand].t != HoldType.ground) {
      final hold = h[d.cand], at = d.candOk ? d.candPt! : attachPoint(hold, d.i, d.px), sp = g.w2s(at.x, at.y);
      // chalk dots from where the limb was, moving slowly along
      final from = g.w2s(d.from.x, d.from.y), len = (sp - from).distance;
      if (len > 30) {
        final dir = (sp - from) / len, phase = g.reducedMotion ? 0.0 : (g.clock * 22) % 10;
        final dots = Path();
        for (var t = 14 + phase; t < len - 26 * k; t += 10) {
          final q = from + dir * t;
          dots.addOval(Rect.fromCircle(center: q, radius: 1.75));
        }
        c.drawPath(dots, _p..color = Kit.chalk.withValues(alpha: 0.75 * fade));
      }
      final Quality? q = d.candOk ? (d.candDyno != null ? null : quality(hold, d.i)) : Quality.no;
      final mark = !d.candOk ? Mark.cross : (d.candDyno != null ? Mark.dots : (q == Quality.good ? Mark.ring : Mark.brokenRing));
      final pulse = g.reducedMotion ? 0.0 : math.sin(g.clock * 7) * 0.025;
      ChalkArt.stamp(c, mark, sp, k * (1 + pulse), chalkTint(q, 0.95));
      // the word goes above the mark, leaning away from the climber
      final word = !d.candOk ? (d.why == 'Too far.' || d.why.isEmpty ? 'too far' : 'no') : (d.candDyno != null ? 'jump!' : chalkWord(hold.t));
      final away = pose == null || at.x >= pose.c.x ? 1.0 : -1.0, ww = _wordWidth(word) * k;
      final wx = away > 0 ? sp.dx + 6 * k : sp.dx - 6 * k - ww;
      ChalkArt.word(c, word, Offset(clampD(wx, 8, g.cw - 8 - ww), sp.dy - 40 * k), k * 0.8, 0.92);
    }
  }

  final Map<String, double> _wordW = {};
  double _wordWidth(String w) => _wordW[w] ??= () {
        final tp = TextPainter(text: TextSpan(text: w, style: FbTxt.hand(36)), textDirection: TextDirection.ltr)..layout();
        final width = tp.width * 0.8;
        tp.dispose();
        return width;
      }();

  void _hang(Canvas c) {
    if (!(g.hangT > 0)) return;
    final at = Offset(g.cd.x, g.cd.y), f = clampD(g.hangT / g.hangMax, 0, 1);
    c.drawCircle(at, 44, _line(rgba(12, 14, 20, 0.4), 3));
    c.drawArc(Rect.fromCircle(center: at, radius: 44), math.pi / 2, -math.pi * 2 * f, false, _line(Kit.low, 2.4));
  }

  // ---------------------------------------------------------------- catching a fall

  /// How deep the fall is in slow motion, 0 to 1 (the veil and glow fade with it).
  double get _slowness {
    final f = g.fall;
    if (f == null) return 0;
    return clampD((1 - f.slow) / (1 - g.mode.slowMo), 0, 1);
  }

  /// While a falling climber can catch a hold, the wall dims.
  void _catchVeil(Canvas c) {
    final w = _slowness;
    if (g.fall == null || w <= 0) return;
    final v = g.viewRange();
    _fill(c, Rect.fromLTRB(v.x0, v.y0, v.x1, v.y1), Pal.ink.withAlpha((72 * w).round()));
  }

  /// ...and the holds in reach get chalk marks: a ring leaves you plenty of
  /// grip, a broken ring little, and a cross is too much for the hand. The
  /// easiest one is the brightest. Wide holds get a chalk line on the lip.
  void _catchMarks(Canvas c) {
    final f = g.fall, w = _slowness;
    if (f == null || w <= 0 || !f.window) return;
    final best = f.best, pulse = g.reducedMotion ? 0.0 : math.sin(g.clock * 10) * 0.05, k = _markK;
    for (final o in f.options) {
      final h = g.holds[o.hold], top = identical(o, best);
      final q = o.left <= 0 ? Quality.no : (o.left < 30 ? Quality.weak : Quality.good);
      final col = chalkTint(q, (top ? 1.0 : 0.62) * w);
      if (h.t.wide) {
        final x0 = math.max(h.x, o.pt.x - Game.catchLip), x1 = math.min(h.x2!, o.pt.x + Game.catchLip);
        final a = g.w2s(x0, h.y + 3), b = g.w2s(x1, h.y + 3);
        final paint = _line(col, top ? 4.5 : 3, cap: StrokeCap.round);
        if (q == Quality.no) {
          c.drawPath(dashLine(a.dx, a.dy, b.dx, b.dy, 6, 6), paint);
        } else if (q == Quality.weak) {
          c.drawPath(dashLine(a.dx, a.dy, b.dx, b.dy, 11, 8), paint);
        } else {
          c.drawLine(a, b, paint);
        }
      } else {
        final mark = switch (q) { Quality.good => Mark.ring, Quality.weak => Mark.brokenRing, Quality.no => Mark.cross };
        ChalkArt.stamp(c, mark, g.w2s(o.pt.x, o.pt.y), k * ((top ? 0.85 : 0.7) + pulse), col);
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
          text: 'Tap a chalk mark!',
          style: FbTxt.typed(15, bold: true, color: Kit.ink, height: 1.1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = g.w2s(best.pt.x, best.pt.y);
    final x = clampD(p.dx - tp.width / 2, 16, g.cw - tp.width - 16), y = clampD(p.dy - 64, 120, g.ch - 220);
    final box = Rect.fromLTWH(x - 10, y - 6, tp.width + 20, tp.height + 12);
    c.drawRect(box.shift(const Offset(0, 3)), _p
      ..shader = null
      ..color = rgba(0, 0, 0, 0.3 * _slowness));
    c.drawRect(box, _p..color = Kit.paper.withValues(alpha: _slowness));
    c.saveLayer(box, Paint()..color = Color.fromRGBO(255, 255, 255, _slowness));
    tp.paint(c, Offset(x, y));
    c.restore();
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
    c.drawPath(dashLine(x0, y, v.x1, y, 12, 9), _line(Kit.blaze.withValues(alpha: 0.6), 1.6));
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
        text: TextSpan(text: text.toUpperCase(), style: FbTxt.typed(11.5, bold: true, color: Kit.blazeWhite, height: 1.1)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    // a blaze-red tag beside the altimeter, the colour of your best on it
    final x = g.cw >= 700 ? 74.0 : 56.0;
    c.drawRect(Rect.fromLTWH(x, p.dy - 22, tp.width + 14, 18), _p..color = Kit.blaze);
    tp.paint(c, Offset(x + 7, p.dy - 13 - tp.height / 2));
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
        PartKind.snow => p.r * 1.6,
        PartKind.pebble => p.r,
        PartKind.spark => 2.4,
      };
      final alpha = (k * 8).ceil().clamp(1, 8);
      final key = (p.kind.index * 64 + (size * 2).round().clamp(1, 63)) * 16 + alpha;
      (batches[key] ??= [])
        ..add(p.x)
        ..add(p.y);
    }
    batches.forEach((key, pts) {
      final alpha = (key % 16) / 8, size = (key ~/ 16 % 64) / 2, kind = PartKind.values[key ~/ 16 ~/ 64];
      _dot
        ..strokeWidth = size
        ..strokeCap = kind == PartKind.pebble || kind == PartKind.spark ? StrokeCap.square : StrokeCap.round
        ..color = switch (kind) {
          PartKind.chalk => rgba(250, 248, 242, 0.55 * alpha),
          PartKind.dust => rgba(150, 140, 128, 0.45 * alpha),
          PartKind.snow => _light.snow.withValues(alpha: 0.9 * alpha),
          PartKind.spark => rgba(255, 200, 110, alpha),
          PartKind.pebble => rgba(120, 116, 110, alpha),
        };
      c.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), _dot);
    });
  }

  /// At night everything past the headlamp's reach goes dark. The lamp
  /// points between the head and the hold you aim at; a warm glow sits in
  /// its middle. Looking out over the route, the night lifts a little.
  void _headlamp(Canvas c, Size size, Pose? pose) {
    final night = _light.night * (1 - 0.65 * g.lookK);
    if (night <= 0.01 || pose == null) return;
    final head = g.w2s(pose.head.x, pose.head.y + 14);
    final d = g.drag;
    var at = head;
    if (d != null) {
      final aim = d.candPt ?? Pt(d.px, d.py);
      at = Offset.lerp(head, g.w2s(aim.x, aim.y), 0.5)!;
    }
    final k = _markK, clear = 80 * k, dark = 250 * k;
    _p
      ..color = Color.fromRGBO(0, 0, 0, night)
      ..shader = ui.Gradient.radial(at, dark, [Kit.darkness.withValues(alpha: 0), Kit.darkness.withValues(alpha: 0), Kit.darkness], [0, clear / dark, 1]);
    c.drawRect(Offset.zero & size, _p);
    _p
      ..shader = ui.Gradient.radial(at, 140 * k, [Kit.lampWarm.withValues(alpha: 0.22), Kit.lampWarm.withValues(alpha: 0)])
      ..blendMode = BlendMode.screen;
    c.drawCircle(at, 140 * k, _p);
    _p
      ..shader = null
      ..blendMode = BlendMode.srcOver;
  }

  /// Frost creeps in from the edges of the screen high up and at night.
  void _frost(Canvas c, Size size, double f) {
    if (f <= 0.01) return;
    final cw = size.width, ch = size.height;
    _p
      ..color = Color.fromRGBO(0, 0, 0, f)
      ..shader = ui.Gradient.radial(Offset(cw / 2, ch * 0.46), math.sqrt(cw * cw + ch * ch) * 0.55,
          [Kit.frost.withValues(alpha: 0), Kit.frost.withValues(alpha: 0), Kit.frost, Kit.frostEdge], [0, 0.6, 0.86, 1]);
    c.drawRect(Offset.zero & size, _p);
    _p.shader = null;
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
