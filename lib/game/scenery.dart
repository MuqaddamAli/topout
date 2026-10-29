// The world behind the wall, in screen space: the sky in the mountain's
// colours for the hour, the sun going down (and the moon and stars after
// it), clouds tinted by the light, three mountain ranges with snow on their
// peaks, and a band of mist between them. It shows above the summit.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'art.dart';
import 'field_book.dart';
import 'mountain.dart';
import 'palette.dart';

/// The light of an hour: what the sun or moon gives the wall and the clouds.
class Light {
  Light(this.hour, this.env)
      : dusk = (hour - 1).clamp(0.0, 1.0),
        night = Mountain.night(hour);
  final double hour;
  final Env env;

  /// 0 by day, 1 at dusk (the sun is down at dusk's end).
  final double dusk;

  /// How dark it is (0 to 1).
  final double night;

  static ui.Color _mix(ui.Color a, ui.Color b, double t) => ui.Color.lerp(a, b, t)!;

  /// The colour of direct light on the rock.
  ui.Color get sun => _mix(_mix(hex(0xFFF1DC), hex(0xFFA066), dusk), hex(0x8CA6D8), night);

  /// How strong the direct light on the rock is.
  double get sunK => (0.18 + 0.14 * dusk) * (1 - night) + 0.07 * night;

  /// How clouds are coloured: their grey turned into a ramp from a shade
  /// colour to a lit one (by day white with blue shadows, at dusk lit warm
  /// from below, at night faint and blue).
  ui.ColorFilter get cloud {
    final white = hex(0xFFFFFF);
    final shade = _mix(_mix(_mix(env.skyTop, white, 0.55), _mix(env.skyTop, env.skyLow, 0.3), dusk), _mix(env.skyTop, white, 0.08), night);
    final lit = _mix(_mix(white, _mix(env.skyLow, white, 0.5), dusk), _mix(env.skyTop, white, 0.28), night);
    // grey 0.78 (the darkest part of a cloud) to 1 becomes shade to lit
    List<double> row(double s, double l, int ch) {
      final a = (l - s) / 0.22, b = (s - a * 0.78) * 255;
      return [for (var k = 0; k < 3; k++) k == ch ? a : 0.0, 0, b];
    }

    return ui.ColorFilter.matrix([
      ...row(shade.r, lit.r, 0),
      ...row(shade.g, lit.g, 1),
      ...row(shade.b, lit.b, 2),
      0, 0, 0, 1, 0,
    ]);
  }

  /// What snow is tinted with: white by day, rosy at dusk, blue at night.
  ui.Color get snow => _mix(_mix(hex(0xFFFFFF), _mix(env.skyLow, hex(0xFFFFFF), 0.65), dusk), hex(0x9DB0D4), night * 0.8);

  /// How much the climber's shadow shows.
  double get shadow => 0.24 + 0.06 * dusk - 0.14 * night;
}

