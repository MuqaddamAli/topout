import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/field_book.dart';
import '../game/game.dart';
import '../game/mountain.dart';
import '../game/palette.dart';
import 'kit.dart';
import 'motion.dart';
import 'widgets.dart';

/// Rebuilds [builder] only when [select] gives a new value. It is checked
/// every frame, but most frames nothing on the HUD changes, so nothing is
/// built or laid out again.
class FrameSelect<T> extends StatefulWidget {
  const FrameSelect({super.key, required this.game, required this.select, required this.builder});
  final Game game;
  final T Function(Game g) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<FrameSelect<T>> createState() => _FrameSelectState<T>();
}

class _FrameSelectState<T> extends State<FrameSelect<T>> {
  late T _v = widget.select(widget.game);

  @override
  void initState() {
    super.initState();
    widget.game.frameTick.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant FrameSelect<T> old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.frameTick.removeListener(_tick);
      widget.game.frameTick.addListener(_tick);
    }
    _v = widget.select(widget.game);
  }

  @override
  void dispose() {
    widget.game.frameTick.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final v = widget.select(widget.game);
    if (v != _v) setState(() => _v = v);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _v);
}

/// How dark it is where the view is, in steps of a twentieth (paper on the
/// screen gets a little darker at night).
double _nightOf(Game g) {
  final r = g.route;
  if (r == null) return 0;
  return (Mountain.night(Mountain.hourAt(r, g.camY)) * 20).round() / 20;
}

/// The climbing screen, as things a climber carries: a paper scrap with the
/// route and the time (top left), Pause on a luggage tag (top right), an
/// altimeter tape down the left edge, and a gear rack along the bottom with
/// Undo, Look, each hand's strength and what is going on.
///
/// The HUD itself is built when the game state changes (a move, a toast, a
/// tip); the numbers that change while you climb rebuild on their own.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final r = game.route;
    if (r == null) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context), size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700, keys = !game.usedTouch && !game.portrait;
    final rackH = wide ? 176.0 : 156.0;
    return Stack(children: [
      // ---------------- the route, the time and the counts
      Positioned(
        left: pad.left + 14,
        top: pad.top + 22,
        child: FrameSelect(
          game: game,
          select: _nightOf,
          builder: (context, night) => _RouteScrap(game: game, width: wide ? 220 : 176, dim: night),
        ),
      ),
      // ---------------- Pause
      Positioned(
        right: pad.right + 18,
        top: 0,
        child: LuggageTag(
          width: wide ? 64 : 56,
          height: wide ? 92 : 72,
          string: 40 + pad.top,
          semanticLabel: 'Pause',
          kicks: game.jolts,
          onTap: () => _tap(game.pause),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _PauseBars(),
            if (keys) ...[const SizedBox(height: 6), const KeyHint('ESC')],
          ]),
        ),
      ),
      // ---------------- the altimeter
      Positioned(
        left: pad.left,
        top: size.height * 0.27,
        height: size.height * 0.46,
        width: 120,
        child: IgnorePointer(child: _Altimeter(game: game, wide: wide)),
      ),
      // ---------------- a short message under the top edge
      Positioned(
        left: 60,
        right: 60,
        top: pad.top + (wide ? 150 : 138),
        child: IgnorePointer(
          child: FrameSelect(
            game: game,
            select: (g) => g.toastVisible ? (g.toastText ?? '', g.toastKind, g.toastUntil) : null,
            builder: (context, t) => Center(child: GameToast(toast: t)),
          ),
        ),
      ),
      // ---------------- with others: quick chat; online at the top: End climb (the creator) and Watch
      if (game.social)
        Positioned(
          right: pad.right + 10,
          top: pad.top + (wide ? 150 : 132),
          child: _SocialTags(game: game, keys: keys, onTap: _tap),
        ),
      // ---------------- emotes, while you stand with others
      if (game.social)
        Positioned(
          right: pad.right + 10,
          bottom: pad.bottom + rackH + 8,
          child: FrameSelect(
            game: game,
            select: (g) => (g.canEmote, g.clock >= g.nextEmoteAt, g.emote),
            builder: (context, v) => _Appear(
              visible: v.$1,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (e, icon) in const [
                  (Emote.cheer, Icons.celebration_rounded),
                  (Emote.taunt, Icons.waving_hand_rounded),
                  (Emote.aura, Icons.self_improvement_rounded),
                ]) ...[
                  _PaperTag(
                    label: e.label,
                    icon: icon,
                    on: v.$3 == e,
                    keyHint: keys ? '${e.index + 1}' : null,
                    semanticLabel: '${e.label} (key ${e.index + 1})',
                    angle: e.index.isEven ? -3 : 2,
                    onTap: v.$1 && v.$2 ? () => _tap(() => game.doEmote(e)) : null,
                  ),
                  const SizedBox(height: 6),
                ],
              ]),
            ),
          ),
        ),
      // ---------------- back to the climber after looking around: in chalk
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + rackH + 56,
        child: Center(
          child: _Appear(
            visible: game.showRecenter,
            child: WriteIn(replay: game.showRecenter, child: IndexLine(label: 'back to me', chalk: true, onTap: () => _tap(game.recenter))),
          ),
        ),
      ),
      // ---------------- tip: a taped scrap above the rack
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + rackH + 6,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            reverseDuration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: game.tipText == null
                ? const SizedBox.shrink()
                : _TipCard(key: ValueKey(game.tipText), game: game, text: game.tipText!),
          ),
        ),
      ),
      // ---------------- the gear rack
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom,
        height: rackH,
        child: _Rack(game: game, wide: wide, keys: keys, onTap: _tap),
      ),
    ]);
  }
}

