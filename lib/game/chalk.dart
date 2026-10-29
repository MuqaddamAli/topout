// Chalk on the rock: the marks that show where a hand or foot can go. A full
// ring is a good hold, a broken ring a poor one, a cross no hold at all, and
// a ring of dots a hold you can only jump to. The shape carries the meaning,
// so it reads without colour. Each mark is drawn once with a grainy edge and
// then stamped; the words next to them ("jug!", "crimp") are Reenie Beanie.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'art.dart';
import 'core.dart';
import 'field_book.dart';
import 'palette.dart';

enum Mark { ring, brokenRing, cross, dots }

class ChalkArt {
  ChalkArt._();

  /// Marks are drawn this many times bigger than shown, so they stay sharp.
  static const double res = 3;

  /// The size of each mark at phone scale, in logical pixels.
  static const Size box = Size(64, 56);

  static final Map<Mark, Baked> _marks = {};
  static Baked _of(Mark m) => _marks[m] ??= bake((box.width * res).ceil(), (box.height * res).ceil(), (c) {
        c.scale(res);
        _draw(c, m);
      });

  static void _draw(ui.Canvas c, Mark m) {
    final r = Rng(5 + m.index * 11);
    final p = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..color = const ui.Color(0xFFFFFFFF);
    const cx = 32.0, cy = 28.0;
    // a hand-drawn ring: wobbles a little and does not quite close on itself
    ui.Path ring(double rx, double ry, double start, double sweep) {
      final path = ui.Path();
      const n = 48;
      final wob = [for (var k = 0; k < 3; k++) (a: (r() - 0.5) * 1.4, f: r() * 6.3)];
      for (var i = 0; i <= n; i++) {
        final t = start + sweep * i / n;
        var d = 0.0;
        for (var k = 0; k < wob.length; k++) {
          d += wob[k].a * math.sin(t * (k + 2) + wob[k].f);
        }
        final x = cx + math.cos(t) * (rx + d), y = cy + math.sin(t) * (ry + d);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      return path;
    }

    switch (m) {
      case Mark.ring:
        c.drawPath(ring(24, 20, -2.2, math.pi * 2.12), p..strokeWidth = 4);
      case Mark.brokenRing:
        // dashes 11 on 8 along the ring
        const per = 19.0, n = 7;
        for (var k = 0; k < n; k++) {
          final a0 = k * math.pi * 2 / n - 1.9;
          c.drawPath(ring(24, 20, a0, math.pi * 2 / n * 11 / per), p..strokeWidth = 4);
        }
      case Mark.cross:
        p.strokeWidth = 4.2;
        c.drawLine(const ui.Offset(cx - 15, cy - 14), ui.Offset(cx + 15 + r(), cy + 14), p);
        c.drawLine(ui.Offset(cx + 15, cy - 14 - r()), const ui.Offset(cx - 15, cy + 14), p);
      case Mark.dots:
        p.style = ui.PaintingStyle.fill;
        for (var k = 0; k < 16; k++) {
          final t = k / 16 * math.pi * 2;
          c.drawCircle(ui.Offset(cx + math.cos(t) * 24, cy + math.sin(t) * 20), 2.2, p);
        }
    }
    // grain: chalk does not cover evenly
    final hole = ui.Paint()..blendMode = ui.BlendMode.dstOut;
    for (var i = 0; i < 420; i++) {
      hole.color = rgba(0, 0, 0, 0.25 + r() * 0.6);
      c.drawCircle(ui.Offset(r() * box.width, r() * box.height), 0.35 + r() * 0.5, hole);
    }
  }

  static final ui.Paint _paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  /// Stamps mark [m] centred on [at], [k] times its phone size, in [color].
  static void stamp(ui.Canvas c, Mark m, ui.Offset at, double k, ui.Color color) {
    final img = _of(m).image, w = box.width * k, h = box.height * k;
    _paint.colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.modulate);
    c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromCenter(center: at, width: w, height: h), _paint);
  }

  static final Map<String, TextPainter> _words = {};

  /// A chalk word, written at [at] (its left middle), turned a little.
  static void word(ui.Canvas c, String text, ui.Offset at, double k, double alpha) {
    final tp = _words[text] ??= TextPainter(
      text: TextSpan(text: text, style: FbTxt.hand(36, color: Kit.chalk)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(-7 * math.pi / 180);
    c.scale(k);
    c.saveLayer(ui.Rect.fromLTWH(-4, -tp.height / 2 - 4, tp.width + 8, tp.height + 8), ui.Paint()..color = rgba(255, 255, 255, alpha));
    tp.paint(c, ui.Offset(0, -tp.height / 2));
    c.restore();
    c.restore();
  }
}

/// Chalk, with a light tint of good (green), weak (yellow) or bad (red) on top.
ui.Color chalkTint(Quality? q, [double a = 1]) {
  final tint = switch (q) { Quality.good => Pal.good, Quality.weak => Pal.weak, Quality.no => Pal.bad, null => Kit.chalk };
  return ui.Color.lerp(Kit.chalk, tint, 0.3)!.withValues(alpha: a);
}
