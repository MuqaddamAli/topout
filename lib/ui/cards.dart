import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/core.dart' show Rng;
import '../game/field_book.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'hud.dart' show FrameSelect;
import 'kit.dart';
import 'widgets.dart';

/// The dark rock behind a card, with the card on it. The card rises into
/// place when it appears. [bottom] puts it at the bottom of the screen (a
/// page sliding up), otherwise it sits in the middle.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.child, this.bottom = false, this.maxWidth = 440});
  final Widget child;
  final bool bottom;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final body = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: still ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, (1 - t) * (bottom ? 120 : 26)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: child,
      ),
    );
    return ColoredBox(
      color: rgba(6, 9, 22, 0.78),
      child: Align(
        alignment: bottom ? Alignment.bottomCenter : Alignment.center,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(14 + pad.left, 26 + pad.top, 14 + pad.right, (bottom ? 10 : 26) + pad.bottom),
          child: body,
        ),
      ),
    );
  }
}

Widget _gap([double h = 14]) => SizedBox(height: h);

/// The buttons under a card: the webbing strap, then index lines 02, 03…
Widget _buttons(List<GameButton> buttons) {
  var n = 1;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final b in buttons) ...[
      if (b.primary)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: b)
      else
        GameButton(label: b.label, onTap: b.onTap, index: ++n, semanticLabel: b.semanticLabel),
    ],
  ]);
}

/// The heading of a page: a title in Archivo and, beside it, typed words.
Widget _heading(String title, String typed, {double size = 34}) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 2,
      children: [
        Text(title.toUpperCase(), style: FbTxt.label(size)),
        Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(typed.toUpperCase(), style: FbTxt.typed(13, bold: true, height: 1))),
      ],
    );

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

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
    final d = data, still = MediaQuery.disableAnimationsOf(context);
    var i = 0;
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the log page, torn across the bottom
        FieldPage(
          angle: -3,
          tornTop: 34,
          rings: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Stagger(
                  index: i++,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOU FELL', style: FbTxt.typed(13, bold: true)),
                    const SizedBox(height: 4),
                    Text((game.route?.name ?? '').toUpperCase(), style: FbTxt.label(26)),
                  ]),
                ),
              ),
              Stagger(
                index: i++,
                child: _StampIn(still: still, child: InkStamp(word: 'Fell', number: d.value, angle: -12, size: 0.9)),
              ),
            ]),
            _gap(10),
            Stagger(index: i++, child: Text(d.why, style: Txt.body(17, color: Kit.ink, height: 1.4))),
            _gap(),
            Stagger(
              index: i++,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 70,
                  width: double.infinity,
                  child: Semantics(
                    label: 'Hand strength before the fall',
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: still ? 1 : 0, end: 1),
                      duration: const Duration(milliseconds: 1100),
                      curve: const Interval(0.25, 1, curve: Curves.easeInOutCubic),
                      builder: (context, t, _) => CustomPaint(painter: TracePainter(d.trace, d.hand, progress: t)),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('HAND STRENGTH', style: FbTxt.typed(12, bold: true)),
              ]),
            ),
            if (d.note != null) ...[
              _gap(10),
              Stagger(
                index: i++,
                child: Text(d.note!, style: FbTxt.typed(14, bold: !d.noteDim, color: d.noteDim ? Kit.graphite : Kit.ink)),
              ),
            ],
          ]),
        ),
        // the fix, on a scrap taped to the rock
        Transform.translate(
          offset: const Offset(0, -18),
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 8),
            child: Stagger(
              index: i++,
              child: PaperScrap(
                angle: 1.5,
                torn: false,
                tapeAt: 0.1,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: LampIcon()),
                  const SizedBox(width: 10),
                  Expanded(child: Text(d.fix, style: Txt.body(15, color: Kit.ink, height: 1.4))),
                ]),
              ),
            ),
          ),
        ),
        // below the tear, on the rock
        Stagger(
          index: i++,
          child: _buttons([
            GameButton(label: d.retryLabel, primary: true, onTap: () => _tap(game.retry)),
            if (d.showRestart) GameButton(label: 'Start over', onTap: () => _tap(game.restart)),
            GameButton(label: game.backLabel, onTap: () => _tap(game.goBack)),
          ]),
        ),
      ]),
    );
  }
}

