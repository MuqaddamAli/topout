// The Field Book parts (design/field-book/HANDOFF.md): every piece of UI is
// something a climber would carry. Paper scraps with a grid, tape and a torn
// edge; luggage tags on a string; webbing straps for the one thing to do
// next; typed index lines for the rest; ink stamps for what is final; tally
// marks for counts; ruled log pages; pencil marks round what is picked.
//
// No blurs: shadows are flat, offset copies. Things that sway or blink stop
// when the phone asks for less motion.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/core.dart' show Rng;
import '../game/field_book.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// Whether what is drawn here sits on paper (ink) or on the rock (paper
/// white). Index lines, typed text and pencil marks take their colour from it.
class Surface extends InheritedWidget {
  const Surface({super.key, required this.paper, required super.child});
  final bool paper;

  static bool isPaper(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Surface>()?.paper ?? false;

  /// The colour to write in here.
  static Color ink(BuildContext context) => isPaper(context) ? Kit.ink : Kit.blazeWhite;

  @override
  bool updateShouldNotify(Surface old) => old.paper != paper;
}

// ---------------------------------------------------------------- paper

enum Rule { grid, ruled, plain }

/// A sheet of paper: its colour, a grid or ruled lines, a red margin, a torn
/// bottom edge and a flat shadow under it.
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.color,
    this.rule = Rule.grid,
    this.cell = 11,
    this.margin,
    this.torn = false,
    this.tornTop = 0,
    this.shadow = 6,
    this.seed = 1,
    this.lineColor,
  });
  final Color color;
  final Rule rule;
  final double cell;

  /// Where the red margin line is, from the left.
  final double? margin;
  final bool torn;

  /// A tear across the page from the bottom left up to this far up at the
  /// right (a torn-out page), 0 for none.
  final double tornTop;
  final double shadow;
  final int seed;
  final Color? lineColor;

  Path shape(Size size) {
    final w = size.width, h = size.height;
    final p = Path()..moveTo(0, 0)..lineTo(w, 0);
    if (!torn && tornTop <= 0) {
      p
        ..lineTo(w, h)
        ..lineTo(0, h);
      return p..close();
    }
    final r = Rng(seed);
    final depth = math.max(3.0, h * 0.04);
    if (tornTop > 0) {
      // torn diagonally: from the right edge high up down to the bottom left
      p.lineTo(w, h - tornTop);
      for (var x = w; x > 0; x -= 6 + r() * 5) {
        final y = h - tornTop * (x / w) - r() * depth;
        p.lineTo(x, y);
      }
      p.lineTo(0, h);
    } else {
      p.lineTo(w, h - depth * 0.5);
      for (var x = w; x > 0; x -= 5 + r() * 6) {
        p.lineTo(x, h - (r() < 0.5 ? 0 : depth) - r() * depth * 0.4);
      }
      p.lineTo(0, h - depth * 0.3);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = shape(size);
    if (shadow > 0) canvas.drawPath(s.shift(Offset(0, shadow)), Paint()..color = rgba(0, 0, 0, 0.3));
    canvas.drawPath(s, Paint()..color = color);
    canvas.save();
    canvas.clipPath(s);
    final line = Paint()
      ..color = lineColor ?? (rule == Rule.grid ? Kit.gridScrap : Kit.rule)
      ..strokeWidth = 1;
    switch (rule) {
      case Rule.grid:
        for (var x = cell; x < size.width; x += cell) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (var y = cell; y < size.height; y += cell) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case Rule.ruled:
        for (var y = cell * 1.6; y < size.height; y += cell) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case Rule.plain:
        break;
    }
    if (margin case final m?) {
      canvas.drawLine(Offset(m, 0), Offset(m, size.height), Paint()
        ..color = Kit.margin
        ..strokeWidth = 1.5);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PaperPainter o) =>
      o.color != color || o.rule != rule || o.cell != cell || o.margin != margin || o.torn != torn || o.tornTop != tornTop;
}

/// A strip of masking tape.
class Tape extends StatelessWidget {
  const Tape({super.key, this.width = 70, this.angle = 3});
  final double width, angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle * math.pi / 180,
        child: Container(width: width, height: 20, color: Kit.tape),
      );
}

