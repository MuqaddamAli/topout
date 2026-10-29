import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/chalk.dart';
import '../game/core.dart';
import '../game/field_book.dart';
import '../game/game.dart';
import 'climbers.dart';
import 'kit.dart';
import 'widgets.dart';

/// Title screen: a poster at the top (TOPOUT between the sky and the
/// mountains, drawn by the scene, and the climber on the summit), then a
/// sheet of the field book that scrolls up over it: who climbs, the routes,
/// the mode and sound, how to play, and your climbing log.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final wide = size.width >= 700;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: pad.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the poster shows through here
        SizedBox(height: math.min(size.height * (wide ? 0.5 : 0.46), wide ? 460 : 400)),
        Stagger(
          index: 0,
          step: 90,
          lift: 24,
          child: CustomPaint(
            painter: PaperPainter(color: Kit.paper, cell: wide ? 24 : 16, lineColor: Kit.grid, raggedTop: true, shadow: 0, seed: 3),
            child: Padding(
              padding: EdgeInsets.fromLTRB(math.max(18, pad.left + 14), 24, math.max(18, pad.right + 14), 32),
              child: Surface(
                paper: true,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: _Book(game: game, wide: wide),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Book extends StatelessWidget {
  const _Book({required this.game, required this.wide});
  final Game game;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    var i = 1;
    Widget section(Widget child) => Stagger(index: i++, step: 70, lift: 12, child: child);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      section(Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BUILD 0.5', style: FbTxt.typed(12, bold: true, color: Kit.graphite)),
            const SizedBox(height: 4),
            Text('Climb one hand or foot at a time.', style: Txt.body(18, color: Kit.ink, height: 1.35)),
          ]),
        ),
        if (wide) _playOnline(),
      ])),
      if (!wide) ...[const SizedBox(height: 4), section(_playOnline())],
      const SizedBox(height: 22),
      section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHead(number: 1, title: 'Climber'),
        const SizedBox(height: 12),
        ClimberPicker(game: game),
      ])),
      const SizedBox(height: 30),
      section(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHead(number: 2, title: 'Routes'),
        const SizedBox(height: 12),
        _Routes(game: game),
      ])),
      const SizedBox(height: 30),
      section(_Grid(minWidth: 290, gap: 28, children: [
        _ModeSection(game: game),
        const _HowTo(),
        _Log(game: game),
      ])),
    ]);
  }

  Widget _playOnline() => IndexLine(
        label: 'Play online',
        icon: Icons.groups_rounded,
        onTap: () {
          game.audio.play(Sfx.tap);
          game.showOnline();
        },
      );
}

/// Lays children out in columns that are at least [minWidth] wide.
class _Grid extends StatelessWidget {
  const _Grid({required this.minWidth, required this.children, this.gap = 12});
  final double minWidth, gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + gap) / (minWidth + gap)).floor());
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final row = children.sublist(i, math.min(children.length, i + cols));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) SizedBox(width: gap),
              SizedBox(width: w, child: k < row.length ? row[k] : const SizedBox.shrink()),
            ],
          ]),
        ));
        if (i + cols < children.length) rows.add(SizedBox(height: gap));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

/// A route's grade: I, II, III, or D for the Daily Wall.
String _grade(ClimbRoute r) => r.endless ? 'D' : const ['', 'I', 'II', 'III'][r.level.clamp(0, 3)];

/// The routes as a topo with tabs: A, B and C for the easy, medium and hard
/// route and D for the Daily Wall. The card under the tabs has the picked
/// route's real numbers, and the webbing strap ropes you up.
class _Routes extends StatefulWidget {
  const _Routes({required this.game});
  final Game game;

  @override
  State<_Routes> createState() => _RoutesState();
}

class _RoutesState extends State<_Routes> {
  int _sel = 0;

