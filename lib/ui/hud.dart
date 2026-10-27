import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// The climbing screen: route name and height on top, grip gauges and the
/// Undo and Look buttons at the bottom, plus tips and short messages.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final shade = rgba(13, 15, 21, 0.74);
    return AnimatedBuilder(
      animation: game.frameTick,
      builder: (context, _) {
        final r = game.route;
        if (r == null) return const SizedBox.shrink();
        game.refreshTicks();
        final h = game.climberHeight();
        final span = game.progSpan();
        final best = game.bestHeight(r);
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
                              '${r.endless ? 'Daily · ' : ''}${game.mode.label}'.toUpperCase(),
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
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                        Text(h.toStringAsFixed(1), style: Txt.mono(28)),
                        const SizedBox(width: 3),
                        Text('m', style: Txt.mono(13, color: Pal.chalkDim)),
                      ]),
                      const SizedBox(height: 3),
                      Text(fmtTime(game.time), style: Txt.mono(11, color: Pal.chalkDim)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                IgnorePointer(child: _Progress(game: game, fill: (h / span).clamp(0.0, 1.0), best: best, span: span)),
              ]),
            ),
          ),
          // ---------------- message at the top
          if (game.toastVisible)
            Positioned(
              left: 14,
              right: 14,
              top: pad.top + 84,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: rgba(17, 20, 27, 0.9),
                      border: Border.all(color: Pal.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      game.toastText ?? '',
                      textAlign: TextAlign.center,
                      style: Txt.body(14,
                          weight: FontWeight.w700,
                          height: 1.25,
                          color: game.toastKind == ToastKind.warn
                              ? Pal.weak
                              : (game.toastKind == ToastKind.ok ? Pal.good : Pal.chalk)),
                    ),
                  ),
                ),
              ),
            ),
          // ---------------- back to the climber after looking around
          if (game.showRecenter)
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 122,
              child: Center(
                child: GameButton(label: 'Back', minHeight: 40, radius: 999, onTap: () => _tap(game.recenter)),
              ),
            ),
          // ---------------- tip card
          if (game.tipText != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 118,
              child: Center(child: _TipCard(game: game)),
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
                Expanded(child: Align(alignment: Alignment.bottomLeft, child: _Gauge(value: game.grip[0], label: 'Left'))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  _Pill(text: game.pillText, danger: game.hangT > 0),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    GameButton(
                      label: 'Undo',
                      icon: Icons.undo_rounded,
                      compact: true,
                      width: 70,
                      minHeight: 60,
                      radius: 18,
                      onTap: game.canUndo && game.phase == Phase.climb ? () => _tap(game.undo) : null,
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
                Expanded(child: Align(alignment: Alignment.bottomRight, child: _Gauge(value: game.grip[1], label: 'Right'))),
              ]),
            ),
          ),
        ]);
      },
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
            child: DecoratedBox(decoration: BoxDecoration(color: Pal.signal, borderRadius: BorderRadius.circular(2))),
          ),
          for (final t in game.ticks)
            Positioned(
              left: w * t.pos - 1,
              top: 2,
              width: 2,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: game.lit.contains(t.hold) ? Pal.lamp : rgba(242, 237, 228, 0.55),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
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

class _Gauge extends StatelessWidget {
  const _Gauge({required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        label: '$label hand strength ${value.round()}',
        excludeSemantics: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: GaugePainter(value),
              child: Center(child: Text('${value.round()}', style: Txt.mono(17))),
            ),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: Txt.eyebrow(size: 10, spacing: 0.12)),
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
    return IgnorePointer(
      child: Opacity(
        opacity: text.isEmpty ? 0 : 1,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: danger ? rgba(255, 90, 90, 0.16) : rgba(127, 220, 149, 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text.isEmpty ? ' ' : text.toUpperCase(),
              style: Txt.eyebrow(spacing: 0.1, color: danger ? Pal.bad : Pal.good)),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: (w - 28).clamp(0.0, 440.0),
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 13),
      decoration: BoxDecoration(
        color: rgba(242, 237, 228, 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.4), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Text(game.tipText ?? '', style: Txt.body(16, color: Pal.ink, height: 1.35))),
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
