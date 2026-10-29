// The Play online screen with a fake server: connecting, making and joining
// a room, the lobby, the errors, a creator who leaves, and Retry.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/online.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';

import 'fake_link.dart';
import 'fonts.dart';

void main() {
  test('the server: the live site finds the online one, local pages the one on their own machine', () {
    Uri page(String s) => Uri.parse(s);
    expect(serverFor('', page('https://topout-mu.vercel.app/')), onlineServer);
    expect(serverFor('', page('https://topout-git-feature-x.vercel.app/?perf')), onlineServer);
    expect(serverFor('', page('http://localhost:8080/')), 'http://localhost:3000');
    expect(serverFor('', page('http://127.0.0.1:8080/')), 'http://127.0.0.1:3000');
    expect(serverFor('', page('http://192.168.18.23:8080/')), 'http://192.168.18.23:3000');
    expect(serverFor('', page('http://10.0.0.7:8080/')), 'http://10.0.0.7:3000');
    expect(serverFor('', page('http://172.20.1.2:8080/')), 'http://172.20.1.2:3000');
    // set at build time, it always wins (a trailing / is dropped)
    expect(serverFor('https://other.example.com/', page('https://topout-mu.vercel.app/')), 'https://other.example.com');
    // apps on phones and desktops
    expect(serverFor('', null), onlineServer);
    expect(serverFor('', null, debug: true), 'http://localhost:3000');
  });

  late Game game;
  late List<FakeLink> links;
  FakeLink link() => links.last;

  Future<void> settle(WidgetTester tester) async {
    for (var k = 0; k < 30; k++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> tap(WidgetTester tester, String label) async {
    // buttons write their labels in capitals
    final f = find.byWidgetPredicate((w) => w is Text && (w.data == label || w.data == label.toUpperCase()), description: 'text "$label"').last;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  final shotKey = GlobalKey();

  /// Saves a screenshot to build/screens/, to check the look by eye.
  Future<void> shot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/screens')..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> open(WidgetTester tester) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    links = [];
    game = Game(
      store: Store.memory(),
      audio: GameAudio(musicOn: false, sfxOn: false, enabled: false),
      netLink: () => (links..add(FakeLink())).last,
    );
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await tester.pump(const Duration(milliseconds: 100));
    await tap(tester, 'Play online');
  }

  /// The server answers, and the player types a name.
  Future<void> connected(WidgetTester tester, {String name = 'Ada'}) async {
    link().up!();
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, name);
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    game.online.close();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('Play online connects, and says so while the server wakes up', (tester) async {
    await open(tester);
    expect(game.screen, Screen.online);
    expect(find.text('Connecting to server…'), findsOneWidget);
    expect(find.text('Connecting'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('waking up'), findsOneWidget);
    link().up!();
    await settle(tester);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Connecting to server…'), findsNothing);
    await done(tester);
  });

  testWidgets('a server that never answers shows Retry, which tries again', (tester) async {
    await open(tester);
    await tester.pump(const Duration(seconds: 61));
    await settle(tester);
    expect(find.text("Can't reach the server."), findsOneWidget);
    expect(link().closed, isTrue);
    await tap(tester, 'Retry');
    expect(links.length, 2);
    expect(find.text('Connecting to server…'), findsOneWidget);
    await done(tester);
  });

  testWidgets('make a room: code with Copy, the players, and Start for the creator', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await open(tester);
    await connected(tester, name: 'Ada');
    await shot(tester, '70_online_entry');
    link().answer = (e, d) => entered(roomJson());
    await tap(tester, 'Granite Steps');
    await tap(tester, 'No saves');
    await tap(tester, 'Create');
    final sent = link().last('create') as Map;
    expect(sent['name'], 'Ada');
    expect(sent['route'], 'steps');
    expect(sent['mode'], 'solo');
    // the creator's day decides the Daily Wall for the room
    expect(sent['dateKey'], game.todayKey);
    expect(game.playerName, 'Ada');

    expect(find.text('KXMP'), findsOneWidget);
    expect(find.text('1/8 players'), findsOneWidget);
    expect(find.text('CREATOR'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('One lane: two climbers side by side.'), findsOneWidget);
    expect(find.text('Ada · Lane 1, left'), findsOneWidget);
    await tap(tester, 'Copy');
    expect(copied, 'KXMP');
    expect(find.text('COPIED'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    link().push('room', roomJson(names: ['Ada', 'Bo', 'Cy', 'Di', 'Ed']));
    await settle(tester);
    expect(find.text('5/8 players'), findsOneWidget);
    expect(find.text('Ed'), findsOneWidget);
    await shot(tester, '71_online_lobby');
    // the lane each player will get, in the order they joined
    expect(find.text('3 lanes side by side, two climbers in each. Bridges join them.'), findsOneWidget);
    for (final lane in ['Lane 1, left', 'Lane 1, right', 'Lane 2, left', 'Lane 2, right', 'Lane 3, left']) {
      expect(find.text('Ada · $lane'), findsOneWidget, reason: lane);
    }

    // a climber picked in the lobby is sent to the room
    await tap(tester, 'KAI');
    expect(link().last('pick'), 'kai');

    expect(find.text('START · 0/5 READY'), findsOneWidget);
    await tap(tester, 'Start · 0/5 ready');
    expect(link().did('start'), isTrue);
    // from the start, the server's lanes are shown
    link().push('room', {
      ...roomJson(names: ['Ada', 'Bo'], started: true),
      'lanes': 1,
      'players': [
        {'id': 'me', 'name': 'Ada', 'climber': 'kai', 'connected': true, 'lane': 0, 'side': 0},
        {'id': 'p1', 'name': 'Bo', 'climber': 'ada', 'connected': true, 'lane': 0, 'side': 1},
      ],
    });
    link().push('started', {'startsIn': 3000, 'lanes': 1});
    await settle(tester);
    expect(find.text('Starting in 3'), findsOneWidget);
    expect(find.text('Kai · Lane 1, left'), findsOneWidget);
    expect(find.text('Ada · Lane 1, right'), findsOneWidget);
    expect(game.online.startsAt, isNotNull);
    await done(tester);
  });

  for (final error in ['Room not found', 'Room is full (8/8)', 'This climb has already started']) {
    testWidgets('joining can fail: $error', (tester) async {
      await open(tester);
      await connected(tester, name: 'Bo');
      link().answer = (e, d) => {'error': error};
      await tester.enterText(find.byType(TextField).last, 'kx mp');
      await settle(tester);
      expect(find.text('KXMP'), findsOneWidget); // capitals, letters only
      await tap(tester, 'Join');
      expect((link().last('join') as Map)['code'], 'KXMP');
      expect(find.text(error), findsOneWidget);
      expect(game.online.inRoom, isFalse);
      await done(tester);
    });
  }

  testWidgets('a player who joined by typing the code and Enter can walk with the keys', (tester) async {
    await open(tester);
    await connected(tester, name: 'Bo');
    final room = {
      ...roomJson(host: 'h', names: ['Host', 'Bo']),
      'players': [
        {'id': 'h', 'name': 'Host', 'climber': 'ada', 'connected': true},
        {'id': 'me', 'name': 'Bo', 'climber': 'ada', 'connected': true},
      ],
    };
    link().answer = (e, d) => entered(room);
    // the code field has the keyboard, and Enter joins
    await tester.tap(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'KXMP');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(game.online.inRoom, isTrue);
    link().push('room', {
      ...room,
      'started': true,
      'lanes': 1,
      'players': [
        {'id': 'h', 'name': 'Host', 'climber': 'ada', 'connected': true, 'lane': 0, 'side': 0},
        {'id': 'me', 'name': 'Bo', 'climber': 'ada', 'connected': true, 'lane': 0, 'side': 1},
      ],
    });
    link().push('started', {'startsIn': 1000, 'lanes': 1});
    for (var k = 0; k < 6; k++) {
      await settle(tester);
    }
    expect(game.phase, Phase.climb);
    expect(game.standOn, 0);
    final x0 = game.c.x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await settle(tester);
    await settle(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await settle(tester);
    expect(game.c.x, greaterThan(x0 + 20), reason: 'the keys reach the game, not the old text field');
    await done(tester);
  });

  testWidgets('a player who joined waits, and becomes the creator when the creator leaves', (tester) async {
    await open(tester);
    await connected(tester, name: 'Bo');
    link().answer = (e, d) => entered(roomJson(host: 'h', names: ['Host', 'Bo']), you: 'p1');
    await tester.enterText(find.byType(TextField).last, 'KXMP');
    await settle(tester);
    await tap(tester, 'Join');
    expect(find.text('Waiting for Host to start…'), findsOneWidget);
    expect(find.textContaining('START · '), findsNothing);

    link().push('room', roomJson(host: 'p1', names: ['Bo']));
    await settle(tester);
    expect(find.textContaining('START · '), findsOneWidget);
    expect(find.text('1/8 players'), findsOneWidget);
    await done(tester);
  });

  testWidgets('Leave goes back to the title screen and leaves the room', (tester) async {
    await open(tester);
    await connected(tester);
    link().answer = (e, d) => entered(roomJson());
    await tap(tester, 'Create');
    await tap(tester, 'Leave');
    expect(link().did('leave'), isTrue);
    expect(link().closed, isTrue);
    expect(game.screen, Screen.menu);
    expect(game.online.status, NetStatus.off);
    expect(find.text('ROUTES'), findsOneWidget);
    await done(tester);
  });

  testWidgets('after a short drop the game takes its place in the room again', (tester) async {
    await open(tester);
    await connected(tester);
    link().answer = (e, d) => entered(roomJson());
    await tap(tester, 'Create');
    link().down!();
    await settle(tester);
    expect(find.text('Connecting to server…'), findsOneWidget);
    link().up!();
    await settle(tester);
    expect(link().last('rejoin'), {'code': 'KXMP', 'token': 't'});
    expect(find.text('KXMP'), findsOneWidget);
    await done(tester);
  });
}