/// A scrap of field-book paper: a fine grid, turned a little, a torn bottom
/// edge, a strip of tape over the top and a flat shadow. Its children write
/// in ink. At night it is a little darker, because it is real paper.
class PaperScrap extends StatelessWidget {
  const PaperScrap({
    super.key,
    required this.child,
    this.angle = -2.5,
    this.tape = true,
    this.torn = true,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 12),
    this.color,
    this.rule = Rule.grid,
    this.cell = 11,
    this.dim = 0,
    this.tapeAt = 0.4,
  });
  final Widget child;

  /// Degrees.
  final double angle;
  final bool tape, torn;
  final EdgeInsets padding;
  final Color? color;
  final Rule rule;
  final double cell;

  /// How dark the night makes it, 0 to 1.
  final double dim;

  /// Where the tape sits along the top, 0 (left) to 1 (right).
  final double tapeAt;

  @override
  Widget build(BuildContext context) {
    final paper = Color.lerp(color ?? Kit.paper, const Color(0xFF000000), 0.18 * dim)!;
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: Stack(clipBehavior: Clip.none, children: [
        CustomPaint(
          painter: PaperPainter(color: paper, rule: rule, cell: cell, torn: torn, seed: child.hashCode & 0xff),
          child: Padding(
            padding: torn ? padding.copyWith(bottom: padding.bottom + 4) : padding,
            child: Surface(paper: true, child: DefaultTextStyle.merge(style: TextStyle(color: Kit.ink), child: child)),
          ),
        ),
        if (tape)
          Positioned(
            top: -9,
            left: 0,
            right: 0,
            child: IgnorePointer(child: Align(alignment: Alignment(tapeAt * 2 - 1, 0), child: const Tape(width: 64))),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- the luggage tag

/// The outline of a luggage tag: the top corners cut off.
Path tagPath(Size s) => Path()
  ..moveTo(s.width * 0.24, 0)
  ..lineTo(s.width * 0.76, 0)
  ..lineTo(s.width, s.height * 0.2)
  ..lineTo(s.width, s.height)
  ..lineTo(0, s.height)
  ..lineTo(0, s.height * 0.2)
  ..close();

class _TagPainter extends CustomPainter {
  _TagPainter(this.color, this.hole, {this.pressed = false});
  final Color color, hole;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = tagPath(size);
    if (!pressed) canvas.drawPath(p.shift(const Offset(0, 5)), Paint()..color = rgba(0, 0, 0, 0.3));
    canvas.drawPath(p, Paint()..color = color);
    // the eyelet
    final c = Offset(size.width / 2, 15);
    canvas.drawCircle(c, 7, Paint()..color = hex(0xB8AE98));
    canvas.drawCircle(c, 4, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(covariant _TagPainter o) => o.color != color || o.hole != hole || o.pressed != pressed;
}

/// A paper tag hanging on a string from above: Pause, and the other things
/// you reach for at the edge of the screen. It sways a little.
class LuggageTag extends StatefulWidget {
  const LuggageTag({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.width = 56,
    this.height = 72,
    this.string = 58,
    this.sway = true,
    this.on = false,
    this.phase = 0,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final double width, height, string;
  final bool sway;

  /// Turned on (Watching, the chat open): webbing orange.
  final bool on;

  /// Where in its sway it starts, so tags side by side do not swing together.
  final double phase;

  @override
  State<LuggageTag> createState() => _LuggageTagState();
}

class _LuggageTagState extends State<LuggageTag> with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 5));
  bool _down = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.sway && !MediaQuery.disableAnimationsOf(context);
    if (run && !_sway.isAnimating) {
      _sway.value = widget.phase;
      _sway.repeat();
    } else if (!run) {
      _sway.stop();
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final tag = SizedBox(
      width: widget.width,
      height: widget.string + widget.height,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: widget.width / 2 - 0.75,
          top: 0,
          width: 1.5,
          height: widget.string + 10,
          child: ColoredBox(color: Kit.blazeWhite.withValues(alpha: 0.85)),
        ),
        Positioned(
          left: 0,
          top: widget.string,
          width: widget.width,
          height: widget.height,
          child: AnimatedSlide(
            offset: Offset(0, _down ? 0.04 : 0),
            duration: const Duration(milliseconds: 80),
            child: CustomPaint(
              painter: _TagPainter(widget.on ? Kit.webbing : Kit.paper, hex(0x2A2E38), pressed: _down),
              child: Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 8),
                child: Surface(paper: true, child: Center(child: widget.child)),
              ),
            ),
          ),
        ),
      ]),
    );
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: disabled ? null : (_) => setState(() => _down = true),
          onTapUp: disabled ? null : (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedOpacity(
            opacity: disabled ? 0.45 : 1,
            duration: const Duration(milliseconds: 180),
            child: AnimatedBuilder(
              animation: _sway,
              builder: (context, child) => Transform.rotate(
                alignment: Alignment.topCenter,
                // between 2 and 5 degrees, back and forth
                angle: (widget.sway ? 3.5 + 1.5 * math.sin(_sway.value * math.pi * 2) : 0) * math.pi / 180,
                child: child,
              ),
              child: tag,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- webbing

class _WebbingPainter extends CustomPainter {
  _WebbingPainter({required this.down, required this.cut});
  final bool down;
  final double cut;

  Path _shape(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width - cut, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shape(size);
    // a flat darker copy for its shadow
    if (!down) canvas.drawPath(shape.shift(const Offset(0, 6)), Paint()..color = Color.lerp(Kit.webbing, const Color(0xFF000000), 0.55)!);
    canvas.drawPath(shape, Paint()..color = down ? Kit.webbingDown : Kit.webbing);
    canvas.save();
    canvas.clipPath(shape);
    final weave = Paint()
      ..color = Kit.weave
      ..strokeWidth = 1;
    for (var y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), weave);
    }
    final rail = Paint()..color = Kit.webbingEdge;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 5), rail);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 5, size.width, 5), rail);
    canvas.restore();
    // the bar-tack stitch on the left end
    const tack = Size(24, 40);
    canvas.save();
    canvas.translate(10, (size.height - math.min(tack.height, size.height - 14)) / 2);
    final h = math.min(tack.height, size.height - 14);
    canvas.drawPath(
        bartackPath(Size(tack.width, h)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..color = Kit.bartack);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WebbingPainter o) => o.down != down || o.cut != cut;
}

