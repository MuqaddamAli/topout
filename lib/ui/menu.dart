import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/core.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// Title screen: the climber on the summit, the routes, mode, sound,
/// how to play, and your climbing log.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final vh = size.height / 100;
    return Stack(children: [
      // The scene shows through at the top and fades to dark lower down.
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [rgba(13, 15, 21, 0), rgba(13, 15, 21, 0), rgba(13, 15, 21, 0.86), Pal.ink],
                stops: const [0, 0.34, 0.54, 0.8],
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(math.max(16, pad.left), pad.top + 20, math.max(16, pad.right), pad.bottom + 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: math.min(42 * vh, 380)),
                _Brand(width: size.width),
                const SizedBox(height: 22),
                Text('ROUTES', style: Txt.eyebrow()),
                const SizedBox(height: 10),
                _Grid(minWidth: 270, children: [for (final r in game.routes) _RouteCard(game: game, route: r)]),
                const SizedBox(height: 22),
                _Grid(minWidth: 280, children: [
                  _ModePanel(game: game),
                  const _HowToPanel(),
                  _LogPanel(game: game),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Lays children out in columns that are at least [minWidth] wide.
class _Grid extends StatelessWidget {
  const _Grid({required this.minWidth, required this.children});
  final double minWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + gap) / (minWidth + gap)).floor());
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final row = children.sublist(i, math.min(children.length, i + cols));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) const SizedBox(width: gap),
              SizedBox(width: w, child: k < row.length ? row[k] : const SizedBox.shrink()),
            ],
          ]),
        ));
        if (i + cols < children.length) rows.add(const SizedBox(height: gap));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final big = (width * 0.21).clamp(68.0, 150.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BUILD 0.4', style: Txt.eyebrow()),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'TOP'),
          TextSpan(text: 'OUT', style: TextStyle(color: Pal.signal)),
        ]),
        style: Txt.display(big, weight: FontWeight.w900, spacing: 0.01).copyWith(
          height: 0.8,
          shadows: [Shadow(color: rgba(10, 10, 20, 0.5), blurRadius: 30, offset: const Offset(0, 6))],
        ),
      ),
      const SizedBox(height: 8),
      Text('Climb one hand or foot at a time.', style: Txt.body(18, color: Pal.chalk.withAlpha(217), height: 1.4)),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});
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

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.game, required this.route});
  final Game game;
  final ClimbRoute route;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final best = game.bestTime(r), hb = game.bestHeight(r);
    final nl = r.ledgeCount;
    final String sub;
    final Color subColor;
    final List<String> facts;
    if (r.endless) {
      final all = game.bestEverDaily();
      sub = '${hb > 0 ? 'Today: ${hb.toStringAsFixed(1)} m' : 'Not tried today'}'
          '${all > hb ? ' · Best ever: ${all.toStringAsFixed(1)} m' : ''}';
      subColor = Pal.jump;
      facts = [r.date];
    } else {
      sub = best != null ? 'Best time ${fmtTime(best)}' : (hb > 0 ? 'Highest: ${hb.toStringAsFixed(1)} m' : 'Not climbed yet');
      subColor = best != null || hb > 0 ? Pal.good : Pal.chalkDim;
      facts = ['${(r.topY / unitsPerMetre).toStringAsFixed(1)} m', '$nl ledge${nl == 1 ? '' : 's'}'];
    }
    final level = const ['', 'Easy', 'Medium', 'Hard'][r.level.clamp(0, 3)];
    return Semantics(
      button: true,
      label: r.endless ? '${r.name}, ${r.date}' : '${r.name}, $level, ${(r.topY / unitsPerMetre).toStringAsFixed(1)} metres',
      excludeSemantics: true,
      child: Material(
        color: Pal.ink2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: r.endless ? Pal.jump.withAlpha(128) : Pal.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            game.audio.play(Sfx.tap);
            game.startRoute(r);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 72, height: 128, child: CustomPaint(painter: TopoPainter(r))),
              const SizedBox(width: 14),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 128),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(r.name.toUpperCase(), style: Txt.display(27))),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: r.endless ? const DailyBadge() : Pips(level: r.level),
                      ),
                    ]),
                    const SizedBox(height: 7),
                    Text(r.blurb, style: Txt.body(15, color: Pal.chalkDim, height: 1.35)),
                    const SizedBox(height: 7),
                    Wrap(spacing: 12, runSpacing: 3, children: [
                      for (final f in facts) Text(f, style: Txt.mono(12, color: Pal.chalkDim)),
                    ]),
                    const SizedBox(height: 10),
                    Text(sub, style: Txt.body(13, color: subColor, height: 1.3)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return _Panel(title: 'Mode', children: [
      Row(children: [
        for (final m in Mode.values) ...[
          if (m != Mode.values.first) const SizedBox(width: 6),
          Expanded(child: _ModeChoice(game: game, mode: m)),
        ],
      ]),
      Text(game.mode.note, style: Txt.body(15, color: Pal.chalkDim, height: 1.4)),
      Text('SOUND', style: Txt.eyebrow(spacing: 0.14).copyWith(fontWeight: FontWeight.w700)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        GameToggle(label: 'Music', value: game.audio.musicOn, onChanged: game.setMusic),
        GameToggle(label: 'Sounds', value: game.audio.sfxOn, onChanged: game.setSfx),
      ]),
    ]);
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.game, required this.mode});
  final Game game;
  final Mode mode;

  @override
  Widget build(BuildContext context) {
    final on = game.mode == mode;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      label: mode.label,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: on ? Pal.signal : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: on ? BorderSide.none : BorderSide(color: Pal.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            game.audio.play(Sfx.tap);
            game.setMode(mode);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(mode.label,
                textAlign: TextAlign.center,
                style: Txt.body(14, weight: FontWeight.w700, color: on ? Pal.signalInk : Pal.chalk, height: 1.1)),
          ),
        ),
      ),
    );
  }
}

