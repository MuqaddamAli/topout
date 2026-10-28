import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/game.dart';
import '../game/palette.dart';
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

/// The climbing screen: route name and height on top, grip gauges and the
/// Undo and Look buttons at the bottom, plus tips and short messages.
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
    final pad = MediaQuery.paddingOf(context);
    final shade = rgba(13, 15, 21, 0.74);
    return Stack(children: [
      // ---------------- top bar
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: _Bar(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [shade, shade, shade.withAlpha(0)],
            stops: const [0, 0.55, 1],
          ),
          padding: EdgeInsets.fromLTRB(pad.left + 10, pad.top + 8, pad.right + 10, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              GameButton(
                label: '',
                icon: Icons.pause_rounded,
                width: 46,
                minHeight: 46,
                radius: 13,
                semanticLabel: 'Pause',
                onTap: () => _tap(game.pause),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IgnorePointer(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.display(21, spacing: 0.03).copyWith(height: 1)),
                    const SizedBox(height: 5),
                    Row(children: [
                      if (!r.endless) ...[Pips(level: r.level), const SizedBox(width: 8)],
                      Flexible(
                        child: Text(
                          '${r.endless ? 'Daily · ' : ''}${game.mode.label} · ${game.climber.name}'.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.eyebrow(spacing: 0.08),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              IgnorePointer(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  FrameSelect(
                    game: game,
                    select: (g) => g.climberHeight().toStringAsFixed(1),
                    builder: (context, h) => Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(h, style: Txt.mono(28)),
                        const SizedBox(width: 3),
                        Text('m', style: Txt.mono(13, color: Pal.chalkDim)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  FrameSelect(
                    game: game,
                    select: (g) => fmtTime(g.time),
                    builder: (context, t) => Text(t, style: Txt.mono(11, color: Pal.chalkDim)),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            IgnorePointer(
              child: FrameSelect(
                game: game,
                select: (g) {
                  g.refreshTicks();
                  final span = g.progSpan();
                  return (
                    fill: ((g.climberHeight() / span).clamp(0.0, 1.0) * 500).round() / 500,
                    best: g.bestHeight(r),
                    span: span,
                    lit: g.lit.length,
                    ticks: g.ticks.length,
                  );
                },
                builder: (context, v) => _Progress(game: game, fill: v.fill, best: v.best, span: v.span),
              ),
            ),
          ]),
        ),
      ),
      // ---------------- message at the top
      Positioned(
        left: 14,
        right: 14,
        top: pad.top + 84,
        child: IgnorePointer(
          child: FrameSelect(
            game: game,
            select: (g) => g.toastVisible ? (g.toastText ?? '', g.toastKind, g.toastUntil) : null,
            builder: (context, t) => Center(child: GameToast(toast: t)),
          ),
        ),
      ),
      // ---------------- everyone's height, in an online climb
      if (game.onlineClimb)
        Positioned(
          left: pad.left + 10,
          top: pad.top + 124,
          child: IgnorePointer(child: _Heights(game: game)),
        ),
      // ---------------- online: the creator, at the top, can end the climb for everyone
      if (game.onlineClimb)
        Positioned(
          right: pad.right + 12,
          top: pad.top + 124,
          child: FrameSelect(
            game: game,
            select: (g) => g.toppedOut && g.online.isHost && !(g.online.room?.ended ?? true),
            builder: (context, show) => _Appear(
              visible: show,
              child: GameButton(label: 'End climb', minHeight: 40, radius: 999, onTap: show ? () => _tap(game.endClimb) : null),
            ),
          ),
        ),
      // ---------------- emotes, while you stand with others
      if (game.social)
        Positioned(
          right: pad.right + 12,
          bottom: pad.bottom + 132,
          child: FrameSelect(
            game: game,
            select: (g) => (g.canEmote, g.clock >= g.nextEmoteAt, g.emote),
            builder: (context, v) => _Appear(
              visible: v.$1,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final (e, icon) in const [
                  (Emote.cheer, Icons.celebration_rounded),
                  (Emote.taunt, Icons.waving_hand_rounded),
                  (Emote.aura, Icons.self_improvement_rounded),
                ]) ...[
                  GameButton(
                    label: e.label,
                    icon: icon,
                    compact: true,
                    width: 64,
                    minHeight: 50,
                    radius: 16,
                    on: v.$3 == e,
                    semanticLabel: '${e.label} (key ${e.index + 1})',
                    onTap: v.$1 && v.$2 ? () => _tap(() => game.doEmote(e)) : null,
                  ),
                  const SizedBox(height: 6),
                ],
              ]),
            ),
          ),
        ),
      // ---------------- back to the climber after looking around
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + 122,
        child: Center(
          child: _Appear(
            visible: game.showRecenter,
            child: GameButton(label: 'Back', minHeight: 40, radius: 999, onTap: () => _tap(game.recenter)),
          ),
        ),
      ),
      // ---------------- tip card
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + 118,
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
      // ---------------- bottom bar
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _Bar(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [shade.withAlpha(0), shade, shade],
            stops: const [0, 0.5, 1],
          ),
          padding: EdgeInsets.fromLTRB(pad.left + 12, 34, pad.right + 12, pad.bottom + 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Align(alignment: Alignment.bottomLeft, child: _GaugeFor(game: game, hand: 0, label: 'Left'))),
            Column(mainAxisSize: MainAxisSize.min, children: [
              FrameSelect(
                game: game,
                select: (g) => (g.pillText, g.hangT > 0),
                builder: (context, p) => _Pill(text: p.$1, danger: p.$2),
              ),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FrameSelect(
                  game: game,
                  select: (g) => g.canUndo && g.phase == Phase.climb,
                  builder: (context, can) => GameButton(
                    label: 'Undo',
                    icon: Icons.undo_rounded,
                    compact: true,
                    width: 70,
                    minHeight: 60,
                    radius: 18,
                    onTap: can ? () => _tap(game.undo) : null,
                  ),
                ),
                const SizedBox(width: 10),
                GameButton(
                  label: 'Look',
                  icon: Icons.visibility_outlined,
                  compact: true,
                  width: 70,
                  minHeight: 60,
                  radius: 18,
                  on: game.look,
                  semanticLabel: 'Look at the whole wall',
                  onTap: () => _tap(() => game.setLook(!game.look)),
                ),
              ]),
            ]),
            Expanded(child: Align(alignment: Alignment.bottomRight, child: _GaugeFor(game: game, hand: 1, label: 'Right'))),
          ]),
        ),
      ),
    ]);
  }
}

