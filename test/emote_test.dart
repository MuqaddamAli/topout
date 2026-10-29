// Emotes (online, and alone on a wall with lanes): Cheer, Taunt and Aura
// while standing, with keys 1, 2, 3 or the HUD buttons, a short cooldown,
// how each one ends, the poses, and the emote going over the wire to the
// others. Screenshots go to build/screens/ (5x_*).
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
import 'package:topout/ui/app.dart';
import 'package:topout/ui/hud.dart';

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

  Future<Game> open(WidgetTester tester, {int lanes = 2}) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27))
      ..debugLanes = lanes;
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 0.3);
    game.startRoute(game.routes[1]);
    await frames(tester, 0.6);
    game.hideTip();
    return game;
  }

  Finder hudButton(String label) => find.descendant(of: find.byType(Hud), matching: find.text(label));

  testWidgets('keys 1, 2, 3 emote while standing, with a short cooldown', (tester) async {
    final g = await open(tester);
    expect(g.canEmote, isTrue);
    expect(g.key(LogicalKeyboardKey.digit1), isTrue);
    expect(g.emote, Emote.cheer);
    // too soon for another one
    await frames(tester, 0.5);
    g.key(LogicalKeyboardKey.digit2);
    expect(g.emote, Emote.cheer);
    await shot(tester, '53_emote_cheer');
    // Cheer ends by itself
    await frames(tester, 1.4);
    expect(g.emote, isNull);
    await frames(tester, 0.2);
    // after the cooldown: Taunt
    g.key(LogicalKeyboardKey.digit2);
    expect(g.emote, Emote.taunt);
    await frames(tester, 0.8);
    await shot(tester, '54_emote_taunt');
    await frames(tester, 1.6);
    expect(g.emote, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Aura: lying down until you walk; the body comes back up', (tester) async {
    final g = await open(tester);
    final y0 = g.c.y;
    g.doEmote(Emote.aura);
    await frames(tester, 1.2);
    expect(g.emote, Emote.aura);
    expect(g.tilt.abs(), closeTo(math.pi / 2, 0.15), reason: 'lying on the back');
    expect(g.cd.y, closeTo(19, 3), reason: 'the body is down on the ground');
    // the head stays above the ground, the feet out to the side
    expect(g.pose!.head.y, greaterThan(5));
    expect((g.pose!.legs[0].e.x - g.cd.x).abs(), greaterThan(50));
    await shot(tester, '55_emote_aura');
    await frames(tester, 5);
    expect(g.emote, Emote.aura, reason: 'Aura lasts');
    // walking ends it, and you stand up
    expect(g.key(LogicalKeyboardKey.keyD), isTrue);
    await frames(tester, 0.6);
    g.keyUp(LogicalKeyboardKey.keyD);
    expect(g.emote, isNull);
    await frames(tester, 0.6);
    expect(g.cd.y, closeTo(y0, 2));
    expect(g.tilt.abs(), lessThan(0.1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('grabbing a hold ends an emote; climbing, there are none', (tester) async {
    final g = await open(tester);
    final r = g.route!;
    g.doEmote(Emote.taunt);
    final k = [
      for (var n = 0; n < r.holds.length; n++)
        if (r.holds[n].t == HoldType.jug && feasible(g.limbs, 0, attachPoint(r.holds[n], 0), g.c, g.climber) != null) n
    ].first;
    final from = g.w2s(g.limbEnd(0).x, g.limbEnd(0).y), to = attachPoint(r.holds[k], 0);
    g.pointerDown(1, from, false);
    expect(g.emote, isNull, reason: 'reaching for a hold ends it');
    for (var n = 1; n <= 8; n++) {
      g.pointerMove(1, Offset.lerp(from, g.w2s(to.x, to.y), n / 8)!);
      await frames(tester, 0.03);
    }
    g.pointerUp(1);
    await frames(tester, 2.2);
    expect(g.standOn, isNull);
    expect(g.canEmote, isFalse);
    g.key(LogicalKeyboardKey.digit1);
    expect(g.emote, isNull, reason: 'no emotes while climbing');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the HUD buttons: only while standing, and they emote', (tester) async {
    final g = await open(tester);
    await frames(tester, 0.4);
    await tester.tap(hudButton('CHEER'));
    await frames(tester, 0.1);
    expect(g.emote, Emote.cheer);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a climb alone has no emotes', (tester) async {
    final g = await open(tester, lanes: 1);
    expect(g.canEmote, isFalse);
    expect(g.key(LogicalKeyboardKey.digit1), isFalse);
    expect(g.emote, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  ClimberState st(int t, {Emote? emote, int start = 0}) => ClimberState(
        t: t,
        climber: 'kai',
        c: Pt(300, 107.5),
        tilt: 0,
        lookX: 0,
        lookUp: 0.5,
        ends: [Pt(269, 80), Pt(331, 80), Pt(288, 0), Pt(312, 0)],
        styles: const [HandStyle.open, HandStyle.open],
        kinds: const [HoldType.jug, HoldType.jug],
        footFree: const [false, false],
        standing: true,
        secs: 2,
        emote: emote,
        emoteStart: start,
      );

  test('an emote and its start go over the wire, after secs; older states have none', () {
    final raw = st(5000, emote: Emote.aura, start: 4200).encode();
    expect(raw.length, 20);
    expect((raw[18], raw[19]), (3, 4200));
    final back = ClimberState.decode(raw)!;
    expect((back.emote, back.emoteStart), (Emote.aura, 4200));
    expect(ClimberState.decode(st(5000).encode())!.emote, isNull);
    expect(st(5000).encode().length, 18, reason: 'no emote, nothing extra');
    // the server took out an emote sent too soon: its id is 0
    expect(ClimberState.decode([...raw]..[18] = 0)!.emote, isNull);
  });

  test('the others see an emote play, and hear it once', () {
    final o = RemoteClimber('p1', 'Kai');
    final events = <RemoteEvent?>[];
    for (var k = 0; k <= 30; k++) {
      o.add(st(k * 100, emote: k >= 5 ? Emote.aura : null, start: 500), k * 100);
    }
    for (var ms = 200; ms <= 3000; ms += 16) {
      events.add(o.update(ms, 0.016, ms / 1000));
    }
    expect(events.where((e) => e == RemoteEvent.emote).length, 1);
    expect(o.pose!.tilt.abs(), closeTo(math.pi / 2, 0.01), reason: 'lying, as they are');
    expect(o.pose!.c.y, closeTo(19, 1), reason: 'on the ground they stand on');
  });
}