class _HowToPanel extends StatelessWidget {
  const _HowToPanel();

  @override
  Widget build(BuildContext context) {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return _Panel(title: 'How to play', children: [
      Row(children: [
        Icon(Icons.touch_app_outlined, size: 28, color: Pal.chalk),
        const SizedBox(width: 12),
        Expanded(child: Text('Drag a hand or foot to a hold.', style: Txt.body(15, height: 1.35))),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 40),
        child: Wrap(spacing: 16, runSpacing: 8, children: [
          RingChip(color: Pal.good, label: 'Good hold'),
          RingChip(color: Pal.weak, label: 'Hard hold'),
          RingChip(color: Pal.jump, label: 'Jump', dashed: true),
        ]),
      ),
      Row(children: [
        const LampIcon(),
        const SizedBox(width: 12),
        Expanded(child: Text('Stand on a ledge to rest. The lamp saves your place.', style: Txt.body(15, height: 1.35))),
      ]),
      if (desktop) Text('U undo · L look · Esc pause', style: Txt.body(13, color: Pal.chalkDim)),
    ]);
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final m = (game.logSecs / 60).floor();
    final time = m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
    final tiles = [
      ('Tops', '${game.logTops}'),
      ('Metres', game.logMetres.toStringAsFixed(0)),
      ('Falls', '${game.logFalls}'),
      ('Time', time),
    ];
    return _Panel(title: 'Your climbs', children: [
      for (var row = 0; row < 2; row++)
        Row(children: [
          for (var k = 0; k < 2; k++) ...[
            if (k > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Pal.ink3, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tiles[row * 2 + k].$1.toUpperCase(), style: Txt.eyebrow(spacing: 0.1)),
                  const SizedBox(height: 4),
                  Text(tiles[row * 2 + k].$2, style: Txt.mono(22)),
                ]),
              ),
            ),
          ],
        ]),
    ]);
  }
}
