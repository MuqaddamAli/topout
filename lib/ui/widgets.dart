import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/art.dart';
import '../game/core.dart';
import '../game/field_book.dart';
import '../game/palette.dart';
import 'kit.dart';

/// Text styles (fonts are in assets/fonts). The Field Book's three hands:
/// Archivo for titles (write them in capitals), Courier for anything typed,
/// Atkinson for sentences. See also [FbTxt].
class Txt {
  /// Archivo ExtraCondensed Black. It has one weight; [weight] is kept so
  /// call sites keep working.
  static TextStyle display(double size, {FontWeight weight = FontWeight.w900, Color? color, double spacing = 0.01}) =>
      TextStyle(
        fontFamily: 'ArchivoXC',
        fontWeight: FontWeight.w900,
        fontSize: size,
        height: 0.9,
        letterSpacing: size * spacing,
        color: color ?? Kit.blazeWhite,
      );
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.38}) =>
      TextStyle(fontFamily: 'Atkinson', fontSize: size, fontWeight: weight, color: color ?? Kit.blazeWhite, height: height);

  /// Courier Prime: numbers, times and typed lines.
  static TextStyle mono(double size, {Color? color, bool bold = true}) => TextStyle(
      fontFamily: 'CourierPrime',
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color ?? Kit.blazeWhite,
      height: 1.1);

  /// Small typed capitals, like "ROUTES".
  static TextStyle eyebrow({double size = 11, double spacing = 0.12, Color? color}) => TextStyle(
        fontFamily: 'CourierPrime',
        fontWeight: FontWeight.w700,
        fontSize: size,
        letterSpacing: size * spacing.clamp(0.08, 0.14),
        color: color ?? Kit.blazeWhite.withValues(alpha: 0.7),
        height: 1.2,
      );
}

/// Shrinks a little while a finger or the mouse is down on it, then eases
/// back. It only listens, so buttons inside still get their taps.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true, this.scale = 0.95});
  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: widget.enabled ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !still ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 70 : 180),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Something you can tap that is not a button: it presses in and shows a hand cursor.
class Pressable extends StatelessWidget {
  const Pressable({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PressScale(child: child),
      ),
    );
  }
}

/// Fades and lifts its child in, a little after the ones above it ([index]).
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.index, required this.child, this.step = 55, this.lift = 10});
  final int index;
  final Widget child;
  final int step;
  final double lift;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = index * step, total = 340 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * lift), child: child),
      ),
      child: child,
    );
  }
}

/// Button in the game's style. [primary] is the one thing to do next, a
/// strap of webbing; the others are index lines ([index] is the number they
/// show).
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.icon,
    this.minHeight = 64,
    this.width,
    this.on = false,
    this.semanticLabel,
    this.index,
    this.extra,
    this.keyHint,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;

  /// The height of a webbing strap (at least 64).
  final double minHeight;
  final double? width;

  /// Picked (an index line gets a pencil ring).
  final bool on;
  final String? semanticLabel;

  /// The number an index line shows (02, 03…).
  final int? index;

  /// Small typed text at the end of a webbing strap.
  final String? extra;

  /// A key that does the same, shown on a desktop.
  final String? keyHint;

  @override
  Widget build(BuildContext context) {
    final Widget b = primary
        ? WebbingButton(label: label, onTap: onTap, extra: extra ?? keyHint, height: math.max(minHeight, 64), semanticLabel: semanticLabel)
        : IndexLine(label: label, onTap: onTap, number: index, icon: icon, on: on, semanticLabel: semanticLabel, keyHint: keyHint);
    return width == null ? b : SizedBox(width: width, child: b);
  }
}

