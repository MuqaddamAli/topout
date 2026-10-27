// Plays the game in a test: opens a route, moves hands and feet with real
// touch drags, looks around, falls, tries again, reaches the top and opens
// the Daily Wall. It also saves screenshots to build/screens/ so the art can
// be checked by eye (CI uploads them).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Atkinson', ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf']);
  await load('BigShoulders', ['BigShouldersDisplay-ExtraBold.ttf', 'BigShouldersDisplay-Black.ttf']);
  await load('PlexMono', ['IBMPlexMono-Medium.ttf']);
  // Real icons too, if the Flutter SDK is where we expect it.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
}

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
    final n = (seconds * 60).round();
    for (var k = 0; k < n; k++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
  }

  /// Drags a limb with a finger, the way a player does on a phone.
  Future<void> drag(WidgetTester tester, Game g, int limb, double wx, double wy, {String? shotName}) async {
    final e = g.limbEnd(limb);
    final start = g.w2s(e.x, e.y);
    final target = g.w2s(wx, wy);
    // on touch the aim sits above the finger, so the finger goes lower
    final offset = (64.0 > 30 * g.scale) ? 64.0 : 30 * g.scale;
    final end = target + Offset(0, offset);
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 16));
    for (var k = 1; k <= 12; k++) {
      await gesture.moveTo(Offset.lerp(start, end, k / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await frames(tester, 0.2);
    if (shotName != null) await shot(tester, shotName);
    await gesture.up();
    await frames(tester, 0.3);
  }

  int holdAt(Game g, double x, double y) => g.holds.indexWhere((h) => h.x == x && h.y == y);

  testWidgets('a full climb on a phone', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: true, sfxOn: true, enabled: false), today: DateTime(2026, 10, 27));
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 1.0);
    expect(find.text('ROUTES'), findsOneWidget);
    expect(game.phase, Phase.menu);
    await shot(tester, '01_menu');

    // open the first route from its card
    await tester.tap(find.text('FIRST WALL'), warnIfMissed: false);
    await frames(tester, 1.0);
    if (game.phase != Phase.climb) game.startRoute(game.routes[0]);
    await frames(tester, 0.5);
    expect(game.phase, Phase.climb);
    await shot(tester, '02_climb');

    // the lesson moves: right foot, left foot, left hand, right hand
    await drag(tester, game, 3, 210, 102, shotName: '03_drag_foot');
    expect(game.moves, 1);
    expect(game.limbs[3].h, holdAt(game, 210, 102));
    await drag(tester, game, 2, 152, 96);
    await drag(tester, game, 0, 138, 218, shotName: '04_drag_hand');
    await drag(tester, game, 1, 224, 230);
    expect(game.moves, 4);
    expect(game.limbs.map((l) => l.h).toList(),
        [holdAt(game, 138, 218), holdAt(game, 224, 230), holdAt(game, 152, 96), holdAt(game, 210, 102)]);
    await frames(tester, 0.5);
    await shot(tester, '05_after_moves');

    // undo takes back the last move
    await tester.tap(find.text('UNDO'));
    await frames(tester, 0.3);
    expect(game.moves, 4);
    expect(game.limbs[1].h, isNot(holdAt(game, 224, 230)));
    await drag(tester, game, 1, 224, 230);

    // look at the whole wall
    await tester.tap(find.text('LOOK'));
    await frames(tester, 1.2);
    expect(game.look, isTrue);
    await shot(tester, '06_look');
    await tester.tap(find.text('LOOK'));
    await frames(tester, 0.8);
    expect(game.look, isFalse);

    // the summit, seen from below
    game.camManual = game.route!.topY - 40;
    await frames(tester, 1.5);
    await shot(tester, '07_summit');
    game.recenter();
    await frames(tester, 1.0);

    // let go with both feet and run out of grip: a fall
    game.limbs[2].h = null;
    game.limbs[3].h = null;
    game.grip[0] = 1;
    await frames(tester, 2.5);
    expect(game.phase, Phase.fallCard);
    expect(find.text('YOU FELL'), findsOneWidget);
    await shot(tester, '08_fall');
    await tester.tap(find.text('Start again'));
    await frames(tester, 0.6);
    expect(game.phase, Phase.climb);

    // put both hands on the top: the climber stands up there
    final h = game.holds;
    final top = h.indexWhere((x) => x.t == HoldType.top);
    final feet = [
      for (var k = 0; k < h.length; k++)
        if (h[k].t == HoldType.jug && h[k].y > h[top].y - 120 && h[k].y < h[top].y - 40) k,
    ];
    game.limbs[0] = Limb(top, 160, h[top].y);
    game.limbs[1] = Limb(top, 200, h[top].y);
    game.limbs[2] = Limb(feet[0], h[feet[0]].x, h[feet[0]].y);
    game.limbs[3] = Limb(feet[1], h[feet[1]].x, h[feet[1]].y);
    game.c = Pt(180, h[top].y - 60);
    game.cd = game.c.copy();
    game.camY = game.c.y + 40;
    await frames(tester, 1.2);
    expect(game.phase, Phase.top);
    await shot(tester, '09_top_out');
    await frames(tester, 1.5);
    expect(game.screen, Screen.topCard);
    expect(find.text('Again'), findsOneWidget);
    await shot(tester, '10_top_card');

    // the Daily Wall, high up in the snow
    await tester.tap(find.text('Routes'));
    await frames(tester, 0.5);
    expect(game.phase, Phase.menu);
    game.startRoute(game.routes.last);
    await frames(tester, 0.5);
    expect(game.route!.endless, isTrue);
    await shot(tester, '11_daily');
    game.camManual = 2350;
    await frames(tester, 1.5);
    await shot(tester, '12_daily_snow');

    // pause
    game.recenter();
    await frames(tester, 0.3);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await frames(tester, 0.4);
    expect(game.phase, Phase.paused);
    await shot(tester, '13_pause');
    await tester.tap(find.text('Resume'));
    await frames(tester, 0.3);
    expect(game.phase, Phase.climb);

    // back to the title screen
    game.showMenu();
    await frames(tester, 0.5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('title screen on a wide screen', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: true, sfxOn: true, enabled: false), today: DateTime(2026, 10, 27));
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 1.0);
    await shot(tester, '20_desktop_menu');
    game.startRoute(game.routes[1]);
    await frames(tester, 1.0);
    await shot(tester, '21_desktop_climb');
    await tester.pumpWidget(const SizedBox());
  });
}
