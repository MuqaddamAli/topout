// Standing and walking on the ground (online, and alone on a wall with
// lanes): the start, keys and a finger held beside the climber, the wall's
// edges, other lanes, the first grab, standing up again, and other players'
// walking played back from their states. A climb alone does not change.
// Screenshots go to build/screens/ (5x_*).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/remote.dart';
import 'package:topout/game/store.dart';
import 'package:topout/game/walk.dart';
import 'package:topout/ui/app.dart';

import 'fonts.dart';

void main() {
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

  /// A climb alone on a wall with [lanes] lanes (as with ?lanes=N).
  Future<Game> open(WidgetTester tester, {int lanes = 2, int route = 0}) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27))
      ..debugLanes = lanes;
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 0.3);
    game.startRoute(game.routes[route]);
    await frames(tester, 0.6);
    game.hideTip();
    return game;
  }

  Future<void> walk(WidgetTester tester, Game g, LogicalKeyboardKey k, double seconds) async {
    expect(g.key(k), isTrue);
    await frames(tester, seconds);
    expect(g.keyUp(k), isTrue);
  }

  /// Drags limb [i] to the world point [to], through the game's own input.
  Future<void> dragTo(WidgetTester tester, Game g, int i, Pt to) async {
    final from = g.w2s(g.limbEnd(i).x, g.limbEnd(i).y);
    g.pointerDown(1, from, false);
    for (var n = 1; n <= 8; n++) {
      g.pointerMove(1, Offset.lerp(from, g.w2s(to.x, to.y), n / 8)!);
      await frames(tester, 0.03);
    }
    g.pointerUp(1);
    await frames(tester, 0.4);
  }

  testWidgets('the start: standing on the ground at the spawn, hands free', (tester) async {
    final g = await open(tester);
    final r = g.route!, s = r.lanes[0].spawns[0];
    expect(g.social, isTrue);
    expect(g.standOn, 0);
    expect(g.c.x, closeTo(s.x, 0.5));
    expect([for (final l in g.limbs) l.h], [null, null, 0, 0]);
    expect(g.c.y, closeTo(standHeight(g.climber) + 2.5, 0.5), reason: 'upright');
    // standing, the grip comes back
    g.grip[0] = 40;
    await frames(tester, 1);
    expect(g.grip[0], greaterThan(50));
    await shot(tester, '50_walk_start');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keys walk left and right, calmly, and stop when let go', (tester) async {
    final g = await open(tester);
    final x0 = g.c.x;
    expect(g.key(LogicalKeyboardKey.keyD), isTrue);
    await frames(tester, 1);
    expect(g.walkAmt, greaterThan(0.9));
    expect(g.facing, 1);
    await shot(tester, '51_walk_right');
    expect(g.keyUp(LogicalKeyboardKey.keyD), isTrue);
    await frames(tester, 0.5);
    expect(g.walkAmt, lessThan(0.05));
    // about walking speed, a little less for speeding up and slowing down
    expect(g.c.x - x0, inInclusiveRange(walkSpeed * 0.8, walkSpeed * 1.3));
    final x1 = g.c.x;
    await walk(tester, g, LogicalKeyboardKey.arrowLeft, 0.6);
    expect(g.facing, -1);
    expect(g.c.x, lessThan(x1 - 20));
    // the feet stay on the ground, under the body
    expect([g.limbs[2].h, g.limbs[3].h], [0, 0]);
    expect((g.limbs[2].x + g.limbs[3].x) / 2, closeTo(g.c.x, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('walking along the ground reaches the next lane, and stops at the wall edge', (tester) async {
    final g = await open(tester);
    final r = g.route!;
    await walk(tester, g, LogicalKeyboardKey.keyD, 8);
    expect(r.laneAt(g.c.x).index, 1, reason: 'walked into lane 2');
    expect(g.camX, closeTo(g.camXFor(g.cd.x), 20), reason: 'the camera came along');
    await walk(tester, g, LogicalKeyboardKey.keyD, 6);
    expect(g.c.x, closeTo(r.wallRight - 20, 0.5));
    await walk(tester, g, LogicalKeyboardKey.keyA, 20);
    expect(g.c.x, closeTo(r.wallLeft + 20, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finger held beside the climber walks there; a quick swipe up or down pans', (tester) async {
    final g = await open(tester);
    final x0 = g.c.x;
    // hold to the right of the climber, at chest height
    final at = g.w2s(x0 + 90, g.c.y);
    g.pointerDown(1, at, true);
    await frames(tester, 3);
    expect(g.c.x, closeTo(x0 + 90, 8), reason: 'walked to the finger and stopped');
    g.pointerUp(1);
    await frames(tester, 0.3);
    expect(g.walkTo, isNull);
    // a quick move up is a pan, not a walk
    final x1 = g.c.x, p = g.w2s(x1 - 80, g.c.y);
    g.pointerDown(2, p, true);
    g.pointerMove(2, p.translate(0, 60));
    await frames(tester, 0.6);
    expect(g.walkTo, isNull);
    expect(g.c.x, closeTo(x1, 1));
    expect(g.showRecenter, isTrue);
    g.pointerUp(2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standing: a foot cannot lift; a hand grab starts the climb, feet on the ground again stand you up', (tester) async {
    final g = await open(tester);
    final r = g.route!, x0 = g.c.x;
    // a foot first: no
    await dragTo(tester, g, 3, Pt(x0 + 30, 50));
    expect(g.standOn, 0);
    expect(g.limbs[3].h, 0);
    // a hand on a hold within reach: climbing
    final k = [
      for (var n = 0; n < r.holds.length; n++)
        if (r.holds[n].t == HoldType.jug && feasible(g.limbs, 0, attachPoint(r.holds[n], 0), g.c, g.climber) != null) n
    ].first;
    await dragTo(tester, g, 0, attachPoint(r.holds[k], 0));
    expect(g.limbs[0].h, k);
    expect(g.standOn, isNull);
    expect(g.key(LogicalKeyboardKey.keyD), isTrue, reason: 'the key is taken, but no walking while climbing');
    await frames(tester, 0.5);
    g.keyUp(LogicalKeyboardKey.keyD);
    expect(g.limbs[0].h, k);
    // both feet on the ground again: you stand and the hand lets go
    await dragTo(tester, g, 3, Pt(g.limbs[3].x + 10, 0));
    expect(g.standOn, 0);
    expect(g.limbs[0].h, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a climb alone is as it always was: no standing, no walking', (tester) async {
    final g = await open(tester, lanes: 1);
    final r = g.route!;
    expect(g.social, isFalse);
    expect(g.standOn, isNull);
    expect([g.limbs[0].h, g.limbs[1].h], r.startHands);
    expect((g.limbs[2].x, g.limbs[3].x), (164.0, 198.0));
    final c0 = g.c.copy();
    expect(g.key(LogicalKeyboardKey.keyD), isFalse);
    await frames(tester, 0.5);
    expect(g.c.x, closeTo(c0.x, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  test('a standing climber state goes over the wire, and the others see the steps', () {
    ClimberState st(int t, double x) => ClimberState(
          t: t,
          climber: 'rio',
          c: Pt(x, 101),
          tilt: 0,
          lookX: 0,
          lookUp: 0.5,
          ends: [Pt(x - 19, 70), Pt(x + 19, 70), Pt(x - 12, 0), Pt(x + 12, 0)],
          styles: const [HandStyle.open, HandStyle.open],
          kinds: const [HoldType.jug, HoldType.jug],
          footFree: const [false, false],
          standing: true,
          facingLeft: true,
          secs: 1,
        );
    final back = ClimberState.decode(st(0, 200).encode())!;
    expect((back.standing, back.facingLeft), (true, true));
    // a state without the new bits (an older game, or climbing) is not standing
    final raw = st(0, 200).encode()..[15] = 0;
    final plain = ClimberState.decode(raw)!;
    expect((plain.standing, plain.facingLeft), (false, false));

    // someone walks left at walking speed: their feet take turns
    final o = RemoteClimber('p1', 'Bo');
    for (var k = 0; k <= 20; k++) {
      o.add(st(k * 100, 400 - k * walkSpeed / 10), k * 100);
    }
    final feet = <double>[];
    for (var ms = 1000; ms <= 2000; ms += 16) {
      o.update(ms, 0.016, ms / 1000);
      feet.add(o.pose!.legs[0].e.x - o.pose!.legs[1].e.x);
    }
    expect(o.pose!.c.x, lessThan(400 - walkSpeed));
    // the gap between the feet swings both ways as they step
    expect(feet.reduce(math.max) - feet.reduce(math.min), greaterThan(12));
    // standing still: feet side by side
    for (var k = 21; k <= 40; k++) {
      o.add(st(k * 100, 400 - 20 * walkSpeed / 10), k * 100);
    }
    o.update(4100, 0.016, 4.1);
    for (var ms = 4100; ms <= 5000; ms += 16) {
      o.update(ms, 0.016, ms / 1000);
    }
    expect((o.pose!.legs[0].e.x - o.pose!.legs[1].e.x).abs(), closeTo(24, 2));
  });
}