/// Paints the sky, the mountains and the mist. [crest] is the summit's
/// height on screen, [d] how far the view is above (+) or below the top in
/// world units, [sc] the world scale and [camX] the view's middle.
class Backdrop {
  final ui.Paint _p = ui.Paint();
  final ui.Paint _img = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  void paint(ui.Canvas c, ui.Size size, Light light, {required double crest, required double d, required double sc, required double camX,
      required double clock, required bool still, required void Function(ui.Canvas c, double crest) birds, void Function(ui.Canvas c)? behindRanges}) {
    final cw = size.width, ch = size.height, env = light.env;
    if (crest <= -40) return;
    final lim = math.min(ch, crest + 100 * sc);
    final skyRect = ui.Rect.fromLTWH(0, 0, cw, lim);
    _p
      ..shader = ui.Gradient.linear(ui.Offset(0, crest - ch * 1.05), ui.Offset(0, crest + 20 * sc),
          [env.skyTop, ui.Color.lerp(env.skyTop, env.skyLow, 0.45)!, env.skyLow], [0, 0.55, 1])
      ..color = const ui.Color(0xFF000000);
    c.drawRect(skyRect, _p);
    _p.shader = null;
    final art = Art.instance;
    // stars, only once the sun is low
    final starK = math.max(light.night, light.dusk * 0.18);
    if (starK > 0.02) {
      for (final st in art.stars) {
        final y = crest - 160 - st.y * ch * 0.9;
        if (y < 0 || y > crest - 120) continue;
        final tw = still ? 0.75 : 0.5 + 0.5 * math.sin(clock * 1.5 + st.p);
        final al = (0.3 + 0.55 * tw) * starK * math.min(1.0, (crest - 120 - y) / 220);
        c.drawRect(ui.Rect.fromLTWH(st.x * cw, y, st.s, st.s), _p..color = rgba(255, 250, 240, al));
      }
    }
    // the sun goes down behind the ranges; the moon comes up on the other side
    final sunK = 1 - light.night;
    if (sunK > 0.01) {
      final orb = ui.Color.lerp(skyLights(DayTime.day).orb, skyLights(DayTime.dusk).orb, light.dusk)!;
      final sunX = cw * 0.22, sunY = ch / 2 + (0.2 * d - (250 - 190 * light.dusk)) * sc;
      _p.shader = ui.Gradient.radial(ui.Offset(sunX, sunY), math.max(cw, ch) * 0.65,
          [orb.withValues(alpha: (0.26 + 0.16 * light.dusk) * sunK), orb.withValues(alpha: 0.08 * sunK), orb.withValues(alpha: 0)], [0, 0.22, 0.8]);
      c.drawRect(skyRect, _p);
      _p.shader = null;
      c.drawCircle(ui.Offset(sunX, sunY), 27 * sc, _p..color = orb.withValues(alpha: 0.22 * sunK));
      c.drawCircle(ui.Offset(sunX, sunY), 15 * sc, _p..color = ui.Color.lerp(orb, hex(0xFFFFFF), 0.35)!.withValues(alpha: sunK));
    }
    if (light.night > 0.01) {
      final moon = skyLights(DayTime.night).orb, mx = cw * 0.76, my = ch / 2 + (0.15 * d - 300) * sc, k = light.night;
      _p.shader = ui.Gradient.radial(ui.Offset(mx, my), 90 * sc, [moon.withValues(alpha: 0.22 * k), moon.withValues(alpha: 0)]);
      c.drawCircle(ui.Offset(mx, my), 90 * sc, _p);
      _p.shader = null;
      c.drawCircle(ui.Offset(mx, my), 12 * sc, _p..color = moon.withValues(alpha: k));
      // a crescent: the sky covers part of the disc
      c.drawCircle(ui.Offset(mx + 5 * sc, my - 3 * sc), 10.5 * sc, _p..color = env.skyTop.withValues(alpha: 0.85 * k));
    }
    // clouds, far to near, tinted by the light
    _img.colorFilter = light.cloud;
    for (final cl in Art.cloudPlaces) {
      final spr = art.clouds[cl.s], w = spr.w * sc * cl.k, hgt = spr.h * sc * cl.k;
      final y = ch / 2 + (cl.p * d - cl.h) * sc;
      if (y - hgt > crest + 10 || y < -10) continue;
      final span = cw + w + 40, x = ((cl.x * span + (still ? 0 : clock) * cl.v * sc) % span) - w - 20;
      _img.color = rgba(255, 255, 255, cl.a * (1 - 0.35 * light.night));
      c.drawImageRect(spr.image, ui.Rect.fromLTWH(0, 0, spr.image.width.toDouble(), spr.image.height.toDouble()),
          ui.Rect.fromLTWH(x, y - hgt, w, hgt), _img);
    }
    _img.colorFilter = null;
    if (light.night < 0.7) birds(c, crest);
    behindRanges?.call(c);
    _ranges(c, cw, ch, light, crest: crest, d: d, sc: sc, camX: camX, clock: clock, still: still);
  }

  void _ranges(ui.Canvas c, double cw, double ch, Light light,
      {required double crest, required double d, required double sc, required double camX, required double clock, required bool still}) {
    final env = light.env;
    final ranges = [
      (p: 0.35, col: env.far, amp: 90.0, fr: 0.011, seed: 1.7, snow: 0.7),
      (p: 0.55, col: ui.Color.lerp(env.far, env.near, 0.35)!, amp: 108.0, fr: 0.017, seed: 4.1, snow: 0.66),
      (p: 0.75, col: env.near, amp: 72.0, fr: 0.026, seed: 7.3, snow: 0.0),
    ];
    // Each range is one fill (its haze is part of the gradient) and stops
    // just under the summit edge, which dips at most ~111 below the top; the
    // wall covers the rest.
    final bottom = math.min(ch, crest + 130 * sc);
    final snowCol = ui.Color.lerp(light.snow, env.skyLow, 0.2)!;
    for (var k = 0; k < ranges.length; k++) {
      final rg = ranges[k];
      final base = ch / 2 + (rg.p * d - (1 - rg.p) * 120) * sc;
      if (base - rg.amp * sc > crest + 100 * sc) continue;
      final xs = <double>[], ys = <double>[];
      for (var x = 0.0; x <= cw + 10; x += 8) {
        final wx = x / sc + camX * rg.p;
        final n = 0.55 + 0.25 * math.sin(wx * rg.fr + rg.seed) + 0.15 * math.sin(wx * rg.fr * 2.7 + rg.seed * 2) + 0.05 * math.sin(wx * rg.fr * 7 + rg.seed);
        xs.add(x);
        ys.add(base - rg.amp * sc * n);
      }
      _p
        ..color = const ui.Color(0xFF000000)
        ..shader = ui.Gradient.linear(ui.Offset(0, base - rg.amp * sc), ui.Offset(0, base + 40 * sc),
            [ui.Color.lerp(rg.col, env.skyLow, 0.28)!, rg.col, ui.Color.lerp(rg.col, env.skyTop, 0.15)!], [0, 0.55, 1]);
      _drawBand(c, xs, ys, 0, xs.length, floor: bottom);
      _p.shader = null;
      if (rg.snow > 0) _snowCaps(c, xs, ys, base - rg.amp * sc * rg.snow, sc, snowCol, rg.seed);
      // mist between the far ranges and the near one
      if (k == 1) _mist(c, cw, base - rg.amp * sc * 0.15, sc, env.skyLow, clock, still);
    }
  }

