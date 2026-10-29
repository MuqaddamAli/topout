// The mountain around a route: colours and the hour follow the height, snow
// lies on the upper part of every route, and snowy holds are slick until a
// hand or foot has brushed them off. Also saves screenshots of every band
// and hour to build/screens/ (scenery_*), to check the art by eye.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/mountain.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';
import 'package:topout/ui/climbers.dart';

import 'fonts.dart';

/// Puts the climber of [g] in a stance near height [y]: two hand holds a
/// little above it and two foot holds below, as close to [x] as there are.
void placeAt(Game g, double y, {double x = 180}) {
  final h = g.holds;
  int? pick(bool hand, double lo, double hi, double near, int? not) {
    int? best;
    var bd = double.infinity;
    for (var k = 0; k < h.length; k++) {
      final t = h[k].t;
      if (k == not || t.wide || t == HoldType.ground || (hand ? t.hand : t.foot) == Quality.no) continue;
      if (h[k].y < lo || h[k].y > hi) continue;
      final d = (h[k].x - near).abs();
      if (d < bd) {
        bd = d;
        best = k;
      }
    }
    return best;
  }

  final l = pick(true, y + 30, y + 100, x - 30, null) ?? pick(true, y, y + 140, x - 30, null)!;
  final r = pick(true, y + 30, y + 100, x + 30, l) ?? pick(true, y, y + 140, x + 30, l)!;
  final lf = pick(false, y - 90, y - 20, x - 22, null) ?? pick(false, y - 130, y, x - 22, null)!;
  final rf = pick(false, y - 90, y - 20, x + 22, lf) ?? pick(false, y - 130, y, x + 22, lf)!;
  final ids = [l, r, lf, rf];
  g.limbs = [for (var i = 0; i < 4; i++) Limb(ids[i], attachPoint(h[ids[i]], i).x, attachPoint(h[ids[i]], i).y)];
  final s = solve(Pt(x, y), [for (var i = 0; i < 4; i++) Anchor(i, g.limbs[i].x, g.limbs[i].y)], 80, g.climber.reach);
  g.c = Pt(s.x, s.y);
  g.cd = g.c.copy();
  g.endDraw = [for (final l in g.limbs) Pt(l.x, l.y)];
  g.camManual = null;
}

