// Small motions the whole UI shares. Each one plays once when something
// appears or changes, or only while something happens; none runs on its
// own all the time, and none plays when the phone asks for less motion.
//
//  - [Once]: a value from 0 to 1 over a short time, for everything below.
//  - [WriteIn]: handwriting writes itself in, left to right.
//  - [TypeIn]: typed text types itself out, a letter at a time.
//  - [Settle]: a piece of paper lands and settles at its angle.
//  - [StampIn]: a rubber stamp comes down, settles, and thumps.
//  - [DrawUp]: a drawing appears from the bottom up, as if drawn.
//  - [Swing]: something hanging from a string swings when it is knocked.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Whether to animate here (the phone has not asked for less motion).
bool moving(BuildContext context) => !MediaQuery.disableAnimationsOf(context);

/// Builds [builder] with a value going from 0 to 1 over [duration] (after
/// [delay]), when it first shows (unless [onShow] is false) and again each
/// time [replay] changes. With less motion the value is always 1. Its child
/// keeps its state when it replays.
class Once extends StatefulWidget {
  const Once({
    super.key,
    required this.builder,
    this.replay,
    this.duration = const Duration(milliseconds: 420),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
    this.onShow = true,
    this.child,
  });
  final ValueWidgetBuilder<double> builder;
  final Object? replay;
  final Duration duration, delay;
  final Curve curve;
  final bool onShow;
  final Widget? child;

  @override
  State<Once> createState() => _OnceState();
}