/// A stamp that lands: it comes down a little bigger and settles.
class _StampIn extends StatelessWidget {
  const _StampIn({required this.still, required this.child});
  final bool still;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (still) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: const Interval(0.35, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 1.6 - 0.6 * t, child: child)),
      child: child,
    );
  }
}

/// Today as the register writes it: "29 OCT".
String _registerDate(Game g) {
  final p = g.todayKey.split('-');
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  return p.length == 3 ? '${int.parse(p[2])} ${months[(int.parse(p[1]) - 1).clamp(0, 11)]}' : '';
}

/// The summit register's page: its column heads, and faded scribbles above
/// for the entries of others (they are only lines, not names).
class _Register extends StatelessWidget {
  const _Register({required this.children});
  final List<Widget> children;
  static const int scribbles = 3;

  @override
  Widget build(BuildContext context) {
    final head = FbTxt.typed(11, bold: true, color: Kit.graphite, height: 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(flex: 4, child: Text('DATE', style: head)),
        Expanded(flex: 3, child: Text('CLIMBER', style: head)),
        Expanded(flex: 5, child: Text('ROUTE', style: head)),
        Expanded(flex: 3, child: Text('TIME', textAlign: TextAlign.right, style: head)),
      ]),
      const SizedBox(height: 4),
      Container(height: 1.5, color: Kit.ink),
      ExcludeSemantics(child: SizedBox(height: scribbles * 22.0, child: CustomPaint(painter: _ScribblePainter(scribbles)))),
      ...children,
    ]);
  }
}

class _ScribblePainter extends CustomPainter {
  _ScribblePainter(this.rows);
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rng(rows * 13 + 7);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = Kit.graphite.withValues(alpha: 0.35);
    for (var k = 0; k < rows; k++) {
      final y = 14 + k * 22.0;
      for (final (a, b) in [(0.0, 0.16), (0.21, 0.45), (0.5, 0.78), (0.86, 1.0)]) {
        final path = Path()..moveTo(size.width * a, y);
        for (var x = size.width * a; x < size.width * (b - 0.02); x += 5) {
          path.lineTo(x + 5, y + (r() - 0.5) * 4);
        }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScribblePainter o) => o.rows != rows;
}

/// One entry in the register, written by hand.
class _Entry extends StatelessWidget {
  const _Entry({required this.date, required this.climber, required this.route, required this.time});
  final String date, climber, route, time;

