import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// Dark screen behind a card, with the card in the middle. The card rises
/// into place when it appears.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: rgba(13, 15, 21, 0.86),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16 + pad.left, 20 + pad.top, 16 + pad.right, 24 + pad.bottom),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: still ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Transform.translate(
                offset: Offset(0, (1 - t) * 22),
                child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Pal.ink2,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Pal.line, width: 1.5),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _gap() => const SizedBox(height: 14);

Widget _title(BuildContext context, String plain, String accent) {
  final size = (MediaQuery.sizeOf(context).width * 0.12).clamp(40.0, 52.0);
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: plain.toUpperCase()),
      TextSpan(text: accent.toUpperCase(), style: TextStyle(color: Pal.signal)),
    ]),
    style: Txt.display(size, weight: FontWeight.w900, spacing: 0),
  );
}

/// Buttons in rows that wrap; each is at least 120 wide and they share the space.
Widget _buttons(List<Widget> buttons) {
  return LayoutBuilder(builder: (context, c) {
    const gap = 8.0;
    final perRow = math.max(1, (c.maxWidth + gap) ~/ (120 + gap));
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += perRow) {
      final row = buttons.sublist(i, math.min(i + perRow, buttons.length));
      rows.add(Row(children: [
        for (var k = 0; k < row.length; k++) ...[
          if (k > 0) const SizedBox(width: gap),
          Expanded(child: row[k]),
        ],
      ]));
      if (i + perRow < buttons.length) rows.add(const SizedBox(height: gap));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  });
}

class FallCard extends StatelessWidget {
  const FallCard({super.key, required this.game, required this.data});
  final Game game;

  /// What the card shows. It is kept here so the card can fade out after the game moves on.
  final FallCardData data;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    var i = 0;
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stagger(index: i++, child: Text('YOU FELL', style: Txt.eyebrow())),
        _gap(),
        Stagger(index: i++, child: _title(context, d.endless ? '' : 'From ', d.value)),
        _gap(),
        Stagger(index: i++, child: Text(d.why, style: Txt.body(17, height: 1.4))),
        _gap(),
        Stagger(
          index: i++,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 64,
              width: double.infinity,
              child: Semantics(
                label: 'Hand strength before the fall',
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 1100),
                  curve: const Interval(0.25, 1, curve: Curves.easeInOutCubic),
                  builder: (context, t, _) => CustomPaint(painter: TracePainter(d.trace, d.hand, progress: t)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('HAND STRENGTH', style: Txt.eyebrow(spacing: 0.1)),
          ]),
        ),
        _gap(),
        Stagger(
          index: i++,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Pal.ink3, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.lightbulb_outline_rounded, size: 18, color: Pal.lamp),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(d.fix, style: Txt.body(15, height: 1.4))),
            ]),
          ),
        ),
        if (d.note != null) ...[
          _gap(),
          Stagger(
            index: i++,
            child: Text(d.note!,
                style: Txt.body(14,
                    weight: d.noteDim ? FontWeight.w400 : FontWeight.w700, color: d.noteDim ? Pal.chalkDim : Pal.good)),
          ),
        ],
        _gap(),
        Stagger(
          index: i++,
          child: _buttons([
            GameButton(label: d.retryLabel, primary: true, minHeight: 52, onTap: () => _tap(game.retry)),
            if (d.showRestart) GameButton(label: 'Start over', minHeight: 52, onTap: () => _tap(game.restart)),
            GameButton(label: game.backLabel, minHeight: 52, onTap: () => _tap(game.goBack)),
          ]),
        ),
      ]),
    );
  }
}

class TopCard extends StatelessWidget {
  const TopCard({super.key, required this.game, required this.data});
  final Game game;
  final TopCardData data;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final still = MediaQuery.disableAnimationsOf(context);

    /// A number that counts up from zero when the card appears.
    Widget count(num to, String Function(double v) show) => TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? to.toDouble() : 0, end: to.toDouble()),
          duration: const Duration(milliseconds: 900),
          curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
          builder: (context, v, _) => Text(show(v), style: Txt.mono(22)),
        );
    Widget stat(String label, Widget value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Pal.ink3, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: Txt.eyebrow(spacing: 0.1)),
              const SizedBox(height: 4),
              value,
            ]),
          ),
        );
    var i = 0;
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stagger(index: i++, child: Text('${d.routeName} · ${d.climber}'.toUpperCase(), style: Txt.eyebrow())),
        _gap(),
        Stagger(index: i++, child: _title(context, 'You made ', 'it')),
        _gap(),
        Stagger(
          index: i++,
          child: Row(children: [
            stat('Time', count(d.seconds, fmtTime)),
            const SizedBox(width: 8),
            stat('Moves', count(d.moves, (v) => '${v.round()}')),
            const SizedBox(width: 8),
            stat('Falls', count(d.falls, (v) => '${v.round()}')),
          ]),
        ),
        _gap(),
        Stagger(
          index: i++,
          child: Row(children: [
            if (!d.noteDim) ...[Icon(Icons.emoji_events_rounded, size: 18, color: Pal.good), const SizedBox(width: 8)],
            Expanded(
              child: Text(d.note,
                  style: Txt.body(14,
                      weight: d.noteDim ? FontWeight.w400 : FontWeight.w700, color: d.noteDim ? Pal.chalkDim : Pal.good)),
            ),
          ]),
        ),
        _gap(),
        Stagger(
          index: i++,
          child: _buttons([
            // online, the room climbs one route: no next route
            if (!game.onlineClimb)
              GameButton(label: d.nextLabel, primary: true, minHeight: 52, onTap: () => _tap(game.nextRoute)),
            GameButton(label: 'Again', primary: game.onlineClimb, minHeight: 52, onTap: () => _tap(game.restart)),
            GameButton(label: game.backLabel, minHeight: 52, onTap: () => _tap(game.goBack)),
          ]),
        ),
      ]),
    );
  }
}

class PauseCard extends StatelessWidget {
  const PauseCard({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    var i = 0;
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stagger(
          index: i++,
          child: Text('${game.route?.name ?? ''} · ${game.climber.name}'.toUpperCase(), style: Txt.eyebrow()),
        ),
        _gap(),
        Stagger(index: i++, child: _title(context, 'Paused', '')),
        _gap(),
        Stagger(
          index: i++,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            GameToggle(label: 'Music', value: game.audio.musicOn, onChanged: game.setMusic),
            GameToggle(label: 'Sounds', value: game.audio.sfxOn, onChanged: game.setSfx),
          ]),
        ),
        _gap(),
        Stagger(
          index: i++,
          child: _buttons([
            GameButton(label: 'Resume', primary: true, minHeight: 52, onTap: () => _tap(game.resume)),
            GameButton(label: 'Start over', minHeight: 52, onTap: () => _tap(game.restart)),
            GameButton(label: game.backLabel, minHeight: 52, onTap: () => _tap(game.goBack)),
          ]),
        ),
      ]),
    );
  }
}