  Game get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final routes = game.routes, sel = _sel.clamp(0, routes.length - 1), r = routes[sel];
    final letter = String.fromCharCode(65 + sel);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 640;
      final topo = SizedBox(
        height: wide ? 380 : 300,
        child: Semantics(
          label: 'Topo of ${r.name}',
          child: CachedPaint(cacheKey: 'topo-${r.id}-${r.date}', painter: TopoPainter(r)),
        ),
      );
      final card = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the tabs: the picked one is the card's colour, the others manila and lower
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var k = 0; k < routes.length; k++) ...[
              if (k > 0) const SizedBox(width: 4),
              _Tab(
                letter: String.fromCharCode(65 + k),
                grade: _grade(routes[k]),
                on: k == sel,
                label: routes[k].endless
                    ? '${routes[k].name}, ${routes[k].date}'
                    : '${routes[k].name}, ${const ['', 'Easy', 'Medium', 'Hard'][routes[k].level.clamp(0, 3)]}, ${(routes[k].topY / unitsPerMetre).toStringAsFixed(1)} metres',
                onTap: () {
                  game.audio.play(Sfx.tap);
                  setState(() => _sel = k);
                },
              ),
            ],
          ]),
        ),
        _RouteCard(game: game, route: r),
        const SizedBox(height: 14),
        GameButton(
          label: 'Rope up',
          extra: 'route $letter',
          primary: true,
          semanticLabel: 'Climb ${r.name}',
          onTap: () {
            game.audio.play(Sfx.tap);
            game.startRoute(r);
          },
        ),
      ]);
      if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [topo, const SizedBox(height: 10), card]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: topo),
        const SizedBox(width: 24),
        Expanded(flex: 6, child: Padding(padding: const EdgeInsets.only(top: 30), child: card)),
      ]);
    });
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.letter, required this.grade, required this.on, required this.label, required this.onTap});
  final String letter, grade, label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.only(top: on ? 0 : 4),
          constraints: const BoxConstraints(minWidth: 64, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? Kit.card : Kit.manila,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(letter, style: FbTxt.label(22, color: Kit.ink)),
            const SizedBox(width: 6),
            Text(grade, style: FbTxt.typed(13, bold: true, color: Kit.ink, height: 1)),
          ]),
        ),
      ),
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
    final rows = <(String, String)>[];
    if (r.endless) {
      final all = game.bestEverDaily();
      rows
        ..add(('Today', hb > 0 ? '${hb.toStringAsFixed(1)} m' : 'not tried'))
        ..add(('Best ever', all > 0 ? '${all.toStringAsFixed(1)} m' : '—'))
        ..add(('Wall of', r.date));
    } else {
      final who = game.bestClimber(r), nl = r.ledgeCount;
      rows
        ..add(('Height', '${(r.topY / unitsPerMetre).toStringAsFixed(1)} m'))
        ..add(('Ledges', '$nl'))
        ..add(('Best time', best != null ? '${fmtTime(best)}${who != null ? ' · ${who.name}' : ''}' : '—'))
        ..add(('Best height', hb > 0 ? '${hb.toStringAsFixed(1)} m' : '—'));
    }
    return IndexCard(
      headAt: 56,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 44,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(r.name.toUpperCase(), style: FbTxt.label(40)))),
            Transform.translate(
              offset: const Offset(0, -12),
              child: InkStamp(word: _grade(r), color: Kit.ink, size: 0.8, angle: 8, semanticLabel: 'Grade ${_grade(r)}'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(r.blurb, style: Txt.body(15, color: Kit.ink, height: 1.35)),
        const SizedBox(height: 6),
        for (final (label, value) in rows) LeaderRow(label: label, value: Text(value), size: 13.5),
      ]),
    );
  }
}