class _OnceState extends State<Once> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: widget.onShow ? 0 : 1);
  bool _still = false, _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = !moving(context);
    if (!_started) {
      _started = true;
      if (widget.onShow) _play();
    }
    if (_still) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant Once old) {
    super.didUpdateWidget(old);
    if (old.replay != widget.replay) _play();
  }

  void _play() {
    if (_still) {
      _c.value = 1;
      return;
    }
    _c.duration = widget.delay + widget.duration;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _t {
    final total = (widget.delay + widget.duration).inMicroseconds;
    if (total == 0) return 1;
    final start = widget.delay.inMicroseconds / total;
    return widget.curve.transform(((_c.value - start) / (1 - start)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (context, child) => widget.builder(context, _t, child), child: widget.child);
}

/// Handwriting that writes itself in, left to right, when it shows and
/// when [replay] changes.
class WriteIn extends StatelessWidget {
  const WriteIn({super.key, required this.child, this.replay, this.duration = const Duration(milliseconds: 560), this.delay = Duration.zero});
  final Widget child;
  final Object? replay;
  final Duration duration, delay;

  @override
  Widget build(BuildContext context) => Once(
        replay: replay,
        duration: duration,
        delay: delay,
        curve: Curves.easeInOutSine,
        builder: (context, t, child) => t >= 1 ? child! : ClipRect(clipper: _Wipe(t, up: false), child: child),
        child: child,
      );
}

/// A drawing that appears from the bottom up, as if drawn from the ground.
class DrawUp extends StatelessWidget {
  const DrawUp({super.key, required this.child, this.replay, this.duration = const Duration(milliseconds: 640)});
  final Widget child;
  final Object? replay;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Once(
        replay: replay,
        duration: duration,
        curve: Curves.easeInOutCubic,
        builder: (context, t, child) => t >= 1 ? child! : ClipRect(clipper: _Wipe(t, up: true), child: child),
        child: child,
      );
}

/// Shows [t] of a box: from the left, or ([up]) from the bottom. A little
/// more than the box across the other way, for ink that sticks out.
class _Wipe extends CustomClipper<Rect> {
  _Wipe(this.t, {required this.up});
  final double t;
  final bool up;

  @override
  Rect getClip(Size s) => up
      ? Rect.fromLTRB(-s.width, s.height * (1 - t), s.width * 2, s.height + 8)
      : Rect.fromLTRB(-6, -s.height, -6 + (s.width + 12) * t, s.height * 2);

  @override
  bool shouldReclip(covariant _Wipe o) => o.t != t || o.up != up;
}

/// Typed text that types itself out, a letter every [perLetter], when it
/// shows and when [replay] changes. The rest is there but clear, so nothing
/// moves while it types, and screen readers read it all at once.
class TypeIn extends StatelessWidget {
  const TypeIn(this.text,
      {super.key, this.style, this.replay, this.perLetter = const Duration(milliseconds: 24), this.delay = Duration.zero, this.textAlign, this.maxLines});
  final String text;
  final TextStyle? style;
  final Object? replay;
  final Duration perLetter, delay;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Once(
        replay: replay ?? text,
        duration: perLetter * text.length,
        delay: delay,
        curve: Curves.linear,
        builder: (context, t, _) {
          final n = (text.length * t).round();
          if (n >= text.length) return Text(text, style: style, textAlign: textAlign, maxLines: maxLines);
          return Text.rich(
            TextSpan(children: [
              TextSpan(text: text.substring(0, n)),
              TextSpan(text: text.substring(n), style: const TextStyle(color: Color(0x00000000))),
            ]),
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
          );
        },
      );
}

/// A piece of paper that lands: it comes down [drop] px, turned [turn]
/// degrees more than it rests, and settles with a little give.
class Settle extends StatelessWidget {
  const Settle({super.key, required this.child, this.turn = 3, this.drop = 10, this.delay = Duration.zero, this.replay});
  final Widget child;
  final double turn, drop;
  final Duration delay;
  final Object? replay;

  @override
  Widget build(BuildContext context) => Once(
        replay: replay,
        duration: const Duration(milliseconds: 480),
        delay: delay,
        curve: Curves.easeOutBack,
        builder: (context, t, child) => t >= 1
            ? child!
            : Transform.translate(
                offset: Offset(0, -(1 - t) * drop),
                child: Transform.rotate(angle: (1 - t) * turn * math.pi / 180, child: child),
              ),
        child: child,
      );
}

/// A rubber stamp coming down: big and light, then pressed flat with a
/// little turn, and a few short strokes of the thump around it.
class StampIn extends StatelessWidget {
  const StampIn({super.key, required this.child, this.replay, this.delay = const Duration(milliseconds: 180), this.color});
  final Widget child;
  final Object? replay;
  final Duration delay;

  /// The thump's colour (the stamp's ink); none without it.
  final Color? color;

  @override
  Widget build(BuildContext context) => Once(
        replay: replay,
        delay: delay,
        duration: const Duration(milliseconds: 720),
        curve: Curves.linear,
        builder: (context, t, child) {
          if (t >= 1) return child!;
          // the first 40%: down; then the thump spreads and fades
          final down = Curves.easeOutBack.transform((t / 0.4).clamp(0.0, 1.0)), thump = ((t - 0.34) / 0.66).clamp(0.0, 1.0);
          return CustomPaint(
            painter: color == null || thump <= 0 ? null : _ThumpPainter(thump, color!),
            child: Opacity(
              opacity: (t / 0.16).clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: (1 - down) * 7 * math.pi / 180,
                child: Transform.scale(scale: 1.55 - 0.55 * down, child: child),
              ),
            ),
          );
        },
        child: child,
      );
}

class _ThumpPainter extends CustomPainter {
  _ThumpPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), rx = size.width / 2, ry = size.height / 2;
    final e = Curves.easeOutCubic.transform(t);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.7 * (1 - t) * (1 - t));
    // strokes all round, a little uneven, like the lines drawn round a thud
    for (var i = 0; i < 8; i++) {
      final ang = i * math.pi / 4 + 0.3 + (i.isEven ? 0.12 : -0.1);
      final d = Offset(math.cos(ang), math.sin(ang)), out = 1.06 + 0.22 * e;
      final a = c + Offset(d.dx * rx * out, d.dy * ry * out);
      canvas.drawLine(a, a + d * (6 + 8 * (1 - e)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ThumpPainter o) => o.t != t || o.color != color;
}

/// Something hanging from the middle of its top (a tag on a string, gear on
/// the rack): it swings when knocked and settles by itself, like a damped
/// pendulum. It is knocked when [kicks] notifies, when it is tapped (if
/// [tap]), and once as it appears (if [swingIn]). [seed] gives each one its
/// own way of swinging, so things side by side do not swing together.
class Swing extends StatefulWidget {
  const Swing({super.key, required this.child, this.kicks, this.strength = 1, this.seed = 0, this.swingIn = false, this.tap = true});
  final Widget child;
  final Listenable? kicks;
  final double strength;
  final int seed;
  final bool swingIn, tap;

  @override
  State<Swing> createState() => _SwingState();
}

class _SwingState extends State<Swing> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _a = 0, _v = 0;
  Duration _last = Duration.zero;
  bool _still = false, _started = false;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    widget.kicks?.addListener(_knock);
  }

  @override
  void didUpdateWidget(covariant Swing old) {
    super.didUpdateWidget(old);
    if (old.kicks != widget.kicks) {
      old.kicks?.removeListener(_knock);
      widget.kicks?.addListener(_knock);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = !moving(context);
    if (!_started) {
      _started = true;
      if (widget.swingIn) _kick(1.4);
    }
  }

  @override
  void dispose() {
    widget.kicks?.removeListener(_knock);
    _ticker.dispose();
    super.dispose();
  }

  void _knock() => _kick(1);

  /// Pushes it with [k] times its usual push, to one side or the other.
  void _kick(double k) {
    if (_still || !mounted) return;
    final h = (widget.seed * 0.618 + _n++ * 0.371) % 1;
    _v += (h < 0.5 ? -1 : 1) * (0.55 + 0.4 * h) * widget.strength * k;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = now;
    // a short string: a quick swing that dies away in about two seconds
    const w = 8.5, zeta = 0.15;
    _v += (-w * w * _a - 2 * zeta * w * _v) * dt;
    _a += _v * dt;
    if (_a.abs() < 0.0006 && _v.abs() < 0.004) {
      _a = _v = 0;
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = Transform.rotate(alignment: Alignment.topCenter, angle: _a, child: widget.child);
    if (!widget.tap) return body;
    return Listener(onPointerDown: (_) => _kick(0.8), child: body);
  }
}