class _PauseBars extends StatelessWidget {
  const _PauseBars();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 4.5, height: 20, color: Kit.ink),
        const SizedBox(width: 5.5),
        Container(width: 4.5, height: 20, color: Kit.ink),
      ]);
}

/// The route's name, the mode and the climber, the time, and tally marks
/// for this climb's falls and catches. Online, everyone's height too.
class _RouteScrap extends StatelessWidget {
  const _RouteScrap({required this.game, required this.width, required this.dim});
  final Game game;
  final double width, dim;

  @override
  Widget build(BuildContext context) {
    final r = game.route!;
    final small = FbTxt.typed(11.5, bold: true, height: 1.25);
    return IgnorePointer(
      child: SizedBox(
        width: width,
        // it is taped up at the start of a climb
        child: Settle(
          turn: -4,
          drop: 16,
          delay: const Duration(milliseconds: 120),
          child: PaperScrap(
            dim: dim,
            tapeAt: 0.45,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: FbTxt.label(width > 200 ? 24 : 20)),
              const SizedBox(height: 3),
              Text(
                '${r.endless ? 'DAILY · ' : ''}${game.mode.label} · ${game.climber.name}'.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
              const SizedBox(height: 2),
              FrameSelect(
                game: game,
                select: (g) => fmtTime(g.time),
                builder: (context, t) => Text('TIME  $t', style: FbTxt.typed(13, bold: true, height: 1.3)),
              ),
              const SizedBox(height: 2),
              FrameSelect(
                game: game,
                select: (g) => (g.falls, g.caught),
                builder: (context, v) => Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [Text('FELL ', style: small), TallyMarks(count: math.min(v.$1, 15), height: 15, label: '${v.$1} falls')]),
                  Row(mainAxisSize: MainAxisSize.min, children: [Text('CAUGHT ', style: small), TallyMarks(count: math.min(v.$2, 15), height: 15, label: '${v.$2} caught')]),
                ]),
              ),
              if (game.onlineClimb) _Heights(game: game),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Everyone in the room, finished first and then highest first: typed
/// lines on the route's scrap, you in bold. It rebuilds only when a shown
/// number changes.
class _Heights extends StatelessWidget {
  const _Heights({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.standingsChanged,
      builder: (context, _) {
        final list = game.standings;
        if (list.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < list.length; i++) _HeightRow(place: i + 1, s: list[i]),
          ]),
        );
      },
    );
  }
}

class _HeightRow extends StatelessWidget {
  const _HeightRow({required this.place, required this.s});
  final int place;
  final Standing s;

