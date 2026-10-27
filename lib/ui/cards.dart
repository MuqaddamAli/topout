import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// Dark screen behind a card, with the card in the middle.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: rgba(13, 15, 21, 0.86),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16 + pad.left, 20 + pad.top, 16 + pad.right, 24 + pad.bottom),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Pal.ink2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Pal.line, width: 1.5),
                boxShadow: [BoxShadow(color: rgba(0, 0, 0, 0.4), blurRadius: 50, offset: const Offset(0, 20))],
              ),
              child: child,
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
  const FallCard({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final d = game.fallCard;
    if (d == null) return const SizedBox.shrink();
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('YOU FELL', style: Txt.eyebrow()),
        _gap(),
        _title(context, d.endless ? '' : 'From ', d.value),
        _gap(),
        Text(d.why, style: Txt.body(17, height: 1.4)),
        _gap(),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 64,
            width: double.infinity,
            child: Semantics(
              label: 'Hand strength before the fall',
              child: CustomPaint(painter: TracePainter(d.trace, d.hand)),
            ),
          ),
          const SizedBox(height: 4),
          Text('HAND STRENGTH', style: Txt.eyebrow(spacing: 0.1)),
        ]),
        _gap(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Pal.ink3, borderRadius: BorderRadius.circular(12)),
          child: Text(d.fix, style: Txt.body(15, height: 1.4)),
        ),
        if (d.note != null) ...[
          _gap(),
          Text(d.note!,
              style: Txt.body(14,
                  weight: d.noteDim ? FontWeight.w400 : FontWeight.w700, color: d.noteDim ? Pal.chalkDim : Pal.good)),
        ],
        _gap(),
        _buttons([
          GameButton(label: d.retryLabel, primary: true, minHeight: 52, onTap: () => _tap(game.retry)),
          if (d.showRestart) GameButton(label: 'Start over', minHeight: 52, onTap: () => _tap(game.restart)),
          GameButton(label: 'Routes', minHeight: 52, onTap: () => _tap(game.showMenu)),
        ]),
      ]),
    );
  }
}

class TopCard extends StatelessWidget {
  const TopCard({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final d = game.topCard;
    if (d == null) return const SizedBox.shrink();
    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Pal.ink3, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: Txt.eyebrow(spacing: 0.1)),
              const SizedBox(height: 4),
              Text(value, style: Txt.mono(22)),
            ]),
          ),
        );
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(d.routeName.toUpperCase(), style: Txt.eyebrow()),
        _gap(),
        _title(context, 'You made ', 'it'),
        _gap(),
        Row(children: [
          stat('Time', d.time),
          const SizedBox(width: 8),
          stat('Moves', '${d.moves}'),
          const SizedBox(width: 8),
          stat('Falls', '${d.falls}'),
        ]),
        _gap(),
        Text(d.note,
            style: Txt.body(14, weight: d.noteDim ? FontWeight.w400 : FontWeight.w700, color: d.noteDim ? Pal.chalkDim : Pal.good)),
        _gap(),
        _buttons([
          GameButton(label: d.nextLabel, primary: true, minHeight: 52, onTap: () => _tap(game.nextRoute)),
          GameButton(label: 'Again', minHeight: 52, onTap: () => _tap(game.restart)),
          GameButton(label: 'Routes', minHeight: 52, onTap: () => _tap(game.showMenu)),
        ]),
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
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text((game.route?.name ?? '').toUpperCase(), style: Txt.eyebrow()),
        _gap(),
        _title(context, 'Paused', ''),
        _gap(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          GameToggle(label: 'Music', value: game.audio.musicOn, onChanged: game.setMusic),
          GameToggle(label: 'Sounds', value: game.audio.sfxOn, onChanged: game.setSfx),
        ]),
        _gap(),
        _buttons([
          GameButton(label: 'Resume', primary: true, minHeight: 52, onTap: () => _tap(game.resume)),
          GameButton(label: 'Start over', minHeight: 52, onTap: () => _tap(game.restart)),
          GameButton(label: 'Routes', minHeight: 52, onTap: () => _tap(game.showMenu)),
        ]),
      ]),
    );
  }
}
