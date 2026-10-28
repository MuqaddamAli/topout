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

  /// Puts the climber on First Wall just under its ledge (3.45 m, in lane
  /// 1): hands on the jugs above it, the left foot already on the ledge and
  /// the right one on a jug below. Returns the ledge.
  int underLedge(Game g) {
    final r = g.route!, h = r.holds;
    final ledge = h.indexWhere((x) => x.t == HoldType.ledge && x.x < Wall.right);
    int at(double x, double y) => h.indexWhere((o) => o.x == x && o.y == y);
    final hands = [at(150, 396), at(214, 408)], foot = at(226, 302);
    g.standOn = null;
    g.limbs = [
      Limb(hands[0], h[hands[0]].x - 3, h[hands[0]].y),
      Limb(hands[1], h[hands[1]].x + 3, h[hands[1]].y),
      Limb(ledge, 160, h[ledge].y),
      Limb(foot, h[foot].x + 3, h[foot].y),
    ];
    final s = solve(Pt(185, 380), g.anchors(), 80, g.climber.reach);
    g.c = Pt(s.x, s.y);
    g.cd = g.c.copy();
    g.camY = g.c.y + 40;
    return ledge;
  }

  /// Steps the right foot up onto [ledge], where it can reach.
  Future<void> stepUp(WidgetTester tester, Game g, int ledge) async {
    final h = g.holds[ledge];
    final x = [for (var x = h.x + 8; x < h.x2! - 8; x += 4) x]
        .firstWhere((x) => feasible(g.limbs, 3, Pt(x, h.y), g.c, g.climber) != null);
    await dragTo(tester, g, 3, Pt(x, h.y + 2));
  }

  testWidgets('on a ledge: both feet on it stand you up, it saves, and you walk to its ends', (tester) async {
    final g = await open(tester);
    final ledge = underLedge(g), h = g.holds[ledge];
    await frames(tester, 0.3);
    g.grip[0] = g.grip[1] = 30;
    await stepUp(tester, g, ledge);
    expect(g.standOn, ledge, reason: 'standing on the ledge');
    expect([g.limbs[0].h, g.limbs[1].h], [null, null], reason: 'the hands let go');
    expect(g.c.y, closeTo(h.y + standHeight(g.climber) + 2.5, 0.5));
    await frames(tester, 0.3);
    expect(g.lit, contains(ledge), reason: 'the lamp is lit: saved');
    expect(g.checkpoint!.ledge, ledge);
    expect(g.climberHeight(), closeTo(h.y / 100, 0.01));
    expect(g.pillText, 'Resting');
    // the grip comes back while you stand
    await frames(tester, 2);
    expect(g.grip[0], greaterThan(50));
    // walking stops at both ends, the feet stay on the ledge
    await walk(tester, g, LogicalKeyboardKey.keyD, 6);
    expect(g.c.x, closeTo(h.x2! - standMargin, 0.5));
    expect(g.limbs[3].x, lessThan(h.x2!));
    expect(g.standOn, ledge);
    await shot(tester, '52_ledge_end');
    await walk(tester, g, LogicalKeyboardKey.keyA, 6);
    expect(g.c.x, closeTo(h.x + standMargin, 0.5));
    expect(g.limbs[2].x, greaterThan(h.x));
    expect(g.phase, Phase.climb, reason: 'no walking off into a fall');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('from a ledge: climb on with a hand, undo, and a fall brings you back to where you left it', (tester) async {
    final g = await open(tester);
    final ledge = underLedge(g), r = g.route!;
    await frames(tester, 0.3);
    await stepUp(tester, g, ledge);
    await frames(tester, 0.3);
    expect(g.standOn, ledge);
    // walk a little along the ledge first
    await walk(tester, g, LogicalKeyboardKey.keyD, 0.8);
    await frames(tester, 0.4);
    final x0 = g.c.x;
    final k = [
      for (var n = 0; n < r.holds.length; n++)
        if (r.holds[n].t == HoldType.jug && r.holds[n].y > r.holds[ledge].y + 40 &&
            feasible(g.limbs, 1, attachPoint(r.holds[n], 1), g.c, g.climber) != null)
          n
    ].first;
    await dragTo(tester, g, 1, attachPoint(r.holds[k], 1));
    expect(g.limbs[1].h, k);
    expect(g.standOn, isNull, reason: 'climbing again');
    // undo stands you on the ledge again, where you were
    g.undo();
    await frames(tester, 0.3);
    expect(g.standOn, ledge);
    expect(g.c.x, closeTo(x0, 1));
    // climb on, let go and fall: Try again puts you back on the ledge, where you left it
    await dragTo(tester, g, 1, attachPoint(r.holds[k], 1));
    g.limbs[2].h = null;
    g.limbs[3].h = null;
    g.grip[0] = g.grip[1] = 1;
    await frames(tester, 2.5);
    expect(g.phase, Phase.fallCard);
    g.retry();
    await frames(tester, 0.4);
    expect(g.standOn, ledge);
    expect(g.c.x, closeTo(x0, 1));
    expect(g.limbs.map((l) => l.h).toList(), [null, null, ledge, ledge]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('No saves: you still stand and walk on a ledge, but a fall is from the ground', (tester) async {
    final g = await open(tester);
    g.setMode(Mode.solo);
    g.startRoute(g.routes[0]);
    await frames(tester, 0.4);
    final start = g.c.x, ledge = underLedge(g);
    await frames(tester, 0.3);
    await stepUp(tester, g, ledge);
    await frames(tester, 0.3);
    expect(g.standOn, ledge);
    expect(g.lit, isNot(contains(ledge)));
    final k = [
      for (var n = 0; n < g.holds.length; n++)
        if (g.holds[n].t == HoldType.jug && g.holds[n].y > 400 &&
            feasible(g.limbs, 1, attachPoint(g.holds[n], 1), g.c, g.climber) != null)
          n
    ].first;
    await dragTo(tester, g, 1, attachPoint(g.holds[k], 1));
    g.limbs[2].h = null;
    g.limbs[3].h = null;
    g.grip[0] = g.grip[1] = 1;
    await frames(tester, 2.5);
    expect(g.phase, Phase.fallCard);
    g.retry();
    await frames(tester, 0.4);
    expect(g.standOn, 0, reason: 'back on the ground');
    expect(g.c.x, closeTo(start, 1));
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
