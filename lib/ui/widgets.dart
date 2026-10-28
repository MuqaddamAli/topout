import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/art.dart';
import '../game/core.dart';
import '../game/palette.dart';

/// Text styles (fonts are in assets/fonts).
class Txt {
  static TextStyle display(double size, {FontWeight weight = FontWeight.w800, Color? color, double spacing = 0.02}) =>
      TextStyle(
        fontFamily: 'BigShoulders',
        fontWeight: weight,
        fontSize: size,
        height: 0.95,
        letterSpacing: size * spacing,
        color: color ?? Pal.chalk,
      );
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.38}) =>
      TextStyle(fontFamily: 'Atkinson', fontSize: size, fontWeight: weight, color: color ?? Pal.chalk, height: height);
  static TextStyle mono(double size, {Color? color}) =>
      TextStyle(fontFamily: 'PlexMono', fontSize: size, fontWeight: FontWeight.w500, color: color ?? Pal.chalk, height: 1.1);

  /// Small capitals label, like "ROUTES".
  static TextStyle eyebrow({double size = 11, double spacing = 0.16, Color? color}) => TextStyle(
        fontFamily: 'Atkinson',
        fontSize: size,
        letterSpacing: size * spacing,
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

/// Button in the game's style. [primary] is the orange one.
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

  @override
  Widget build(BuildContext context) {
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

/// On/off switch with a label (Music, Sounds).
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
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: BorderSide(color: Pal.line, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 20,
                decoration: BoxDecoration(color: value ? Pal.signal : Pal.ink3, borderRadius: BorderRadius.circular(10)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: value ? Pal.signalInk : Pal.chalkDim, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: Txt.body(14, weight: FontWeight.w700, height: 1.1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three bars that show how hard a route is.
class Pips extends StatelessWidget {
  const Pips({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: const ['', 'Easy', 'Medium', 'Hard'][level.clamp(0, 3)],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 1; k <= 3; k++)
            Container(
              width: 5,
              height: 3.0 + k * 3,
              margin: EdgeInsets.only(left: k == 1 ? 0 : 3),
              decoration: BoxDecoration(color: k <= level ? Pal.signal : Pal.line, borderRadius: BorderRadius.circular(1.5)),
            ),
        ],
      ),
    );
  }
}

class DailyBadge extends StatelessWidget {
  const DailyBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Pal.jump, borderRadius: BorderRadius.circular(6)),
        child: Text('DAILY',
            style: Txt.body(11, weight: FontWeight.w700, color: hex(0x0b1a26), height: 1).copyWith(letterSpacing: 0.9)),
      );
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

/// Hand strength over the last seconds before a fall. Red shading shows
/// moments with no feet on the wall, yellow with one foot. [progress] (0 to 1)
/// draws the line from the left, so it can be played in.
class TracePainter extends CustomPainter {
  TracePainter(this.trace, this.hand, {this.progress = 1});
  final List<List<double>> trace;
  final int hand;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)), Paint()..color = Pal.ink);
    final n = trace.length;
    if (n < 2) return;
    double px(int k) => 8 + (w - 16) * (80 - n + k) / 79;
    double py(double v) => h - 8 - (h - 16) * v / 100;
    final band = Paint();
    for (var k = 0; k < n; k++) {
      final fw = trace[k][2];
      if (fw < 2) {
        band.color = fw == 0 ? rgba(255, 90, 90, 0.22) : rgba(244, 198, 77, 0.14);
        canvas.drawRect(Rect.fromLTWH(px(k) - w / 160, 0, w / 79 + 1, h), band);
      }
    }
    canvas.drawLine(Offset(0, py(30)), Offset(w, py(30)),
        Paint()
          ..color = rgba(242, 237, 228, 0.18)
          ..strokeWidth = 1);
    // the line, up to where it has been played in
    final upTo = (n - 1) * progress.clamp(0.0, 1.0), last = upTo.floor();
    final line = Path()..moveTo(px(0), py(trace[0][hand]));
    for (var k = 1; k <= last; k++) {
      line.lineTo(px(k), py(trace[k][hand]));
    }
    if (last < n - 1) {
      final f = upTo - last;
      line.lineTo(px(last) + (px(last + 1) - px(last)) * f, py(trace[last][hand] + (trace[last + 1][hand] - trace[last][hand]) * f));
    }
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..color = Pal.chalk);
    if (progress >= 1) canvas.drawCircle(Offset(px(n - 1), py(trace[n - 1][hand])), 4, Paint()..color = Pal.bad);
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