  /// Snow on the peaks of a range: everything above [line] on screen, with a
  /// ragged lower edge.
  void _snowCaps(ui.Canvas c, List<double> xs, List<double> ys, double line, double sc, ui.Color col, double seed) {
    // a gradient of one colour: drawn with the mesh's colours, a plain paint
    // colour is not used by every renderer, a shader is
    _p
      ..color = const ui.Color(0xFF000000)
      ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(0, 1), [col, col]);
    var run = <int>[];
    void flush() {
      if (run.length >= 2) {
        // the lower edge is ragged, and never above the ridge, so each cap
        // tapers to nothing at its ends
        final low = <double>[];
        for (final i in run) {
          final jag = (math.sin(xs[i] * 0.21 + seed) * 4 + math.sin(xs[i] * 0.067 + seed * 3) * 7) * sc;
          low.add(math.max(ys[i], math.min(line + jag.abs() * 0.6, ys[i] + 26 * sc + jag)));
        }
        _drawBand(c, xs, ys, run.first, run.first + run.length, low: low, alpha: 0.85);
      }
      run = [];
    }

    for (var i = 0; i < xs.length; i++) {
      if (ys[i] < line) {
        run.add(i);
      } else {
        if (run.isNotEmpty) run.add(i);
        flush();
      }
    }
    flush();
    _p.shader = null;
  }

  /// Fills a band across the sky with the gradient of [_p] at [alpha]: from
  /// the edge [top] (screen y at each of [xs], from [from] to [to]) down to
  /// the edge [low] (one y for each of those), or down to the level [floor].
  /// It is drawn as triangles with a clear fringe a pixel wide outside the
  /// top edge and [low], which smooths them. A concave anti-aliased path
  /// this big would be slow to fill, and on the web it would be filled again
  /// from scratch every frame.
  void _drawBand(ui.Canvas c, List<double> xs, List<double> top, int from, int to, {List<double>? low, double floor = 0, double alpha = 1}) {
    // the paint's own alpha is lost when it is blended with the mesh's colours,
    // so [alpha] goes in the mesh
    const aa = 1.0, clear = 0x00FFFFFF;
    final solid = (alpha * 255).round() << 24 | 0xFFFFFF;
    final n = to - from, rows = low == null ? 3 : 4;
    final pos = Float32List(n * rows * 2), colors = Int32List(n * rows), idx = Uint16List((n - 1) * (rows - 1) * 6);
    for (var i = 0; i < n; i++) {
      final x = xs[from + i], t = top[from + i], b = low != null ? low[i] : floor, v = i * rows;
      final edge = [t - aa, t, b, b + aa];
      for (var r = 0; r < rows; r++) {
        pos[(v + r) * 2] = x;
        pos[(v + r) * 2 + 1] = edge[r];
        colors[v + r] = r == 0 || r == 3 ? clear : solid;
      }
    }
    var k = 0;
    for (var i = 0; i < n - 1; i++) {
      for (var r = 0; r < rows - 1; r++) {
        final a = i * rows + r, b = a + rows;
        idx
          ..[k++] = a
          ..[k++] = b
          ..[k++] = a + 1
          ..[k++] = a + 1
          ..[k++] = b
          ..[k++] = b + 1;
      }
    }
    final mesh = ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: colors, indices: idx);
    // the paint's gradient, times the clear or solid of the mesh
    c.drawVertices(mesh, ui.BlendMode.modulate, _p);
    mesh.dispose();
  }

  void _mist(ui.Canvas c, double cw, double y, double sc, ui.Color col, double clock, bool still) {
    final img = Art.instance.mist.image, w = 512 * sc * 0.9, h = 96 * sc * 0.9;
    final drift = still ? 0.0 : math.sin(clock * math.pi * 2 / 20) * 25 * sc;
    _img
      ..colorFilter = ui.ColorFilter.mode(col, ui.BlendMode.modulate)
      ..color = rgba(255, 255, 255, 0.75);
    for (var x = -w + (drift % w); x < cw; x += w) {
      c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), ui.Rect.fromLTWH(x, y - h / 2, w, h), _img);
    }
    _img.colorFilter = null;
  }
}