/// The one thing to do next: a strap of orange webbing with a stitched end
/// and the other end cut on a slant.
class WebbingButton extends StatefulWidget {
  const WebbingButton({super.key, required this.label, required this.onTap, this.extra, this.height = 64, this.semanticLabel, this.size = 34});
  final String label;
  final VoidCallback? onTap;

  /// Small typed text at the right end ("route A", "Enter").
  final String? extra;
  final double height, size;
  final String? semanticLabel;

  @override
  State<WebbingButton> createState() => _WebbingButtonState();
}

class _WebbingButtonState extends State<WebbingButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final h = wide ? math.max(widget.height, 70.0) : widget.height, cut = wide ? 15.0 : 12.0;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: disabled ? null : (_) => setState(() => _down = true),
          onTapUp: disabled ? null : (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedOpacity(
            opacity: disabled ? 0.38 : 1,
            duration: const Duration(milliseconds: 180),
            child: PressScale(
              enabled: !disabled,
              scale: 0.98,
              child: AnimatedSlide(
                offset: Offset(0, _down ? 4 / h : 0),
                duration: const Duration(milliseconds: 70),
                child: CustomPaint(
                  painter: _WebbingPainter(down: _down, cut: cut),
                  child: SizedBox(
                    height: h,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(44, 0, 12 + cut, 0),
                      child: Row(children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(widget.label.toUpperCase(), maxLines: 1, style: FbTxt.label(widget.size, color: Kit.ink)),
                          ),
                        ),
                        if (widget.extra case final e?) ...[
                          const SizedBox(width: 8),
                          Text(e, style: FbTxt.typed(wide ? 15 : 13, bold: true, color: Kit.ink, height: 1)),
                        ],
                      ]),
                    ),
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

// ---------------------------------------------------------------- index lines

/// Everything else in a menu: a typed number and a label, no box. An
/// underline appears on hover or focus. [chalk] writes it in chalk on the
/// rock, in your own hand ("back to me").
class IndexLine extends StatefulWidget {
  const IndexLine({
    super.key,
    required this.label,
    required this.onTap,
    this.number,
    this.size = 30,
    this.chalk = false,
    this.icon,
    this.semanticLabel,
    this.on = false,
    this.keyHint,
  });
  final String label;
  final VoidCallback? onTap;

  /// "02", "03"…: its place in the menu. None for a lone line.
  final int? number;
  final double size;
  final bool chalk;
  final IconData? icon;
  final String? semanticLabel;

  /// Picked (the pencil circles it).
  final bool on;

  /// A key that does the same, shown in a box on a desktop.
  final String? keyHint;

  @override
  State<IndexLine> createState() => _IndexLineState();
}

class _IndexLineState extends State<IndexLine> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final ink = widget.chalk ? Kit.chalk : Surface.ink(context);
    final style = widget.chalk ? FbTxt.hand(widget.size + 4, color: ink) : FbTxt.label(widget.size, color: ink);
    final line = Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (widget.number case final n?) ...[
        Text(n.toString().padLeft(2, '0'), style: FbTxt.typed(14, bold: true, color: ink, height: 1)),
        const SizedBox(width: 10),
      ],
      if (widget.icon case final i?) ...[Icon(i, size: widget.size * 0.62, color: ink), const SizedBox(width: 8)],
      Flexible(
        child: Container(
          padding: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: (_hover || _focus) && !disabled ? ink : Colors.transparent, width: 2)),
          ),
          child: Text(widget.chalk ? widget.label : widget.label.toUpperCase(),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(height: 1.05)),
        ),
      ),
      if (widget.keyHint case final k?) ...[const SizedBox(width: 10), KeyHint(k, color: ink)],
    ]);
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: !disabled,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        mouseCursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedOpacity(
            opacity: disabled ? 0.4 : 1,
            duration: const Duration(milliseconds: 180),
            child: PressScale(
              enabled: !disabled,
              scale: 0.97,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: widget.on ? CustomPaint(foregroundPainter: PencilRing(color: ink), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: line)) : line,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A key on the keyboard that does the same thing, in a typed box.
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Surface.ink(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: ink, width: 2)),
      child: Text(label, style: FbTxt.typed(12, bold: true, color: ink, height: 1.2)),
    );
  }
}