class _ModeSection extends StatelessWidget {
  const _ModeSection({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHead(number: 3, title: 'Mode'),
      const SizedBox(height: 8),
      Row(children: [
        for (final m in Mode.values) ...[
          if (m != Mode.values.first) const SizedBox(width: 4),
          Expanded(
            child: GameChoice(
              label: m.label,
              on: game.mode == m,
              onTap: () {
                game.audio.play(Sfx.tap);
                game.setMode(m);
              },
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      Text(game.mode.note, style: Txt.body(15, color: Kit.ink, height: 1.4)),
      const SizedBox(height: 14),
      Text('SOUND', style: FbTxt.typed(12, bold: true)),
      Wrap(spacing: 8, runSpacing: 4, children: [
        GameToggle(label: 'Music', value: game.audio.musicOn, onChanged: game.setMusic),
        GameToggle(label: 'Sounds', value: game.audio.sfxOn, onChanged: game.setSfx),
      ]),
    ]);
  }
}

/// A chalk mark in pencil, for the legend in How to play.
class _MarkIcon extends StatelessWidget {
  const _MarkIcon(this.mark);
  final Mark mark;

  @override
  Widget build(BuildContext context) => SizedBox(width: 30, height: 26, child: CustomPaint(painter: _MarkPainter(mark)));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark);
  final Mark mark;

  @override
  void paint(Canvas canvas, Size size) => ChalkArt.stamp(canvas, mark, size.center(Offset.zero), 0.46, Kit.ink);

  @override
  bool shouldRepaint(covariant _MarkPainter o) => o.mark != mark;
}

class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    // also true in a desktop browser, where the keys work too
    final desktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final small = FbTxt.typed(12.5, bold: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHead(number: 4, title: 'How to play'),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.touch_app_outlined, size: 26, color: Kit.ink),
        const SizedBox(width: 12),
        Expanded(child: Text('Drag a hand or foot to a hold.', style: Txt.body(15, color: Kit.ink, height: 1.35))),
      ]),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 36),
        child: Wrap(spacing: 14, runSpacing: 6, children: [
          for (final (m, label) in const [(Mark.ring, 'good hold'), (Mark.brokenRing, 'poor hold'), (Mark.dots, 'jump'), (Mark.cross, 'no hold')])
            Row(mainAxisSize: MainAxisSize.min, children: [_MarkIcon(m), const SizedBox(width: 4), Text(label, style: small)]),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        const LampIcon(),
        const SizedBox(width: 10),
        Expanded(child: Text('Stand on a ledge to rest. The lamp saves your place.', style: Txt.body(15, color: Kit.ink, height: 1.35))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.ac_unit_rounded, size: 24, color: Kit.ink),
        const SizedBox(width: 12),
        Expanded(child: Text('Up high, snow makes holds slick until it brushes off.', style: Txt.body(15, color: Kit.ink, height: 1.35))),
      ]),
      if (desktop) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (k, what) in const [('U', 'undo'), ('L', 'look'), ('ESC', 'pause'), ('ENTER', 'go on')])
            Row(mainAxisSize: MainAxisSize.min, children: [KeyHint(k), const SizedBox(width: 5), Text(what, style: small)]),
        ]),
      ],
    ]);
  }
}

/// Your climbs so far, as lines in the log: the counts as tally marks.
class _Log extends StatelessWidget {
  const _Log({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final rec = game.records;
    final m = (rec.secs / 60).floor();
    final time = m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
    Widget count(int n) => n <= 20 ? TallyMarks(count: n, height: 18, label: '$n') : Text('$n', style: FbTxt.typed(15, bold: true));
    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 78, child: Text(label, style: FbTxt.typed(14, bold: true))),
            Flexible(child: value),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHead(number: 5, title: 'Your climbs'),
      const SizedBox(height: 10),
      line('TOPS', count(rec.tops)),
      line('METRES', Text(rec.metres.toStringAsFixed(0), style: FbTxt.typed(15))),
      // falls you stopped by catching a hold on the way down
      line('FALLS', Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        count(rec.falls),
        if (rec.catches > 0) Text('${rec.catches} caught', style: FbTxt.typed(13, color: Kit.graphite)),
      ])),
      line('TIME', Text(time, style: FbTxt.typed(15))),
    ]);
  }
}