/// One choice of a few side by side (Relaxed, Normal, No saves): the picked
/// one has a pencil ring round it.
class GameChoice extends StatelessWidget {
  const GameChoice({super.key, required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Surface.ink(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      label: label,
      button: true,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: PressScale(
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: CustomPaint(
                foregroundPainter: on ? PencilRing(color: ink) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: FbTxt.label(22, color: on ? ink : ink.withValues(alpha: 0.62))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On/off switch with a label (Music, Sounds): a box drawn in pencil, ticked when on.
class GameToggle extends StatelessWidget {
  const GameToggle({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(2, 0, 12, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PencilBox(on: value),
              const SizedBox(width: 10),
              Text(label.toUpperCase(), style: FbTxt.typed(15, bold: true, color: Surface.ink(context), height: 1.1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Hand strength over the last seconds before a fall, as a pencil line on
/// the page: it turns blaze red where the hand was running out. Red shading
/// shows moments with no feet on the wall, yellow with one foot. [progress]
/// (0 to 1) draws the line from the left, so it can be played in.
class TracePainter extends CustomPainter {
  TracePainter(this.trace, this.hand, {this.progress = 1});
  final List<List<double>> trace;
  final int hand;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = trace.length;
    if (n < 2) return;
    double px(int k) => 4 + (w - 8) * (80 - n + k) / 79;
    double py(double v) => h - 6 - (h - 12) * v / 100;
    final band = Paint();
    for (var k = 0; k < n; k++) {
      final fw = trace[k][2];
      if (fw < 2) {
        band.color = fw == 0 ? rgba(196, 42, 28, 0.12) : rgba(217, 164, 65, 0.16);
        canvas.drawRect(Rect.fromLTWH(px(k) - w / 160, 0, w / 79 + 1, h), band);
      }
    }
    // where a hand starts to slip
    canvas.drawPath(dashLine(0, py(30), w, py(30), 4, 4), Paint()
      ..style = PaintingStyle.stroke
      ..color = Kit.blaze.withValues(alpha: 0.45)
      ..strokeWidth = 1);
    // the line, up to where it has been played in: graphite, red when low
    final upTo = (n - 1) * progress.clamp(0.0, 1.0), last = upTo.floor();
    final pencil = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var k = 1; k <= math.min(last + 1, n - 1); k++) {
      final f = k <= last ? 1.0 : upTo - last;
      if (f <= 0) break;
      final a = Offset(px(k - 1), py(trace[k - 1][hand]));
      final b = Offset(px(k - 1) + (px(k) - px(k - 1)) * f, py(trace[k - 1][hand] + (trace[k][hand] - trace[k - 1][hand]) * f));
      pencil.color = trace[k][hand] < 30 ? Kit.blaze : Kit.graphite;
      canvas.drawLine(a, b, pencil);
    }
    if (progress >= 1) canvas.drawCircle(Offset(px(n - 1), py(trace[n - 1][hand])), 4, Paint()..color = Kit.blaze);
  }

  @override
  bool shouldRepaint(covariant TracePainter old) => old.trace != trace || old.hand != hand || old.progress != progress;
}

/// Paints [painter] once into an image (at the screen's pixel ratio) and then
/// only draws that image. On the web every layer is drawn again each frame,
/// so a detailed picture that never changes is much cheaper this way.
/// [cacheKey] must change whenever the picture would.
class CachedPaint extends StatelessWidget {
  const CachedPaint({super.key, required this.cacheKey, required this.painter});
  final String cacheKey;
  final CustomPainter painter;

  static final Map<String, Baked> _images = {};

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, c) {
      final size = c.biggest;
      if (size.isEmpty || !size.isFinite) return const SizedBox.shrink();
      if (_images.length > 48) _images.clear(); // sizes change on resize; keep it small
      final baked = _images.putIfAbsent('$cacheKey|${size.width.round()}x${size.height.round()}@$dpr', () {
        return bake((size.width * dpr).ceil(), (size.height * dpr).ceil(), (canvas) {
          canvas.scale(dpr);
          painter.paint(canvas, size);
        });
      });
      return CustomPaint(size: size, painter: _ImagePainter(baked, dpr));
    });
  }
}

class _ImagePainter extends CustomPainter {
  // repaints when the web swaps in the baked pixels
  _ImagePainter(this.baked, this.dpr) : super(repaint: baked);
  final Baked baked;
  final double dpr;

  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final img = baked.image;
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, img.width / dpr, img.height / dpr), _paint);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) => old.baked != baked;
}

/// The topo of a route, drawn in the field book: the outline of the face
/// with a wash of colour for each band of the mountain, pencil hatching
/// along its edges, the line the route takes, the ledges as numbered belay
/// circles, a flag on the top, and a height scale down the right. The
/// Daily Wall shows its first three sections.
class TopoPainter extends CustomPainter {
  TopoPainter(this.route);
  final ClimbRoute route;

  static final List<Color> _washes = [hex(0xBCCB9A), hex(0xDCC9A0), hex(0xBFD9E8), hex(0xD3DAEA)];

  @override
  void paint(Canvas canvas, Size size) {
    final r = route, w = size.width, h = size.height;
    final span = r.endless ? 3 * chunkHeight : r.topY;
    final left = w * 0.04, right = w * 0.86, top = h * 0.08, bottom = h - 4;
    double x(double v) => left + (v - Wall.left) / (Wall.right - Wall.left) * (right - left);
    double y(double v) => bottom - v / span * (bottom - top);
    final rng = Rng(r.id.length * 17 + 3);
    // the face: ragged sides that lean in toward a summit
    final face = Path()..moveTo(x(-4), bottom);
    final pts = <Offset>[];
    for (var k = 0; k <= 10; k++) {
      final u = k / 10, lean = u * u * 0.18;
      pts.add(Offset(x(-4) + (right - left) * lean + (rng() - 0.5) * w * 0.03, bottom - u * (bottom - top)));
    }
    for (final p in pts) {
      face.lineTo(p.dx, p.dy);
    }
    final peak = Offset((left + right) / 2 + (rng() - 0.5) * w * 0.06, top - h * 0.05);
    face.lineTo(peak.dx, peak.dy);
    final rightPts = <Offset>[];
    for (var k = 10; k >= 0; k--) {
      final u = k / 10, lean = u * u * 0.18;
      rightPts.add(Offset(x(364) - (right - left) * lean + (rng() - 0.5) * w * 0.03, bottom - u * (bottom - top)));
    }
    for (final p in rightPts) {
      face.lineTo(p.dx, p.dy);
    }
    face.close();
    canvas.save();
    canvas.clipPath(face);
    // a wash for each band: valley, cliff band, icefall, summit ridge
    for (var b = 0; b < 4; b++) {
      final y0 = bottom - (b + 1) / 4 * (bottom - top + h * 0.06), y1 = bottom - b / 4 * (bottom - top + h * 0.06);
      canvas.drawRect(Rect.fromLTRB(0, y0, w, y1 + 1), Paint()..color = _washes[b].withValues(alpha: 0.75));
    }
    // snow up high
    canvas.drawRect(Rect.fromLTRB(0, 0, w, top + (bottom - top) * 0.12), Paint()..color = hex(0xF7F4EC).withValues(alpha: 0.85));
    // pencil hatching along the edges
    final hatch = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = Kit.ink.withValues(alpha: 0.4);
    for (var k = 0; k < pts.length - 1; k++) {
      for (var t = 0.0; t < 1; t += 0.34) {
        final a = Offset.lerp(pts[k], pts[k + 1], t)!;
        canvas.drawLine(a + const Offset(3, 0), a + const Offset(11, -7), hatch);
      }
    }
    for (var k = 0; k < rightPts.length - 1; k++) {
      for (var t = 0.0; t < 1; t += 0.34) {
        final a = Offset.lerp(rightPts[k], rightPts[k + 1], t)!;
        canvas.drawLine(a - const Offset(3, 0), a - const Offset(11, 7), hatch);
      }
    }
    canvas.restore();
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = Kit.ink;
    canvas.drawPath(face, ink);
    // the line the route takes: through the middle of the hand holds, band by band
    final line = <Offset>[Offset(x(180), y(60))];
    const step = 70.0;
    for (var b = 60.0 + step; b < span; b += step) {
      var sx = 0.0, n = 0;
      for (final hd in r.holds) {
        if (hd.t.wide || hd.t.hand == Quality.no || hd.y < b - step / 2 || hd.y > b + step / 2) continue;
        sx += hd.x;
        n++;
      }
      if (n > 0) line.add(Offset(x(sx / n), y(b)));
    }
    if (!r.endless) line.add(Offset(x(180), y(span)));
    final path = Path()..moveTo(line.first.dx, line.first.dy);
    for (var k = 1; k < line.length; k++) {
      final m = Offset.lerp(line[k - 1], line[k], 0.5)!;
      path.quadraticBezierTo(line[k - 1].dx, line[k - 1].dy, m.dx, m.dy);
    }
    path.lineTo(line.last.dx, line.last.dy);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = Kit.card);
    final dots = Path();
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        dots.addPath(m.extractPath(d, d + 3.5), Offset.zero);
      }
    }
    canvas.drawPath(
        dots,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Kit.blaze);
    // ledges: numbered belay circles
    var n = 0;
    final ledges = [for (final hd in r.holds) if (hd.t == HoldType.ledge && hd.y <= span) hd]..sort((a, b) => a.y.compareTo(b.y));
    for (final hd in ledges) {
      final c = Offset(x((hd.x + hd.x2!) / 2), y(hd.y));
      canvas.drawCircle(c, 8.5, Paint()..color = Kit.card);
      canvas.drawCircle(
          c,
          8.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Kit.blaze);
      final tp = TextPainter(
        text: TextSpan(text: '${++n}', style: FbTxt.typed(10, bold: true, color: Kit.ink, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
    // a flag on the top
    if (!r.endless) {
      final f = Offset(peak.dx, peak.dy + 2);
      canvas.drawLine(f, f - const Offset(0, 18), ink..strokeWidth = 1.6);
      canvas.drawPath(
          Path()
            ..moveTo(f.dx, f.dy - 18)
            ..lineTo(f.dx + 13, f.dy - 14)
            ..lineTo(f.dx, f.dy - 10)
            ..close(),
          Paint()..color = Kit.blaze);
    }
    // the height scale
    final tick = Paint()
      ..strokeWidth = 1.2
      ..color = Kit.ink;
    final every = span / unitsPerMetre > 12 ? 5 : 2;
    for (var m = 0; m * unitsPerMetre <= span; m += every) {
      final yy = y(m * unitsPerMetre.toDouble());
      canvas.drawLine(Offset(w - 12, yy), Offset(w, yy), tick);
      final tp = TextPainter(
        text: TextSpan(text: '$m', style: FbTxt.typed(10.5, bold: true, color: Kit.ink, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - 15 - tp.width, yy - tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant TopoPainter old) => old.route != route;
}

/// The little lantern icon in "How to play".
class LampIcon extends StatelessWidget {
  const LampIcon({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(width: 28, height: 28, child: CustomPaint(painter: _LampPainter()));
}

class _LampPainter extends CustomPainter {
  const _LampPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28);
    canvas.drawCircle(const Offset(14, 15), 11, Paint()..color = Pal.lamp.withAlpha(46));
    final glass = RRect.fromRectAndRadius(const Rect.fromLTWH(10, 10, 8, 10), const Radius.circular(1.5));
    canvas.drawRRect(glass, Paint()..color = Pal.lamp);
    final ink = Paint()
      ..color = hex(0x3a3d46)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(glass, ink);
    canvas.drawPath(
        Path()
          ..moveTo(9, 21)
          ..lineTo(19, 21)
          ..moveTo(10.5, 10)
          ..lineTo(11.5, 7.5)
          ..lineTo(16.5, 7.5)
          ..lineTo(17.5, 10),
        ink);
    canvas.drawArc(const Rect.fromLTWH(12, 5.5, 4, 4), math.pi, math.pi, false, ink..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _LampPainter old) => false;
}