// ---------------------------------------------------------------- pencil

/// A pencil ring drawn round something picked, not quite closed.
class PencilRing extends CustomPainter {
  PencilRing({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rng(size.width.round() * 7 + size.height.round());
    final c = size.center(Offset.zero), rx = size.width / 2 + 6, ry = size.height / 2 + 3;
    final p = Path();
    const n = 40;
    for (var i = 0; i <= n + 4; i++) {
      final t = -2.4 + i / n * math.pi * 2, wob = 1 + (r() - 0.5) * 0.04;
      final o = c + Offset(math.cos(t) * rx * wob, math.sin(t) * ry * wob);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant PencilRing o) => o.color != color;
}

/// A box drawn in pencil, ticked when [on].
class PencilBox extends StatelessWidget {
  const PencilBox({super.key, required this.on, this.size = 22});
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _PencilBoxPainter(on, Surface.ink(context))));
}

class _PencilBoxPainter extends CustomPainter {
  _PencilBoxPainter(this.on, this.color);
  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final w = size.width, h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(2, 3)
          ..lineTo(w - 2.5, 2)
          ..lineTo(w - 2, h - 2.5)
          ..lineTo(2.5, h - 2)
          ..close(),
        p);
    if (on) {
      canvas.drawPath(
          Path()
            ..moveTo(5, h * 0.55)
            ..lineTo(w * 0.42, h - 5)
            ..lineTo(w + 3, -3),
          p
            ..strokeWidth = 2.6
            ..color = Kit.blaze);
    }
  }

  @override
  bool shouldRepaint(covariant _PencilBoxPainter o) => o.on != on || o.color != color;
}

// ---------------------------------------------------------------- tallies and stamps

/// Tally marks: strokes, every fifth one crossing the four before it.
class TallyMarks extends StatelessWidget {
  const TallyMarks({super.key, required this.count, this.color, this.height = 22, this.label});
  final int count;
  final Color? color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(0, 99), groups = n ~/ 5, rest = n % 5;
    final w = 6 + groups * 42 + rest * 8 + 4.0;
    final ink = color ?? Surface.ink(context);
    return Semantics(
      label: label ?? '$count',
      excludeSemantics: true,
      child: SizedBox(
        width: (n == 0 ? 14 : w) * height / 28,
        height: height,
        child: CustomPaint(painter: _TallyPainter(n, ink)),
      ),
    );
  }
}