/// Everyone in the room, finished first and then highest first, small in a
/// corner. It rebuilds only when a shown number changes.
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
        return Container(
          width: 156,
          padding: const EdgeInsets.fromLTRB(9, 7, 10, 7),
          decoration: BoxDecoration(color: rgba(13, 15, 21, 0.62), borderRadius: BorderRadius.circular(12)),
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
    return Semantics(
      label: '$place, ${s.you ? 'you' : s.name}, ${f != null ? 'topped out in $value' : value}',
      excludeSemantics: true,
      child: Opacity(
        opacity: s.connected ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            SizedBox(width: 15, child: Text('$place', style: Txt.mono(11, color: Pal.chalkDim))),
            Expanded(
              child: Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.body(12.5, weight: FontWeight.w700, color: s.you ? Pal.signal : Pal.chalk, height: 1.2)),
            ),
            const SizedBox(width: 6),
            if (f != null) ...[Icon(Icons.flag_rounded, size: 12, color: Pal.good), const SizedBox(width: 3)],
            Text(value, style: Txt.mono(11.5, color: f != null ? Pal.good : Pal.chalk)),
          ]),
        ),
      ),
    );
  }
}

/// A strip with a soft gradient behind it. Touches on the gradient go
/// through to the wall; only the buttons on it catch them.
class _Bar extends StatelessWidget {
  const _Bar({required this.gradient, required this.padding, required this.child});
  final Gradient gradient;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)))),
      Padding(padding: padding, child: child),
    ]);
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