void main() {
  test('the hour passes as you climb, and only the hard route and the Daily Wall reach the night', () {
    final routes = buildRoutes(), daily = dailyWallFor(DateTime(2026, 10, 27));
    for (final r in routes) {
      expect(Mountain.hourAt(r, 0), closeTo(1, 0.01), reason: '${r.name} starts in the afternoon');
      expect(Mountain.hourAt(r, r.topY), greaterThan(1.9), reason: '${r.name} is at dusk near the top');
      var last = 0.0;
      for (var y = 0.0; y <= r.topY; y += 20) {
        final h = Mountain.hourAt(r, y);
        expect(h, greaterThanOrEqualTo(last));
        last = h;
      }
      expect(Mountain.night(Mountain.hourAt(r, r.topY)) > 0.5, r.level >= 3, reason: r.name);
    }
    expect(Mountain.night(Mountain.hourAt(daily, 1500)), 0);
    expect(Mountain.night(Mountain.hourAt(daily, 8000)), 1);
  });

  test('snow lies on the upper part of every route, more of it higher up', () {
    for (final r in [...buildRoutes(), dailyWallFor(DateTime(2026, 10, 27))]) {
      final top = r.endless ? 6000.0 : r.topY;
      expect(Mountain.snow(r, top * 0.25), 0, reason: r.name);
      expect(Mountain.snow(r, top), greaterThan(0.8), reason: r.name);
      final covered = [for (var k = 0; k < r.holds.length; k++) if (Mountain.snowCovered(r, k)) r.holds[k]];
      expect(covered, isNotEmpty, reason: r.name);
      expect(covered.every((h) => !h.t.rest), isTrue);
      expect(covered.map((h) => h.y).reduce((a, b) => a < b ? a : b), greaterThan(r.endless ? dailyIce - 300 : top * 0.4), reason: r.name);
    }
  });

  test('a hand on a snowy hold tires faster, a foot on one helps less', () {
    final holds = [const Hold(HoldType.ground, -200, 0, 560), const Hold(HoldType.jug, 150, 220), const Hold(HoldType.jug, 210, 220),
      const Hold(HoldType.chip, 160, 90), const Hold(HoldType.chip, 200, 90)];
    final limbs = [Limb(1, 147, 220), Limb(2, 213, 220), Limb(3, 160, 90), Limb(4, 200, 90)];
    final dry = gripRates(limbs, holds, Mode.normal);
    final wetHand = gripRates(limbs, holds, Mode.normal, null, {1});
    final wetFoot = gripRates(limbs, holds, Mode.normal, null, {3});
    expect(wetHand.rates[0], closeTo(dry.rates[0] * snowSlick, 1e-9));
    expect(wetHand.rates[1], dry.rates[1]);
    expect(wetFoot.s.feetW, closeTo(1 + snowFoot, 1e-9));
    expect(wetFoot.rates[0], lessThan(dry.rates[0]));
    expect(wetFoot.s.supported, isTrue);
  });

  testWidgets('a snowy hold is brushed off after a moment, then it is like any other', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27));
    await tester.pumpWidget(TopoutApp(game: game));
    await tester.pump(const Duration(milliseconds: 100));
    final r = game.routes[1];
    game.startRoute(r);
    await tester.pump(const Duration(milliseconds: 100));
    placeAt(game, r.topY - 220);
    final snowy = [for (final l in game.limbs) if (game.snowCover.contains(l.h)) l.h!];
    expect(snowy, isNotEmpty, reason: 'some holds up high have snow');
    for (var k = 0; k < 30; k++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.snowyHeld, isNotEmpty);
    for (var k = 0; k < 90; k++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (final k in snowy) {
      expect(game.snowOn(k), 0, reason: 'the snow is off hold $k');
    }
    expect(game.snowyHeld, isEmpty);
  });

  group('screenshots', () {
    final shotKey = GlobalKey();
    Future<void> shot(WidgetTester tester, String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/screens')..createSync(recursive: true);
        File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> frames(WidgetTester tester, double seconds) async {
      for (var k = 0; k < (seconds * 60).round(); k++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
    }

    testWidgets('the four climbers, close up', (tester) async {
      await loadGameFonts();
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(
        key: shotKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFF6E7F86),
            child: Row(children: [
              for (final k in Climber.all) Expanded(child: Padding(padding: const EdgeInsets.all(12), child: ClimberPortrait(climber: k))),
            ]),
          ),
        ),
      ));
      await frames(tester, 0.2);
      await shot(tester, 'scenery_climbers');
    });

    testWidgets('each climber on the wall', (tester) async {
      await loadGameFonts();
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27));
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
      await frames(tester, 0.5);
      for (final k in Climber.all) {
        game.showMenu();
        await frames(tester, 0.2);
        game.setClimber(k);
        game.startRoute(game.routes[1]);
        await frames(tester, 0.3);
        placeAt(game, 330);
        await frames(tester, 1.2);
        await shot(tester, 'scenery_climber_${k.id}');
      }
    });

    testWidgets('every band and hour', (tester) async {
      await loadGameFonts();
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27));
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
      await frames(tester, 1);
      await shot(tester, 'scenery_00_menu');
      // the rest of the field book, scrolled up over the poster
      for (final n in ['b', 'c', 'd']) {
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -700));
        await frames(tester, 0.6);
        await shot(tester, 'scenery_00_menu_$n');
      }
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 3000));
      await frames(tester, 0.4);
      var n = 1;
      for (final r in game.routes) {
        game.startRoute(r);
        await frames(tester, 0.3);
        final top = r.endless ? 7000.0 : r.topY;
        for (final f in r.endless ? const [0.3, 0.45, 0.65, 0.9] : const [0.25, 0.55, 0.85]) {
          placeAt(game, top * f - 60);
          // the grip would run out while the shots are taken
          game.grip = [100, 100];
          await frames(tester, 1.4);
          game.grip = [100, 100];
          await shot(tester, 'scenery_${(n++).toString().padLeft(2, '0')}_${r.id}_${(f * 100).round()}');
        }
        if (!r.endless) {
          game.camManual = r.topY - 60;
          await frames(tester, 1.4);
          game.grip = [100, 100];
          await shot(tester, 'scenery_${(n++).toString().padLeft(2, '0')}_${r.id}_summit');
        }
      }
    });
  });
}
