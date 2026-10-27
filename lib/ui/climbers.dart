import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/climber.dart';
import '../game/core.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'widgets.dart';

/// Pick who climbs: a card for each climber, then the stats and perk of the
/// one you picked. The stats of every climber add up to the same total.
class ClimberPicker extends StatelessWidget {
  const ClimberPicker({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 660;
      final cards = Row(children: [
        for (final k in Climber.all) ...[
          if (k != Climber.all.first) const SizedBox(width: 8),
          Expanded(child: _ClimberCard(game: game, climber: k)),
        ],
      ]);
      final info = _ClimberInfo(climber: game.climber);
      if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cards, const SizedBox(height: 10), info]);
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 11, child: cards),
          const SizedBox(width: 12),
          Expanded(flex: 9, child: info),
        ]),
      );
    });
  }
}

class _ClimberCard extends StatelessWidget {
  const _ClimberCard({required this.game, required this.climber});
  final Game game;
  final Climber climber;

  @override
  Widget build(BuildContext context) {
    final on = game.climber == climber, look = Look.of(climber.id);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: '${climber.name}, ${climber.role}',
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          game.audio.play(Sfx.tap);
          game.setClimber(climber);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: on ? Color.alphaBlend(look.shirt[0].withAlpha(28), Pal.ink2) : Pal.ink2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? Pal.signal : Pal.line, width: on ? 2 : 1.5),
            boxShadow: on ? [BoxShadow(color: Pal.signal.withAlpha(46), blurRadius: 18, offset: const Offset(0, 6))] : const [],
          ),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedScale(
              scale: on ? 1 : 0.9,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: SizedBox(height: 92, child: ClimberPortrait(climber: climber, glow: on)),
            ),
            const SizedBox(height: 4),
            Text(climber.name.toUpperCase(), style: Txt.display(20, spacing: 0.06, color: on ? Pal.chalk : Pal.chalkDim)),
          ]),
        ),
      ),
    );
  }
}

/// Role, the four stats and the perk of the climber you picked.
class _ClimberInfo extends StatelessWidget {
  const _ClimberInfo({required this.climber});
  final Climber climber;

  @override
  Widget build(BuildContext context) {
    final k = climber;
    final stats = [('Reach', k.reachStat), ('Grip', k.gripStat), ('Rest', k.restStat), ('Jump', k.jumpStat)];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Pal.ink2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pal.line, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        _Fade(
          id: k.id,
          child: Text('${k.name} · ${k.role}'.toUpperCase(), style: Txt.display(19, spacing: 0.05)),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 7),
          Row(children: [
            for (var col = 0; col < 2; col++) ...[
              if (col > 0) const SizedBox(width: 14),
              Expanded(child: StatPips(label: stats[row * 2 + col].$1, value: stats[row * 2 + col].$2)),
            ],
          ]),
        ],
        const SizedBox(height: 11),
        _Fade(
          id: k.id,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.auto_awesome_rounded, size: 17, color: Pal.lamp),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${k.perk.label}. ', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.chalk)),
                  TextSpan(text: k.perk.note),
                ]),
                style: Txt.body(14, color: Pal.chalkDim, height: 1.35),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Cross-fades its child when [id] changes.
class _Fade extends StatelessWidget {
  const _Fade({required this.id, required this.child});
  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
      ),
      child: KeyedSubtree(key: ValueKey(id), child: child),
    );
  }
}

/// A stat from 1 to 5 as five small bars. They fill and empty smoothly.
class StatPips extends StatelessWidget {
  const StatPips({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value of 5',
      excludeSemantics: true,
      child: Row(children: [
        SizedBox(width: 46, child: Text(label.toUpperCase(), style: Txt.eyebrow(size: 10.5, spacing: 0.1))),
        for (var k = 1; k <= 5; k++)
          Expanded(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 160 + k * 40),
              curve: Curves.easeOut,
              height: 7,
              margin: EdgeInsets.only(left: k == 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: k <= value ? (value >= 4 ? Pal.good : (value <= 2 ? Pal.weak : Pal.signal)) : Pal.ink3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A climber standing tall, painted with the same code as in the game.
class ClimberPortrait extends StatelessWidget {
  const ClimberPortrait({super.key, required this.climber, this.glow = false});
  final Climber climber;
  final bool glow;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PortraitPainter(climber, glow), size: Size.infinite);
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter(this.climber, this.glow);
  final Climber climber;
  final bool glow;

  static final Map<String, ({Pose pose, Gear gear})> _cache = {};

  /// The pose and the settled gear, made once per climber.
  static ({Pose pose, Gear gear}) _figure(Climber k) => _cache.putIfAbsent(k.id, () {
        final look = Look.of(k.id), pose = standingPose(k);
        final gear = Gear(pose, links: look.tailLinks, link: look.tailLink);
        for (var n = 0; n < 90; n++) {
          gear.update(pose, 1 / 60, 140);
        }
        return (pose: pose, gear: gear);
      });

  @override
  void paint(Canvas canvas, Size size) {
    final k = climber, look = Look.of(k.id), f = _figure(k), h = standHeight(k);
    const top = 56.0, pad = 4.0;
    final s = (size.height - pad * 2) / (h + top);
    final cx = size.width / 2, by = size.height - pad;
    final floor = Rect.fromCenter(center: Offset(cx, by - 1), width: 46 * s, height: 9 * s);
    canvas.drawOval(floor, Paint()..color = rgba(0, 0, 0, 0.3));
    if (glow) {
      canvas.drawCircle(
          Offset(cx, by - (h + top) * s * 0.55),
          size.height * 0.46,
          Paint()
            ..shader = RadialGradient(colors: [look.shirt[0].withAlpha(70), look.shirt[0].withAlpha(0)])
                .createShader(Rect.fromCircle(center: Offset(cx, by - (h + top) * s * 0.55), radius: size.height * 0.46)));
    }
    canvas.save();
    canvas.translate(cx, by);
    canvas.scale(s, -s);
    canvas.translate(0, h);
    const ClimberPainter().draw(canvas, f.pose, f.gear, look);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter old) => old.climber != climber || old.glow != glow;
}