class _Progress extends StatelessWidget {
  const _Progress({required this.game, required this.fill, required this.best, required this.span});
  final Game game;
  final double fill, best, span;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            height: 4,
            child: DecoratedBox(
                decoration: BoxDecoration(color: rgba(242, 237, 228, 0.14), borderRadius: BorderRadius.circular(2))),
          ),
          Positioned(
            left: 0,
            top: 4,
            height: 4,
            width: w * fill,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Pal.signal, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          for (final t in game.ticks)
            Positioned(
              left: w * t.pos - 1,
              top: 2,
              width: 2,
              height: 8,
              child: _Tick(lit: game.tickLit(t)),
            ),
          if (best > 0.5 && best < span)
            Positioned(
              left: w * best / span - 1.5,
              top: 0,
              width: 3,
              height: 12,
              child: DecoratedBox(decoration: BoxDecoration(color: Pal.jump, borderRadius: BorderRadius.circular(2))),
            ),
        ]);
      }),
    );
  }
}

/// A ledge mark on the progress bar. It grows a halo when its lamp is lit.
class _Tick extends StatelessWidget {
  const _Tick({required this.lit});
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: lit ? Pal.lamp : rgba(242, 237, 228, 0.55),
        borderRadius: BorderRadius.circular(1),
        // a flat halo (spread, no blur): blurs are redrawn every frame on the web
        boxShadow: [BoxShadow(color: Pal.lamp.withAlpha(lit ? 90 : 0), spreadRadius: lit ? 1.5 : 0)],
      ),
    );
  }
}

/// A short message that slides in at the top.
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
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(a),
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
        ),
      ),
      child: t == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(t),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: rgba(17, 20, 27, 0.9),
                border: Border.all(
                    color: t.$2 == ToastKind.ok
                        ? Pal.good.withAlpha(90)
                        : (t.$2 == ToastKind.warn ? Pal.weak.withAlpha(80) : Pal.line)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                t.$1,
                textAlign: TextAlign.center,
                style: Txt.body(14,
                    weight: FontWeight.w700,
                    height: 1.25,
                    color: t.$2 == ToastKind.warn ? Pal.weak : (t.$2 == ToastKind.ok ? Pal.good : Pal.chalk)),
              ),
            ),
    );
  }
}

/// The grip gauge of one hand; it rebuilds only when the shown number changes.
class _GaugeFor extends StatelessWidget {
  const _GaugeFor({required this.game, required this.hand, required this.label});
  final Game game;
  final int hand;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FrameSelect(
      game: game,
      select: (g) => (g.grip[hand].round(), g.phase == Phase.climb && g.limbs.length == 4 && g.limbs[hand].h != null),
      builder: (context, v) => _Gauge(value: v.$1, holding: v.$2, label: label),
    );
  }
}

class _Gauge extends StatefulWidget {
  const _Gauge({required this.value, required this.holding, required this.label});
  final int value;
  final bool holding;
  final String label;

  @override
  State<_Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<_Gauge> with SingleTickerProviderStateMixin {
  /// A slow pulse while the hand is weak and still holding on.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  bool get _low => widget.holding && widget.value < 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Gauge old) {
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
    final v = widget.value;
    return IgnorePointer(
      child: Semantics(
        label: '${widget.label} hand strength $v',
        excludeSemantics: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 60,
            height: 60,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) =>
                  CustomPaint(painter: GaugePainter(v.toDouble(), glow: _pulse.value), child: child),
              child: Center(child: Text('$v', style: Txt.mono(17))),
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.label.toUpperCase(), style: Txt.eyebrow(size: 10, spacing: 0.12)),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.danger});
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: danger ? rgba(255, 90, 90, 0.16) : rgba(127, 220, 149, 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(on ? text.toUpperCase() : ' ',
                style: Txt.eyebrow(spacing: 0.1, color: danger ? Pal.bad : Pal.good)),
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({super.key, required this.game, required this.text});
  final Game game;
  final String text;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: math.min(math.max(0.0, w - 28), 440),
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 13),
      decoration: BoxDecoration(
        color: rgba(242, 237, 228, 0.96),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(text, style: Txt.body(16, color: Pal.ink, height: 1.35))),
        SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Close',
            icon: Icon(Icons.close_rounded, color: Pal.ink, size: 22),
            onPressed: game.hideTip,
          ),
        ),
      ]),
    );
  }
}