class _TallyPainter extends CustomPainter {
  _TallyPainter(this.n, this.color);
  final int n;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 28);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (n == 0) {
      // nothing yet: a short dash
      canvas.drawLine(const Offset(3, 14), const Offset(11, 14), p..color = color.withValues(alpha: 0.5));
      return;
    }
    canvas.drawPath(tallyPath(n), p);
  }

  @override
  bool shouldRepaint(covariant _TallyPainter o) => o.n != n || o.color != color;
}

/// A rubber stamp, a little worn: a circle or a box in blaze red (or ink),
/// a 5 px outline and a 2 px inner line, turned, with a word in Archivo and
/// a typed number. For what is final: TOP, FELL, the route's grade, Daily.
class InkStamp extends StatelessWidget {
  const InkStamp({super.key, required this.word, this.number, this.circle = false, this.color, this.angle = -10, this.size = 1, this.semanticLabel});
  final String word;
  final String? number;
  final bool circle;
  final Color? color;
  final double angle, size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final col = color ?? Kit.blaze;
    final w = (circle ? 96.0 : (word.length * 17.0 + 36).clamp(64.0, 260.0)) * size;
    final h = (circle ? 96.0 : (number == null ? 54.0 : 74.0)) * size;
    return Semantics(
      label: semanticLabel ?? [word, number].whereType<String>().join(' '),
      excludeSemantics: true,
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: SizedBox(
          width: w,
          height: h,
          child: CachedPaint(cacheKey: 'stamp-$word-$number-$circle-${col.toARGB32()}', painter: _StampPainter(word, number, circle, col)),
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.word, this.number, this.circle, this.color);
  final String word;
  final String? number;
  final bool circle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.saveLayer(box.inflate(4), Paint());
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;
    if (circle) {
      final c = size.center(Offset.zero), r = math.min(size.width, size.height) / 2 - 3;
      canvas.drawCircle(c, r, line..strokeWidth = 5);
      canvas.drawCircle(c, r - 7, line..strokeWidth = 2);
    } else {
      canvas.drawRect(box.deflate(3), line..strokeWidth = 5);
      canvas.drawRect(box.deflate(10), line..strokeWidth = 2);
    }
    final k = size.height / (circle ? 96 : (number == null ? 54 : 74));
    final wp = TextPainter(
      text: TextSpan(text: word.toUpperCase(), style: FbTxt.label(30 * k, color: color, spacing: 0.04)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 20);
    final np = number == null
        ? null
        : (TextPainter(
            text: TextSpan(text: number, style: FbTxt.typed(16 * k, bold: true, color: color, height: 1)),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: size.width - 20));
    final total = wp.height + (np == null ? 0 : np.height + 3 * k);
    var y = (size.height - total) / 2;
    wp.paint(canvas, Offset((size.width - wp.width) / 2, y));
    y += wp.height + 3 * k;
    np?.paint(canvas, Offset((size.width - np.width) / 2, y));
    wp.dispose();
    np?.dispose();
    // worn ink: specks where it did not take
    final r = Rng(word.length * 31 + (number?.length ?? 0));
    final hole = Paint()..blendMode = BlendMode.dstOut;
    for (var i = 0; i < (size.width * size.height / 30).round(); i++) {
      hole.color = rgba(0, 0, 0, 0.3 + r() * 0.6);
      canvas.drawCircle(Offset(r() * size.width, r() * size.height), 0.4 + r() * 1.1, hole);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StampPainter o) => o.word != word || o.number != number || o.circle != circle || o.color != color;
}

// ---------------------------------------------------------------- the field book page

/// A field-book page: ruled lines, a red margin, a spiral binding along the
/// top (or, [spread], an open book with the rings down the middle).
class FieldPage extends StatelessWidget {
  const FieldPage({super.key, required this.child, this.padding, this.spread = false, this.tornTop = 0, this.angle = -1, this.dim = 0, this.rings = true});
  final Widget child;
  final EdgeInsets? padding;
  final bool spread, rings;

  /// A tear across the bottom (see [PaperPainter.tornTop]).
  final double tornTop;
  final double angle, dim;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final rule = wide ? 30.0 : 26.0, margin = wide ? 74.0 : 66.0;
    final paper = Color.lerp(Kit.paper, const Color(0xFF000000), 0.18 * dim)!;
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: Stack(clipBehavior: Clip.none, children: [
        CustomPaint(
          painter: PaperPainter(color: paper, rule: Rule.ruled, cell: rule, margin: spread ? null : margin, tornTop: tornTop, shadow: 8, seed: 5),
          foregroundPainter: rings ? _RingsPainter(spread: spread) : null,
          child: Padding(
            padding: padding ?? EdgeInsets.fromLTRB(spread ? 36 : margin + 12, rings ? 40 : 22, 22, 22 + tornTop),
            child: Surface(paper: true, child: DefaultTextStyle.merge(style: TextStyle(color: Kit.ink), child: child)),
          ),
        ),
      ]),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.spread});
  final bool spread;