  @override
  Widget build(BuildContext context) {
    final f = s.finish;
    final value = f != null ? fmtTime(f) : '${s.metres.toStringAsFixed(1)} m';
    final style = FbTxt.typed(12, bold: s.you, height: 1.3, color: s.you ? Kit.blaze : Kit.ink);
    return Semantics(
      label: '$place, ${s.you ? 'you' : s.name}, ${f != null ? 'topped out in $value' : value}',
      excludeSemantics: true,
      child: Opacity(
        opacity: s.connected ? 1 : 0.45,
        child: Row(children: [
          SizedBox(width: 15, child: Text('$place', style: style)),
          Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          const SizedBox(width: 4),
          if (f != null) Text('✓ ', style: style),
          Text(value, style: style),
        ]),
      ),
    );
  }
}

/// Fades and grows in when [visible], and the other way out. Hidden children take no taps.
class _Appear extends StatelessWidget {
  const _Appear({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedScale(
          scale: visible ? 1 : 0.85,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: child,
        ),
      ),
    );
  }
}

/// A small paper tag you can tap: a label (and a drawing), turned a little.
class _PaperTag extends StatelessWidget {
  const _PaperTag({required this.label, required this.onTap, this.icon, this.on = false, this.keyHint, this.semanticLabel, this.angle = 0});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool on;
  final String? keyHint, semanticLabel;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedOpacity(
            opacity: disabled ? 0.45 : 1,
            duration: const Duration(milliseconds: 180),
            child: PressScale(
              child: Transform.rotate(
                angle: angle * math.pi / 180,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  decoration: BoxDecoration(
                    color: on ? Kit.webbing : Kit.paper,
                    boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.3), offset: const Offset(0, 4))],
                  ),
                  child: Surface(
                    paper: true,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon case final i?) ...[Icon(i, size: 20, color: Kit.ink), const SizedBox(width: 6)],
                      Text(label, style: FbTxt.typed(14, bold: true, height: 1.1)),
                      if (keyHint case final k?) ...[const SizedBox(width: 8), KeyHint(k)],
                    ]),
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