  @override
  Widget build(BuildContext context) {
    final hand = FbTxt.hand(30, color: Kit.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(flex: 4, child: Text(date, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: hand)),
        Expanded(flex: 3, child: Text(climber, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: hand)),
        Expanded(flex: 5, child: Text(route, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: hand)),
        Expanded(flex: 3, child: Text(time, maxLines: 1, textAlign: TextAlign.right, style: hand)),
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
    final top = game.route == null ? '' : '${(game.route!.topY / 100).toStringAsFixed(1)} m';

    /// A number that counts up from zero when the card appears.
    Widget count(num to, String Function(double v) show) => TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? to.toDouble() : 0, end: to.toDouble()),
          duration: const Duration(milliseconds: 900),
          curve: const Interval(0.2, 1, curve: Curves.easeOutCubic),
          builder: (context, v, _) => Text(show(v)),
        );
    var i = 0;
    return _Overlay(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(clipBehavior: Clip.none, children: [
          CustomPaint(
            painter: PaperPainter(color: Kit.register, rule: Rule.ruled, cell: 26, shadow: 8, seed: 9),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Surface(
                paper: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Stagger(index: i++, child: Text('SUMMIT REGISTER', style: FbTxt.typed(13, bold: true))),
                  _gap(4),
                  Stagger(index: i++, child: Padding(padding: const EdgeInsets.only(right: 90), child: Text('YOU MADE IT', style: FbTxt.label(40)))),
                  _gap(12),
                  Stagger(
                    index: i++,
                    child: _Register(children: [
                      _Entry(date: _registerDate(game), climber: d.climber, route: d.routeName, time: fmtTime(d.seconds)),
                    ]),
                  ),
                  _gap(10),
                  Stagger(
                    index: i++,
                    child: Column(children: [
                      LeaderRow(label: 'Time', value: count(d.seconds, fmtTime)),
                      LeaderRow(label: 'Moves', value: count(d.moves, (v) => '${v.round()}')),
                      LeaderRow(label: 'Falls', value: count(d.falls, (v) => '${v.round()}')),
                    ]),
                  ),
                  _gap(10),
                  Stagger(
                    index: i++,
                    child: Text(d.note, style: FbTxt.typed(14, bold: !d.noteDim, color: d.noteDim ? Kit.graphite : Kit.ink)),
                  ),
                  if (game.onlineClimb) ...[_gap(), Stagger(index: i++, child: _FinishOrder(game: game))],
                ]),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: -14,
            child: _StampIn(still: still, child: InkStamp(word: 'Top', number: top, circle: true, angle: 12)),
          ),
        ]),
        _gap(18),
        Stagger(
          index: i++,
          child: _buttons([
            // online, the room climbs one route: no next route
            if (!game.onlineClimb) GameButton(label: d.nextLabel, primary: true, onTap: () => _tap(game.nextRoute)),
            GameButton(label: 'Again', primary: game.onlineClimb, onTap: () => _tap(game.restart)),
            GameButton(label: game.backLabel, onTap: () => _tap(game.goBack)),
          ]),
        ),
      ]),
    );
  }
}

/// Online: who reached the top in what order and time, then who is still
/// climbing and how high, as entries in the register. It keeps up while the
/// card is open. [over]: the room's climb has ended, so the others did not
/// finish.
class _FinishOrder extends StatelessWidget {
  const _FinishOrder({required this.game, this.over = false});
  final Game game;
  final bool over;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.standingsChanged,
      builder: (context, _) {
        final list = game.standings;
        var place = 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('FINISHING ORDER', style: FbTxt.typed(13, bold: true)),
          const SizedBox(height: 6),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                  width: 40,
                  child: Text(s.finish != null ? ordinal(++place) : '–', style: FbTxt.typed(14, bold: true, color: Kit.graphite)),
                ),
                Expanded(
                  child: Text(s.you ? '${s.name} (you)' : s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.you ? FbTxt.hand(30, color: Kit.blaze) : FbTxt.hand(30, color: Kit.ink)),
                ),
                if (s.finish case final f?)
                  Text(fmtTime(f), style: FbTxt.typed(15, bold: true))
                else
                  Text('${over ? 'did not finish' : 'climbing'} · ${s.metres.toStringAsFixed(1)} m',
                      style: FbTxt.typed(13, color: Kit.graphite)),
              ]),
            ),
        ]);
      },
    );
  }
}

/// Online: the room's results once its climb is over (everyone topped out,
/// or the creator ended it): the register, one real row per player. The
/// creator can play again: the same room and players, a new start. Everyone
/// can leave.
class ResultsCard extends StatelessWidget {
  const ResultsCard({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: game.online,
      builder: (context, _) {
        final o = game.online, room = o.room, host = room?.player(room.host);
        var i = 0;
        return _Overlay(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CustomPaint(
              painter: PaperPainter(color: Kit.register, rule: Rule.ruled, cell: 26, shadow: 8, seed: 11),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Surface(
                  paper: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Stagger(
                      index: i++,
                      child: Text('${game.route?.name ?? ''} · Room ${room?.code ?? ''}'.toUpperCase(), style: FbTxt.typed(13, bold: true)),
                    ),
                    _gap(4),
                    Stagger(index: i++, child: Text('RESULTS', style: FbTxt.label(40))),
                    _gap(12),
                    Stagger(index: i++, child: _FinishOrder(game: game, over: true)),
                  ]),
                ),
              ),
            ),
            _gap(18),
            Stagger(
              index: i++,
              child: FrameSelect<int?>(
                game: game,
                select: (g) => g.countdown?.ceil(),
                builder: (context, left) {
                  if (left != null) {
                    return Text(left > 0 ? 'Starting in $left' : 'Starting…',
                        textAlign: TextAlign.center, style: FbTxt.label(32, color: Kit.blazeWhite));
                  }
                  return _buttons([
                    if (o.isHost) GameButton(label: 'Play again', primary: true, onTap: o.busy ? null : () => _tap(game.playAgain)),
                    GameButton(label: 'Leave', onTap: () => _tap(game.leaveOnline)),
                  ]);
                },
              ),
            ),
            if (!o.isHost) ...[
              const SizedBox(height: 10),
              Text('Waiting for ${host?.name ?? 'the creator'} to play again…',
                  textAlign: TextAlign.center, style: FbTxt.typed(14, color: Kit.blazeWhite)),
            ],
          ]),
        );
      },
    );
  }
}

