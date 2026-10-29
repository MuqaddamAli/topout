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
        color: color ?? Pal.chalk,
      );
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.38}) =>
      TextStyle(fontFamily: 'Atkinson', fontSize: size, fontWeight: weight, color: color ?? Pal.chalk, height: height);

  /// Courier Prime: numbers, times and typed lines.
  static TextStyle mono(double size, {Color? color, bool bold = true}) => TextStyle(
      fontFamily: 'CourierPrime',
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color ?? Pal.chalk,
      height: 1.1);

  /// Small typed capitals, like "ROUTES".
  static TextStyle eyebrow({double size = 11, double spacing = 0.12, Color? color}) => TextStyle(
        fontFamily: 'CourierPrime',
        fontWeight: FontWeight.w700,
        fontSize: size,
        letterSpacing: size * spacing.clamp(0.08, 0.14),
        color: color ?? Pal.chalkDim,
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
/// show). [compact] is a small dark button with an icon over its label.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.icon,
    this.minHeight = 48,
    this.width,
    this.radius = 14,
    this.on = false,
    this.compact = false,
    this.semanticLabel,
    this.index,
    this.extra,
    this.keyHint,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final double minHeight;
  final double? width;
  final double radius;

  /// Highlighted (like the Look button while looking).
  final bool on;

  /// Icon above a small capital label (the HUD buttons).
  final bool compact;
  final String? semanticLabel;

  /// The number an index line shows (02, 03…).
  final int? index;

  /// Small typed text at the end of a webbing strap.
  final String? extra;

  /// A key that does the same, shown on a desktop.
  final String? keyHint;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      final Widget b = primary
          ? WebbingButton(label: label, onTap: onTap, extra: extra ?? keyHint, height: math.max(minHeight, 64), semanticLabel: semanticLabel)
          : IndexLine(label: label, onTap: onTap, number: index, icon: icon, on: on, semanticLabel: semanticLabel, keyHint: keyHint);
      return width == null ? b : SizedBox(width: width, child: b);
    }
    final filled = primary || on;
    final fg = filled ? Pal.signalInk : Pal.chalk;
    final disabled = onTap == null;
    final Widget content;
    if (compact) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 22, color: fg),
        const SizedBox(height: 3),
        Text(label.toUpperCase(), style: Txt.body(11, weight: FontWeight.w700, color: fg).copyWith(letterSpacing: 0.9)),
      ]);
    } else {
      content = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 22, color: fg), if (label.isNotEmpty) const SizedBox(width: 8)],
        if (label.isNotEmpty) Text(label, style: Txt.body(15, weight: FontWeight.w700, color: fg, height: 1.1)),
      ]);
    }
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: disabled ? 0.38 : 1,
        duration: const Duration(milliseconds: 180),
        child: PressScale(
          enabled: !disabled,
          child: SizedBox(
            width: width,
            child: Material(
              color: filled ? Pal.signal : Pal.ink2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: filled ? BorderSide.none : BorderSide(color: Pal.line, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                splashColor: Pal.chalk.withAlpha(30),
                highlightColor: Pal.chalk.withAlpha(18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: compact || label.isEmpty ? 0 : 18, vertical: compact ? 6 : 0),
                    child: Center(widthFactor: width == null ? 1 : null, heightFactor: 1, child: content),
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

/// A dark rounded panel with a title in capitals.
class GamePanel extends StatelessWidget {
  const GamePanel({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Pal.ink2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Pal.line, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: Txt.display(20, spacing: 0.06)),
        for (final c in children) ...[const SizedBox(height: 12), c],
      ]),
    );
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

/// How hard a route is: one to three tally marks.
class Pips extends StatelessWidget {
  const Pips({super.key, required this.level, this.color});
  final int level;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      TallyMarks(count: level.clamp(0, 3), height: 14, color: color, label: const ['', 'Easy', 'Medium', 'Hard'][level.clamp(0, 3)]);
}

/// The Daily Wall's stamp.
class DailyBadge extends StatelessWidget {
  const DailyBadge({super.key});
  @override
  Widget build(BuildContext context) => const InkStamp(word: 'Daily', size: 0.42, angle: -6);
}

/// The ring that shows how strong a hand still is. [glow] (0 to 1) is a red
/// halo that pulses while the hand is about to slip.
class GaugePainter extends CustomPainter {
  GaugePainter(this.value, {this.glow = 0});
  final double value;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.scale(s);
    const center = Offset(32, 32);
    if (glow > 0) {
      // two soft rings instead of a blur, which would be redrawn every frame on the web
      final halo = Paint()..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 28 + glow * 2, halo..strokeWidth = 9..color = Pal.bad.withAlpha((glow * 40).round()));
      canvas.drawCircle(center, 27.5 + glow, halo..strokeWidth = 5..color = Pal.bad.withAlpha((glow * 60).round()));
    }
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Pal.ink3;
    canvas.drawCircle(center, 26, track);
    final v = value.clamp(0.0, 100.0) / 100;
    if (v <= 0) return;
    final col = value > 60 ? Pal.good : (value > 30 ? Pal.weak : Pal.bad);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 26), -math.pi / 2, math.pi * 2 * v, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = col);
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) => old.value != value || old.glow != glow;
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