/// Online and with others: Chat (and its phrases), End climb and Watch, as
/// tags on the right under Pause.
class _SocialTags extends StatelessWidget {
  const _SocialTags({required this.game, required this.keys, required this.onTap});
  final Game game;
  final bool keys;
  final void Function(VoidCallback f) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      FrameSelect(
        game: game,
        select: (g) => (g.canChat, g.chatOpen, g.clock >= g.nextChatAt),
        builder: (context, v) => _Appear(
          visible: v.$1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _PaperTag(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              on: v.$2,
              angle: 2,
              onTap: v.$1 ? () => onTap(game.toggleChat) : null,
            ),
            if (v.$2)
              for (final (i, text) in quickChat.indexed) ...[
                const SizedBox(height: 6),
                _PaperTag(
                  label: '$text  ${'QWER'[i]}',
                  angle: i.isEven ? -2 : 1.5,
                  onTap: v.$3 ? () => onTap(() => game.say(i)) : null,
                ),
              ],
          ]),
        ),
      ),
      if (game.onlineClimb) ...[
        const SizedBox(height: 8),
        FrameSelect(
          game: game,
          select: (g) => g.toppedOut && g.online.isHost && !(g.online.room?.ended ?? true),
          builder: (context, show) => _Appear(
            visible: show,
            child: _PaperTag(label: 'End climb', angle: -2, onTap: show ? () => onTap(game.endClimb) : null),
          ),
        ),
        const SizedBox(height: 8),
        FrameSelect(
          game: game,
          select: (g) => (g.canWatch, g.watchingName),
          builder: (context, v) => _Appear(
            visible: v.$1,
            child: _PaperTag(
              label: v.$2 == null ? 'Watch' : 'Watching ${v.$2}',
              icon: Icons.visibility_outlined,
              on: v.$2 != null,
              keyHint: keys ? 'TAB' : null,
              angle: 1.5,
              semanticLabel: 'Watch another climber (Tab)',
              onTap: v.$1 ? () => onTap(game.watchNext) : null,
            ),
          ),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- the altimeter

/// A tape down the left edge that moves under a fixed pointer: a tick every
/// metre, a number every five, your best height in blaze red, and the
/// ledges' lamps (lit ones bright). The height is a webbing tag in the middle.
class _Altimeter extends StatelessWidget {
  const _Altimeter({required this.game, required this.wide});
  final Game game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final r = game.route!;
    return FrameSelect(
      game: game,
      select: (g) {
        g.refreshTicks();
        return (h: (g.climberHeight() * 10).round() / 10, best: g.bestHeight(r), lit: g.lit.length, ticks: g.ticks.length, span: g.progSpan());
      },
      builder: (context, v) {
        final h = v.h.toStringAsFixed(1);
        return Semantics(
          label: 'Height $h metres',
          excludeSemantics: true,
          child: LayoutBuilder(builder: (context, c) {
            final strip = wide ? 62.0 : 46.0;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: strip,
                child: CustomPaint(
                  painter: _TapePainter(
                    height: v.h,
                    best: v.best,
                    top: r.endless ? null : v.span,
                    lamps: [for (final t in game.ticks) (t.pos * v.span, game.tickLit(t))],
                    perMetre: wide ? 14 : 12,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: c.maxHeight / 2 - 15,
                // it gives a small jump when a lamp comes on
                child: Once(
                  replay: v.lit,
                  onShow: false,
                  duration: const Duration(milliseconds: 620),
                  builder: (context, t, child) =>
                      Transform.scale(alignment: Alignment.centerLeft, scale: 1 + 0.16 * math.sin(t * math.pi) * (1 - t * 0.4), child: child),
                  child: _HeightTag(text: h, big: wide),
                ),
              ),
            ]);
          }),
        );
      },
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({required this.height, required this.best, required this.top, required this.lamps, required this.perMetre});
  final double height, best, perMetre;
  final double? top;
  final List<(double, bool)> lamps;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Kit.shade);
    canvas.drawRect(Rect.fromLTWH(size.width - 1.5, 0, 1.5, size.height), Paint()..color = Kit.blazeWhite.withValues(alpha: 0.55));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final mid = size.height / 2;
    double y(double m) => mid - (m - height) * perMetre;
    final tick = Paint()
      ..color = Kit.blazeWhite.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    final long = Paint()
      ..color = Kit.blazeWhite
      ..strokeWidth = 2;
    final lo = (height - mid / perMetre).floor() - 1, hi = (height + mid / perMetre).ceil() + 1;
    for (var m = math.max(0, lo); m <= hi; m++) {
      if (top != null && m > top! + 0.01) break;
      final yy = y(m.toDouble());
      if (m % 5 == 0) {
        canvas.drawLine(Offset(size.width - 16, yy), Offset(size.width, yy), long);
        final tp = TextPainter(
          text: TextSpan(text: '$m', style: FbTxt.typed(10, bold: true, color: Kit.blazeWhite, height: 1)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - 19 - tp.width, yy - tp.height / 2));
        tp.dispose();
      } else {
        canvas.drawLine(Offset(size.width - 10, yy), Offset(size.width, yy), tick);
      }
    }
    // the top of the route
    if (top case final t?) {
      final yy = y(t);
      canvas.drawRect(Rect.fromLTWH(size.width - 22, yy - 2, 22, 4), Paint()..color = Kit.webbing);
    }
    // the ledges' lamps
    for (final (m, lit) in lamps) {
      final yy = y(m);
      if (yy < -10 || yy > size.height + 10) continue;
      final c = Offset(size.width - 30, yy);
      canvas.drawCircle(c, 4, Paint()..color = lit ? Pal.lamp : rgba(0, 0, 0, 0));
      canvas.drawCircle(
          c,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = lit ? Pal.lamp : Kit.blazeWhite.withValues(alpha: 0.6));
    }
    // your best
    if (best > 0.5) {
      final yy = y(best);
      canvas.drawRect(Rect.fromLTWH(size.width - 26, yy - 1.75, 26, 3.5), Paint()..color = Kit.blaze);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TapePainter o) =>
      o.height != height || o.best != best || o.top != top || o.lamps.length != lamps.length || o.lamps.any((l) => l.$2) != lamps.any((l) => l.$2);
}

/// The height now: a webbing tag with an arrow tip.
class _HeightTag extends StatelessWidget {
  const _HeightTag({required this.text, required this.big});
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _ArrowClip(),
      child: Container(
        height: 30,
        padding: const EdgeInsets.fromLTRB(8, 0, 18, 0),
        decoration: BoxDecoration(
          color: Kit.webbing,
          border: Border.symmetric(horizontal: BorderSide(color: Kit.webbingEdge, width: 3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(text, style: FbTxt.label(big ? 26 : 24, color: Kit.ink).copyWith(height: 1)),
          const SizedBox(width: 3),
          Text('m', style: FbTxt.typed(11, bold: true, color: Kit.ink, height: 1)),
        ]),
      ),
    );
  }
}