/// Pause: the climb so far, written in the log. On a phone the page slides
/// up from the bottom; on a wide screen the book lies open.
class PauseCard extends StatelessWidget {
  const PauseCard({super.key, required this.game});
  final Game game;

  void _tap(VoidCallback f) {
    game.audio.play(Sfx.tap);
    f();
  }

  @override
  Widget build(BuildContext context) {
    final r = game.route, wide = MediaQuery.sizeOf(context).width >= 760;
    final falls = game.falls == 0 ? 'none yet' : '${_plural(game.falls, 'fall', 'falls')}${game.caught > 0 ? ', ${game.caught} caught' : ''}';
    final lines = <Widget>[
      LogLine(label: 'TIME', text: fmtTime(game.time)),
      LogLine(label: 'MOVES', text: '${game.moves}'),
      LogLine(label: 'FALLS', text: falls),
      if (r != null && !r.endless) LogLine(label: 'SAVES', text: game.lit.isEmpty ? 'no lamp lit yet' : _plural(game.lit.length, 'lamp lit', 'lamps lit')),
      LogLine(label: 'NOW', text: '${game.climberHeight().toStringAsFixed(1)} m up', cursor: true),
    ];
    final heading = _heading(r?.name ?? '', '${game.mode.label} · ${game.climber.name}');
    final toggles = Wrap(spacing: 8, runSpacing: 4, children: [
      GameToggle(label: 'Music', value: game.audio.musicOn, onChanged: game.setMusic),
      GameToggle(label: 'Sounds', value: game.audio.sfxOn, onChanged: game.setSfx),
    ]);
    final buttons = _buttons([
      GameButton(label: 'Back on the wall', primary: true, semanticLabel: 'Resume', onTap: () => _tap(game.resume)),
      GameButton(label: 'Start over', onTap: () => _tap(game.restart)),
      // online, the creator can end the climb for everyone: the results show
      if (game.onlineClimb && game.online.isHost) GameButton(label: 'End climb', onTap: () => _tap(game.endClimb)),
      GameButton(label: game.backLabel, onTap: () => _tap(game.goBack)),
    ]);
    var i = 0;
    if (wide) {
      return _Overlay(
        maxWidth: 880,
        child: FieldPage(
          spread: true,
          angle: -0.6,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stagger(index: i++, child: heading),
                  _gap(16),
                  for (final l in lines) Stagger(index: i++, child: Padding(padding: const EdgeInsets.only(bottom: 6), child: l)),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Stagger(index: i++, child: toggles),
                  _gap(16),
                  Stagger(index: i++, child: buttons),
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    return _Overlay(
      bottom: true,
      child: FieldPage(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stagger(index: i++, child: heading),
          _gap(12),
          for (final l in lines) Stagger(index: i++, child: Padding(padding: const EdgeInsets.only(bottom: 4), child: l)),
          _gap(8),
          Stagger(index: i++, child: toggles),
          _gap(10),
          Stagger(index: i++, child: buttons),
        ]),
      ),
    );
  }
}