/// A small map of a route for the route cards.
class TopoPainter extends CustomPainter {
  TopoPainter(this.route);
  final ClimbRoute route;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 144.0, hh = 256.0;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    canvas.scale(size.width / w, size.height / hh);
    final r = route;
    final p = Paint();
    p.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [hex(0x2b2f55), hex(0xc47b74)])
        .createShader(const Rect.fromLTWH(0, 0, w, 44));
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, 44), p);
    final span = r.endless ? 3 * chunkHeight : r.topY;
    final s = math.min((w - 12) / 300, (hh - 40) / (span + 40));
    double x(double v) => w / 2 + (v - 180) * s;
    double y(double v) => hh - 12 - v * s;
    p.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [hex(0x7b7488), hex(0x3e4350)])
        .createShader(const Rect.fromLTWH(0, 0, w, hh));
    final rock = Path()..moveTo(0, hh);
    for (var px = 0.0; px <= w; px += 6) {
      rock.lineTo(px, r.endless ? 0 : y(r.topY + 60) + math.sin(px * 0.2) * 3);
    }
    rock
      ..lineTo(w, hh)
      ..close();
    canvas.drawPath(rock, p);
    p.shader = null;
    for (final h in r.holds) {
      if (h.t == HoldType.ground || h.y > span + 30) continue;
      if (h.t.wide) {
        p.color = h.t == HoldType.top ? Pal.signal : Pal.chalk;
        canvas.drawRect(Rect.fromLTWH(x(h.x), y(h.y) - 1.5, (h.x2! - h.x) * s, 3), p);
        continue;
      }
      p.color = switch (h.t) {
        HoldType.chip => rgba(242, 237, 228, 0.4),
        HoldType.crimp => Pal.weak,
        HoldType.sloper => hex(0xf0a35a),
        _ => Pal.chalk,
      };
      canvas.drawCircle(Offset(x(h.x), y(h.y)), h.t == HoldType.chip ? 1.5 : 2.4, p);
    }
    canvas.drawRect(const Rect.fromLTWH(0, hh - 12, w, 12), p..color = Pal.earth);
    canvas.restore();
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

/// The coloured rings shown in "How to play".
class RingChip extends StatelessWidget {
  const RingChip({super.key, required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 16, height: 16, child: CustomPaint(painter: _RingPainter(color, dashed))),
        const SizedBox(width: 7),
        Text(label, style: Txt.body(14, color: Pal.chalkDim, height: 1.2)),
      ]);
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.dashed);
  final Color color;
  final bool dashed;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withAlpha(204);
    final r = size.width / 2 - 1;
    final c = Offset(size.width / 2, size.height / 2);
    if (!dashed) {
      canvas.drawCircle(c, r, p);
      return;
    }
    for (var k = 0; k < 8; k++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), k * math.pi / 4, math.pi / 7, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.color != color || old.dashed != dashed;
}