class _ArrowClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width - 12, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(s.width - 12, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ---------------------------------------------------------------- the gear rack

/// Where the rope hangs at [x]: a shallow curve across the rack.
double _ropeY(double x, double w) {
  final t = ((x + 10) / (w + 20)).clamp(0.0, 1.0);
  return 22 + 72 * t * (1 - t);
}

class _RopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final rope = Path()
      ..moveTo(-10, 22)
      ..quadraticBezierTo(w / 2, 58, w + 10, 22);
    canvas.drawPath(
        rope.shift(const Offset(0, 4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..color = rgba(0, 0, 0, 0.3));
    canvas.drawPath(
        rope,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..color = Kit.rope);
    // the twist of the rope: short dashes, 3 on 7
    final twist = Path();
    for (final m in rope.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        twist.addPath(m.extractPath(d, d + 3), Offset.zero);
      }
    }
    canvas.drawPath(
        twist,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Kit.ropeTwist);
  }

  @override
  bool shouldRepaint(covariant _RopePainter oldDelegate) => false;
}

/// A rope sling across the bottom of the screen with things hanging from it
/// on carabiners: the left hand's strength, Undo, what is going on, Look,
/// and the right hand's strength.
class _Rack extends StatelessWidget {
  const _Rack({required this.game, required this.wide, required this.keys, required this.onTap});
  final Game game;
  final bool wide, keys;
  final void Function(VoidCallback f) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, mid = w / 2, gap = wide ? 120.0 : 90.0;
      Widget at(double x, Widget child, {double width = 64}) =>
          Positioned(left: x - width / 2, top: _ropeY(x, w) - 4, width: width, child: child);
      // each thing on the rack swings from its carabiner when the climber is jolted
      Widget swing(int seed, Widget child) => Swing(kicks: game.jolts, seed: seed, strength: 0.8, child: child);
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _RopePainter()))),
        at(math.max(46, w * 0.11), swing(1, _HandTag(game: game, hand: 0)), width: 72),
        at(
          mid - gap,
          swing(
            2,
            FrameSelect(
              game: game,
              select: (g) => g.canUndo && g.phase == Phase.climb,
              builder: (context, can) => _RackItem(
                label: 'UNDO',
                keyHint: keys ? 'U' : null,
                angle: 3,
                semanticLabel: 'Undo',
                onTap: can ? () => onTap(game.undo) : null,
                drawing: const _UnclipPainter(),
              ),
            ),
          ),
          width: keys ? 100 : 72,
        ),
        at(
          mid,
          swing(
            3,
            FrameSelect(
              game: game,
              select: (g) => (g.pillText, g.hangT > 0),
              builder: (context, p) => _StatusTag(text: p.$1, danger: p.$2),
            ),
          ),
          width: 150,
        ),
        at(
          mid + gap,
          swing(
            4,
            _RackItem(
              label: 'LOOK',
              keyHint: keys ? 'L' : null,
              angle: -2,
              on: game.look,
              semanticLabel: 'Look at the whole wall',
              onTap: () => onTap(() => game.setLook(!game.look)),
              drawing: const _MonocularPainter(),
            ),
          ),
          width: keys ? 100 : 72,
        ),
        at(math.min(w - 46, w * 0.89), swing(5, _HandTag(game: game, hand: 1)), width: 72),
      ]);
    });
  }
}

/// A teal carabiner, 16 by 26.
class _CarabinerPainter extends CustomPainter {
  const _CarabinerPainter({this.open = false});
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Kit.teal;
    final path = Path()
      ..moveTo(2, 6)
      ..quadraticBezierTo(2, 1, 7, 1)
      ..lineTo(9, 1)
      ..quadraticBezierTo(14, 1, 14, 8)
      ..lineTo(14, 19)
      ..quadraticBezierTo(14, 25, 8, 25)
      ..lineTo(7, 25)
      ..quadraticBezierTo(2, 25, 2, 21);
    canvas.drawPath(path, p);
    // the gate
    if (open) {
      canvas.drawLine(const Offset(2, 21), const Offset(-4, 9), p..strokeWidth = 2.4);
    } else {
      canvas.drawLine(const Offset(2, 21), const Offset(2, 6), p..strokeWidth = 2.4);
    }
  }

  @override
  bool shouldRepaint(covariant _CarabinerPainter o) => o.open != open;
}

