import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/audio.dart';
import '../game/climber.dart';
import '../game/core.dart';
import '../game/field_book.dart';
import '../game/game.dart';
import '../game/palette.dart';
import 'kit.dart';
import 'motion.dart';
import 'widgets.dart';

/// Pick who climbs: an index card for each climber, then the card of the
/// one you picked with their stats as tally marks and their perk as a
/// pencil note. The stats of every climber add up to the same total.
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
      if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cards, const SizedBox(height: 12), info]);
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 11, child: cards),
          const SizedBox(width: 14),
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
    final on = game.climber == climber;
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
        child: AnimatedSlide(
          offset: Offset(0, on ? -0.03 : 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Stack(clipBehavior: Clip.none, children: [
            IndexCard(
              color: on ? Kit.card : Color.lerp(Kit.card, Kit.manila, 0.55),
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // picked, the climber grows a little and gives a small hop
                Once(
                  replay: on,
                  onShow: false,
                  duration: const Duration(milliseconds: 440),
                  curve: Curves.easeOut,
                  builder: (context, t, child) => Transform.translate(offset: Offset(0, on ? -math.sin(t * math.pi) * 7 : 0), child: child),
                  child: AnimatedScale(
                    scale: on ? 1 : 0.9,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: SizedBox(height: 92, child: ClimberPortrait(climber: climber)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(climber.name.toUpperCase(), style: FbTxt.label(22, color: on ? Kit.ink : Kit.graphite)),
              ]),
            ),
            // the picked one: a webbing ribbon that runs down its left edge
            if (on)
              Positioned(
                left: -3,
                top: -4,
                bottom: 10,
                width: 9,
                child: Once(
                  duration: const Duration(milliseconds: 360),
                  builder: (context, t, child) => FractionallySizedBox(alignment: Alignment.topCenter, heightFactor: t, child: child),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Kit.webbing,
                      border: Border.symmetric(vertical: BorderSide(color: Kit.webbingEdge, width: 2)),
                    ),
                  ),
                ),
              ),
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
    return IndexCard(
      headAt: 46,
      angle: -0.6,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 30,
          child: _Fade(id: k.id, child: Text('${k.name} · ${k.role}'.toUpperCase(), style: FbTxt.label(26))),
        ),
        const SizedBox(height: 12),
        for (var row = 0; row < 2; row++)
          Row(children: [
            for (var col = 0; col < 2; col++) ...[
              if (col > 0) const SizedBox(width: 14),
              Expanded(child: StatPips(label: stats[row * 2 + col].$1, value: stats[row * 2 + col].$2)),
            ],
          ]),
        const SizedBox(height: 6),
        _Fade(
          id: k.id,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // the perk, as a pencil note that writes itself in
            WriteIn(delay: const Duration(milliseconds: 120), child: Text(k.perk.label.toLowerCase(), style: FbTxt.hand(32, color: Kit.blaze))),
            const SizedBox(width: 10),
            Expanded(child: Text(k.perk.note, style: Txt.body(14, color: Kit.ink, height: 1.3))),
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

/// A stat from 1 to 5, as tally marks.
class StatPips extends StatelessWidget {
  const StatPips({super.key, required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value of 5',
      excludeSemantics: true,
      child: SizedBox(
        height: 22,
        child: Row(children: [
          SizedBox(width: 52, child: Text(label.toUpperCase(), style: FbTxt.typed(12, bold: true, height: 1))),
          TallyMarks(count: value, height: 18),
        ]),
      ),
    );
  }
}

/// A climber standing tall, painted with the same code as in the game.
class ClimberPortrait extends StatelessWidget {
  const ClimberPortrait({super.key, required this.climber, this.glow = false});
  final Climber climber;
  final bool glow;

  @override
  Widget build(BuildContext context) =>
      CachedPaint(cacheKey: 'portrait-${climber.id}-$glow', painter: _PortraitPainter(climber, glow));
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
