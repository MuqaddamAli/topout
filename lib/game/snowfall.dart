// Falling snow, in screen space: a fixed set of flakes at three depths that
// wrap around the screen, so the snow never thins out when the view jumps.
// Near flakes are big, bright and quick, far ones small and slow; all of
// them move with the view a little (by how near they are), sway, and are
// pushed sideways by gusts that come and go. How many fall depends on how
// much snow there is where you are. Drawn with one drawRawAtlas call.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'art.dart';
import 'core.dart';

class _Flake {
  _Flake(this.x, this.y, this.z, this.ph, this.f);
  double x, y; // screen pixels
  final double z, ph, f; // nearness 0.25 to 1, sway phase and speed
}

class Snowfall {
  Snowfall() {
    final r = Rng(61);
    for (var i = 0; i < count; i++) {
      // a few near flakes, more far ones; sorted far to near
      final z = 0.25 + 0.75 * math.pow(r(), 1.6).toDouble();
      _flakes.add(_Flake(r() * 2000, r() * 2000, z, r() * math.pi * 2, 0.6 + r() * 1.4));
    }
    _flakes.sort((a, b) => a.z.compareTo(b.z));
    // shuffle by depth band so drawing the first n gives every depth
    final out = <_Flake>[];
    for (var k = 0; k < count; k++) {
      out.add(_flakes[(k * 37) % count]);
    }
    _flakes
      ..clear()
      ..addAll(out);
  }

  static const int count = 220;
  final List<_Flake> _flakes = [];
  double? _camX, _camY;
  double _t = 0;

  final Float32List _xf = Float32List(count * 4), _rects = Float32List(count * 4);
  final Int32List _colors = Int32List(count);
  final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  /// How hard the wind blows right now, 0 to 1: calm most of the time, with
  /// a gust every few seconds.
  double get gust {
    final a = math.max(0.0, math.sin(_t * 0.41) * math.sin(_t * 0.17 + 1.3));
    return a * a;
  }

  /// Steps the flakes by [dt] seconds. [camX], [camY] and [scale] are the
  /// view (world units); [w], [h] the screen size.
  void update(double dt, {required double camX, required double camY, required double scale, required double w, required double h}) {
    _t += dt;
    final dx = _camX == null ? 0.0 : (camX - _camX!) * scale, dy = _camY == null ? 0.0 : (camY - _camY!) * scale;
    _camX = camX;
    _camY = camY;
    final k = scale / 1.6, wind = 14 + 150 * gust, spanW = w + 60, spanH = h + 60;
    for (final f in _flakes) {
      final sway = math.sin(_t * f.f + f.ph) * 14;
      f.x += ((wind + sway) * f.z * k) * dt - dx * f.z;
      f.y += (24 + 52 * f.z) * k * dt + dy * f.z;
      f.x = (f.x + 30) % spanW - 30;
      f.y = (f.y + 30) % spanH - 30;
    }
  }

  /// Draws as many flakes as [amount] (0 to 1) asks for, tinted [tint].
  void paint(ui.Canvas c, double amount, ui.Color tint, double scale) {
    final n = (count * amount.clamp(0.0, 1.0)).round();
    if (n <= 0) return;
    final img = Art.instance.flake.image, k = scale / 1.6;
    final r = tint.r * 255, g = tint.g * 255, b = tint.b * 255;
    for (var i = 0; i < n; i++) {
      final f = _flakes[i], size = (1.5 + 4.6 * f.z * f.z) * k, s = size / 32;
      _xf
        ..[i * 4] = s
        ..[i * 4 + 1] = 0
        ..[i * 4 + 2] = f.x - size / 2
        ..[i * 4 + 3] = f.y - size / 2;
      _rects
        ..[i * 4] = 0
        ..[i * 4 + 1] = 0
        ..[i * 4 + 2] = 32
        ..[i * 4 + 3] = 32;
      final a = ((0.3 + 0.6 * f.z) * 255).round();
      _colors[i] = (a << 24) | (r.round() << 16) | (g.round() << 8) | b.round();
    }
    c.drawRawAtlas(img, Float32List.sublistView(_xf, 0, n * 4), Float32List.sublistView(_rects, 0, n * 4),
        Int32List.sublistView(_colors, 0, n), ui.BlendMode.modulate, null, _paint);
  }
}