/// Undo: a carabiner unclipped, its gate open, and an arrow going back.
class _UnclipPainter extends CustomPainter {
  const _UnclipPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 - 8, 6);
    const _CarabinerPainter(open: true).paint(canvas, const Size(16, 26));
    canvas.restore();
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Kit.blazeWhite;
    final cx = size.width / 2;
    canvas.drawPath(
        Path()
          ..moveTo(cx + 12, 40)
          ..quadraticBezierTo(cx + 10, 30, cx - 6, 32),
        arrow);
    canvas.drawPath(
        Path()
          ..moveTo(cx - 1, 27)
          ..lineTo(cx - 7, 32)
          ..lineTo(cx - 1, 37),
        arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Look: a small monocular.
class _MonocularPainter extends CustomPainter {
  const _MonocularPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final body = Path()
      ..moveTo(cx - 9, 8)
      ..lineTo(cx + 9, 8)
      ..lineTo(cx + 8, 38)
      ..quadraticBezierTo(cx, 42, cx - 8, 38)
      ..close();
    canvas.drawPath(body.shift(const Offset(0, 3)), Paint()..color = rgba(0, 0, 0, 0.3));
    canvas.drawPath(body, Paint()..color = Kit.teal);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 11, 3, 22, 8), const Radius.circular(3)), Paint()..color = Kit.chalk);
    canvas.drawRect(Rect.fromLTWH(cx - 8, 20, 16, 5), Paint()..color = rgba(0, 0, 0, 0.25));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Something on the rack you can tap: a carabiner, a drawing and a paper