  @override
  void paint(Canvas canvas, Size size) {
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = hex(0x9AA0A8);
    final hole = Paint()..color = hex(0x2A2E38);
    if (spread) {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = rgba(0, 0, 0, 0.18)
        ..strokeWidth = 6);
      for (var y = 24.0; y < size.height - 12; y += 26) {
        canvas.drawCircle(Offset(x - 10, y), 3, hole);
        canvas.drawCircle(Offset(x + 10, y), 3, hole);
        canvas.drawArc(Rect.fromCenter(center: Offset(x, y - 2), width: 22, height: 14), math.pi, math.pi, false, wire);
      }
      return;
    }
    for (var x = 22.0; x < size.width - 14; x += 22) {
      canvas.drawCircle(Offset(x, 16), 3.2, hole);
      canvas.drawArc(Rect.fromCenter(center: Offset(x, 10), width: 10, height: 22), math.pi, math.pi * 1.1, false, wire);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter o) => o.spread != spread;
}

/// A typed log line: a bold label column, then the text.
class LogLine extends StatelessWidget {
  const LogLine({super.key, required this.label, required this.text, this.labelWidth = 64, this.size = 16, this.cursor = false, this.color});
  final String label, text;
  final double labelWidth, size;

  /// The last line ends with a blinking block cursor.
  final bool cursor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Surface.ink(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: labelWidth, child: Text(label, style: FbTxt.typed(size, bold: true, color: ink))),
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text),
          if (cursor) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(left: 4), child: _Cursor())),
        ]), style: FbTxt.typed(size, color: ink)),
      ),
    ]);
  }
}

class _Cursor extends StatefulWidget {
  const _Cursor();
  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Surface.ink(context);
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(opacity: _blink.value < 0.55 ? 1 : 0, child: Container(width: 9, height: 16, color: ink)),
    );
  }
}

/// A row of a typed table with dotted leaders: `LENGTH ........ 38 m`.
class LeaderRow extends StatelessWidget {
  const LeaderRow({super.key, required this.label, required this.value, this.size = 15});
  final String label;
  final Widget value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = Surface.ink(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(label.toUpperCase(), style: FbTxt.typed(size, bold: true, color: ink, height: 1.2)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: LayoutBuilder(builder: (context, c) {
              final n = math.max(0, (c.maxWidth / (size * 0.6)).floor());
              return Text('.' * n, maxLines: 1, overflow: TextOverflow.clip, style: FbTxt.typed(size, color: ink.withValues(alpha: 0.6), height: 1.2));
            }),
          ),
        ),
        DefaultTextStyle.merge(style: FbTxt.typed(size, bold: true, color: ink, height: 1.2), child: value),
      ]),
    );
  }
}

/// A section heading in the field book: a typed "§1" and a title in Archivo.
class SectionHead extends StatelessWidget {
  const SectionHead({super.key, required this.number, required this.title, this.size = 30});
  final int number;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = Surface.ink(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
      Text('§$number', style: FbTxt.typed(15, bold: true, color: ink)),
      const SizedBox(width: 10),
      Flexible(child: Text(title.toUpperCase(), style: FbTxt.label(size, color: ink))),
    ]);
  }
}