/// tag with its name. The whole hanging shape takes the tap.
class _RackItem extends StatelessWidget {
  const _RackItem({required this.label, required this.onTap, required this.drawing, this.keyHint, this.angle = 0, this.on = false, this.semanticLabel});
  final String label;
  final VoidCallback? onTap;
  final CustomPainter drawing;
  final String? keyHint, semanticLabel;
  final double angle;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedOpacity(
            opacity: disabled ? 0.45 : 1,
            duration: const Duration(milliseconds: 180),
            child: PressScale(
              child: SizedBox(
                height: 104,
                child: Column(children: [
                  const SizedBox(width: 16, height: 26, child: CustomPaint(painter: _CarabinerPainter())),
                  SizedBox(width: 56, height: 44, child: CustomPaint(painter: drawing)),
                  Transform.rotate(
                    angle: angle * math.pi / 180,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      color: on ? Kit.webbing : Kit.paper,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(label, style: FbTxt.typed(14, bold: true, color: Kit.ink, height: 1.1)),
                        if (keyHint case final k?) ...[const SizedBox(width: 5), KeyHint(k, color: Kit.ink)],
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hand's strength on a paper tag at one end of the rack: "L 72". When
/// the hand is weak and still holding on, the tag turns red and pulses.
class _HandTag extends StatelessWidget {
  const _HandTag({required this.game, required this.hand});
  final Game game;
  final int hand;

  @override
  Widget build(BuildContext context) {
    return FrameSelect(
      game: game,
      select: (g) => (g.grip[hand].round(), g.phase == Phase.climb && g.limbs.length == 4 && g.limbs[hand].h != null),
      builder: (context, v) => _HandTagBody(value: v.$1, holding: v.$2, hand: hand),
    );
  }
}

class _HandTagBody extends StatefulWidget {
  const _HandTagBody({required this.value, required this.holding, required this.hand});
  final int value, hand;
  final bool holding;

  @override
  State<_HandTagBody> createState() => _HandTagBodyState();
}

class _HandTagBodyState extends State<_HandTagBody> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  bool get _low => widget.holding && widget.value < 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _HandTagBody old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = _low && !MediaQuery.disableAnimationsOf(context);
    if (run && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!run && _pulse.isAnimating) {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value, left = widget.hand == 0, label = left ? 'Left' : 'Right';
    return IgnorePointer(
      child: Semantics(
        label: '$label hand strength $v',
        excludeSemantics: true,
        child: Column(children: [
          const SizedBox(width: 16, height: 26, child: CustomPaint(painter: _CarabinerPainter())),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.rotate(
              angle: (left ? -4 : 4) * math.pi / 180,
              child: Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _low ? Color.lerp(Kit.low, Kit.paper, _pulse.value * 0.6) : Kit.paper,
                  boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.3), offset: const Offset(0, 4))],
                ),
                child: child,
              ),
            ),
            child: Column(children: [
              Text('${left ? 'L' : 'R'} $v', style: FbTxt.label(26, color: Kit.ink).copyWith(height: 1)),
              const SizedBox(height: 3),
              // the grip as a pencil bar that runs down and fills up smoothly
              TweenAnimationBuilder<double>(
                tween: Tween(end: v / 100),
                duration: Duration(milliseconds: moving(context) ? 260 : 0),
                curve: Curves.easeOutCubic,
                builder: (context, f, _) => SizedBox(width: 46, height: 5, child: CustomPaint(painter: _GripBarPainter(f))),
              ),
              const SizedBox(height: 2),
              Text(label.toUpperCase(), style: FbTxt.typed(10, bold: true, color: Kit.ink, height: 1.2)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// How much grip a hand has left, 0 to 1: a box drawn in pencil, filled in
/// graphite, blaze red once the hand is about to slip.
class _GripBarPainter extends CustomPainter {
  _GripBarPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = rgba(26, 29, 36, 0.12));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * f.clamp(0.0, 1.0), size.height), Paint()..color = f < 0.3 ? Kit.blaze : Kit.graphite);
    canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Kit.ink.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _GripBarPainter o) => o.f != f;
}

/// What is going on ("Resting", "Grab a hold!"), on a paper tag hanging in
/// the middle of the rack; typed (it types out), blaze red when it is urgent.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.text, required this.danger});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final on = text.isNotEmpty;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: Duration(milliseconds: on ? 160 : 300),
        child: AnimatedScale(
          scale: on ? 1 : 0.9,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Column(children: [
            const SizedBox(width: 16, height: 26, child: CustomPaint(painter: _CarabinerPainter())),
            const SizedBox(height: 2),
            Transform.rotate(
              angle: -2 * math.pi / 180,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: danger ? Kit.blaze : Kit.paper,
                  boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.3), offset: const Offset(0, 4))],
                ),
                child: TypeIn(on ? text.toUpperCase() : ' ',
                    perLetter: const Duration(milliseconds: 18),
                    textAlign: TextAlign.center,
                    style: FbTxt.typed(13, bold: true, color: danger ? Kit.blazeWhite : Kit.ink, height: 1.15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A short message: a scrap that slides down under the top edge, typed
/// bold; blaze red for bad news.
class GameToast extends StatelessWidget {
  const GameToast({super.key, required this.toast});
  final (String, ToastKind, double)? toast;

  @override
  Widget build(BuildContext context) {
    final t = toast;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.5), end: Offset.zero).animate(a),
          // put down a little turned, it settles straight
          child: RotationTransition(turns: Tween(begin: -0.012, end: 0.0).animate(a), child: child),
        ),
      ),
      child: t == null
          ? const SizedBox.shrink()
          : PaperScrap(
              key: ValueKey(t),
              angle: t.$2 == ToastKind.warn ? 1.5 : -1.5,
              tape: false,
              rule: Rule.plain,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Text(
                t.$1,
                textAlign: TextAlign.center,
                style: FbTxt.typed(15, bold: true, height: 1.25, color: t.$2 == ToastKind.warn ? Kit.blaze : Kit.ink),
              ),
            ),
    );
  }
}

/// A tip: a taped scrap above the rack, in plain sentences.
class _TipCard extends StatelessWidget {
  const _TipCard({super.key, required this.game, required this.text});
  final Game game;
  final String text;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: math.min(math.max(0.0, w - 40), 440),
      child: Settle(
        turn: 2.5,
        drop: 8,
        child: PaperScrap(
          angle: 1,
          torn: false,
          tapeAt: 0.12,
          rule: Rule.ruled,
          cell: 24,
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text(text, style: Txt.body(16, color: Kit.ink, height: 1.35))),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: Kit.ink, size: 22),
                onPressed: game.hideTip,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
