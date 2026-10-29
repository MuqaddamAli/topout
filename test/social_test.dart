// The social extras of online play: quick chat (keys and the menu, the
// bubble, the cooldown), name tags and bubbles that stay readable in every
// pose and when players overlap, friend arrows, Watch after the top, the
// lobby's ready check, and coming back after a dropped connection.
// Screenshots go to build/screens/ (6x_*).
import 'dart:io';
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

import 'fake_link.dart';
import 'fonts.dart';

void main() {
  final shotKey = GlobalKey();
  late Game game;
  late FakeLink link;

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

  List<Map<String, Object?>> players(int n, int at, {List<bool>? ready, bool lanes = true}) => [
        for (var k = 0; k < n; k++)
          {
            'id': k == at ? 'me' : 'p$k',
            'name': ['Ada', 'Bo', 'Cy', 'Dee'][k],
            'climber': ['ada', 'rio', 'mei', 'kai'][k],
            'connected': true,
            'ready': ready?[k] ?? false,
            if (lanes) 'lane': k ~/ 2,
            if (lanes) 'side': k % 2,
          },
      ];

  Map<String, Object?> room(int n, {bool started = true, List<bool>? ready}) => {
        ...roomJson(host: 'me', names: const ['Ada']),
        'started': started,
        'round': started ? 1 : 0,
        if (started) 'lanes': lanesFor(n),
        'players': players(n, 0, ready: ready, lanes: started),
      };

  /// You (the creator) and [n] - 1 others in the lobby.
  Future<void> lobby(WidgetTester tester, int n) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    game = Game(
      store: Store.memory(),
      audio: GameAudio(musicOn: false, sfxOn: false, enabled: false),
      netLink: () => link = FakeLink(),
      today: DateTime(2026, 10, 27),
    );
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 0.1);
    game.showOnline();
    link.up!();
    link.answer = (e, d) => entered(room(n, started: false));
    await game.online.create(name: 'Ada', route: 'first', mode: 'normal', dateKey: '2026-10-27', climber: 'ada');
    await frames(tester, 0.2);
  }

  Future<void> climbing(WidgetTester tester, int n) async {
    await lobby(tester, n);
    link.push('room', room(n));
    link.push('started', {'startsIn': 300, 'lanes': lanesFor(n), 'round': 1});
    await frames(tester, 0.6);
    expect(game.phase, Phase.climb);
    game.hideTip();
  }

  Future<void> done(WidgetTester tester) async {
    game.online.close();
    await tester.pumpWidget(const SizedBox());
  }

  /// Player [id] stands at [x] on the ground (or the top at [y]), maybe in
  /// an emote or saying something, as their states show.
  Future<void> others(WidgetTester tester, Map<String, ({double x, double y, Emote? emote, int? chat})> who, {double secs = 0.6}) async {
    for (var k = 0; k < (secs * 10).round(); k++) {
      final t = 1000 + k * 100;
      for (final MapEntry(key: id, value: o) in who.entries) {
        link.push('state', [
          id,
          ClimberState(
            t: t,
            climber: 'rio',
            c: Pt(o.x, o.y + 107.5),
            tilt: 0,
            lookX: 0,
            lookUp: 0.5,
            ends: [Pt(o.x - 31, o.y + 80), Pt(o.x + 31, o.y + 80), Pt(o.x - 12, o.y), Pt(o.x + 12, o.y)],
            styles: const [HandStyle.open, HandStyle.open],
            kinds: const [HoldType.jug, HoldType.jug],
            footFree: const [false, false],
            standing: true,
            metres: o.y / 100,
            secs: k / 10,
            emote: o.emote,
            emoteStart: 1000,
            chat: o.chat,
            chatStart: 1000,
          ).encode(),
        ]);
      }
      await frames(tester, 0.1);
    }
  }

  testWidgets('quick chat: Q W E R, a bubble for 3 s, a cooldown, and it goes out with the state', (tester) async {
    await climbing(tester, 2);
    expect(game.key(LogicalKeyboardKey.keyE), isTrue);
    expect(game.chatShown, 'Nice!');
    await frames(tester, 0.3);
    final st = ClimberState.decode(link.sent.lastWhere((e) => e.$1 == 'state').$2)!;
    expect(st.chat, 2);
    expect(st.emote, isNull);
    // too soon for another
    game.key(LogicalKeyboardKey.keyQ);
    expect(game.chatShown, 'Nice!');
    await frames(tester, 1.9);
    game.key(LogicalKeyboardKey.keyQ);
    expect(game.chatShown, 'Wait for me!');
    await frames(tester, 3.1);
    expect(game.chatShown, isNull, reason: 'the bubble is gone after 3 s');
    await frames(tester, 0.3);
    expect(ClimberState.decode(link.sent.lastWhere((e) => e.$1 == 'state').$2)!.chat, isNull);
    await done(tester);
  });

  testWidgets('the chat menu on touch, and chatting while climbing', (tester) async {
    await climbing(tester, 2);
    await tester.tap(find.descendant(of: find.byType(Hud), matching: find.text('Chat')));
    await frames(tester, 0.3);
    expect(game.chatOpen, isTrue);
    await tester.tap(find.text('Over here!  R'));
    await frames(tester, 0.2);
    expect(game.chatShown, 'Over here!');
    expect(game.chatOpen, isFalse);
    // grab a hold: climbing, you can still chat
    final r = game.route!;
    final k = [
      for (var n = 0; n < r.holds.length; n++)
        if (r.holds[n].t == HoldType.jug && feasible(game.limbs, 0, attachPoint(r.holds[n], 0), game.c, game.climber) != null) n
    ].first;
    final from = game.w2s(game.limbEnd(0).x, game.limbEnd(0).y), to = attachPoint(r.holds[k], 0);
    game.pointerDown(1, from, false);
    for (var n = 1; n <= 8; n++) {
      game.pointerMove(1, Offset.lerp(from, game.w2s(to.x, to.y), n / 8)!);
      await frames(tester, 0.03);
    }
    game.pointerUp(1);
    await frames(tester, 2.2);
    expect(game.standOn, isNull);
    game.say(1);
    expect(game.chatShown, 'Come on!');
    await done(tester);
  });

  testWidgets('tags and bubbles stay readable: lying down, and with players in the same spot', (tester) async {
    await climbing(tester, 4);
    final x = game.c.x;
    game.say(0);
    await others(tester, {
      'p1': (x: x + 90, y: 0, emote: Emote.aura, chat: 3),
      'p2': (x: x - 70, y: 0, emote: null, chat: 1),
      'p3': (x: x - 66, y: 0, emote: Emote.cheer, chat: 2),
    });
    expect(tester.takeException(), isNull);
    await shot(tester, '60_tags_and_bubbles');
    await done(tester);
  });

  testWidgets('friend arrows: a player out of view gets a small arrow with name and height', (tester) async {
    await climbing(tester, 3);
    await others(tester, {
      'p1': (x: game.c.x + 900, y: 0, emote: null, chat: null),
      'p2': (x: game.c.x, y: 600, emote: null, chat: null),
    });
    expect(tester.takeException(), isNull);
    await shot(tester, '61_friend_arrows');
    await done(tester);
  });

  testWidgets('Watch: after the top, follow the others one by one (Tab too); walking brings you back', (tester) async {
    await climbing(tester, 3);
    expect(game.canWatch, isFalse, reason: 'only once you topped out');
    await others(tester, {
      'p1': (x: 500, y: 0, emote: null, chat: null),
      'p2': (x: 900, y: 0, emote: null, chat: null),
    });
    final r = game.route!, top = r.holds.indexWhere((h) => h.t == HoldType.top);
    game.standOn = null;
    game.limbs[0]
      ..h = top
      ..y = r.topY;
    game.limbs[1]
      ..h = top
      ..y = r.topY;
    await frames(tester, 1.6);
    expect(game.toppedOut, isTrue);
    expect(game.canWatch, isTrue);
    game.watchNext();
    expect(game.watching, 'p1');
    await frames(tester, 1.5);
    expect(game.camX, closeTo(game.camXFor(500), 15));
    expect(game.camY, lessThan(300), reason: 'down by Bo on the ground');
    expect(find.text('Watching Bo'), findsOneWidget);
    expect(game.key(LogicalKeyboardKey.tab), isTrue);
    expect(game.watching, 'p2');
    game.key(LogicalKeyboardKey.tab);
    expect(game.watching, isNull, reason: 'after the last one, back to you');
    game.watchNext();
    expect(game.watching, 'p1');
    // walking brings the camera back to you
    game.key(LogicalKeyboardKey.keyA);
    await frames(tester, 0.3);
    game.keyUp(LogicalKeyboardKey.keyA);
    expect(game.watching, isNull);
    await done(tester);
  });

  testWidgets('the ready check: Ready in the lobby, everyone sees who is ready, the creator sees how many', (tester) async {
    await lobby(tester, 3);
    expect(find.text('START · 0/3 READY'), findsOneWidget);
    await tester.ensureVisible(find.text("I'M READY"));
    await tester.tap(find.text("I'M READY"));
    await frames(tester, 0.2);
    expect(link.last('ready'), isTrue);
    link.push('room', room(3, started: false, ready: [true, false, true]));
    await frames(tester, 0.3);
    expect(find.text('START · 2/3 READY'), findsOneWidget);
    expect(find.text('READY'), findsNWidgets(2));
    expect(find.text('READY ✓'), findsOneWidget);
    // tapping again: not ready
    await tester.tap(find.text('READY ✓'));
    await frames(tester, 0.2);
    expect(link.last('ready'), isFalse);
    await done(tester);
  });

  testWidgets('a dropped connection: back in the room where you were, not at the spawn', (tester) async {
    await climbing(tester, 2);
    // walk a little, then reach the top
    game.key(LogicalKeyboardKey.keyD);
    await frames(tester, 1);
    game.keyUp(LogicalKeyboardKey.keyD);
    final r = game.route!, top = r.holds.indexWhere((h) => h.t == HoldType.top);
    game.standOn = null;
    game.limbs[0]
      ..h = top
      ..y = r.topY;
    game.limbs[1]
      ..h = top
      ..y = r.topY;
    // the connection drops just as you top out: the time cannot get through
    link.down!();
    await frames(tester, 2);
    expect(game.toppedOut, isTrue);
    final finish = game.myFinish!, x = game.c.x, grip = game.grip[0];
    final sentBefore = link.sent.where((e) => e.$1 == 'topped').length;
    // back within the grace time: the same place in the room
    link.answer = (e, d) => entered(room(2));
    link.up!();
    await frames(tester, 0.5);
    expect(link.did('rejoin'), isTrue);
    expect(game.phase, Phase.climb);
    expect(game.onlineClimb, isTrue);
    expect(game.toppedOut, isTrue);
    expect(game.myFinish, finish);
    expect(game.c.x, closeTo(x, 1), reason: 'where you were, not at the spawn');
    expect(game.grip[0], greaterThanOrEqualTo(grip));
    expect(game.standOn, top);
    // the time is said again, as the room did not have it
    expect(link.sent.where((e) => e.$1 == 'topped').length, sentBefore + 1);
    expect(link.last('topped'), finish);
    await done(tester);
  });

  testWidgets('a climb alone has no chat, no arrows and no Watch', (tester) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final g = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false));
    await tester.pumpWidget(TopoutApp(game: g));
    g.startRoute(g.routes.first);
    await frames(tester, 0.3);
    expect(g.canChat, isFalse);
    expect(g.key(LogicalKeyboardKey.keyQ), isFalse);
    expect(g.chatShown, isNull);
    expect(g.canWatch, isFalse);
    expect(find.descendant(of: find.byType(Hud), matching: find.text('Chat')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('a chat phrase over the wire: after the emote numbers (0 0 without one); junk is none', () {
    ClimberState st({Emote? emote, int? chat}) => ClimberState(
          t: 10,
          climber: 'ada',
          c: Pt(1, 2),
          tilt: 0,
          lookX: 0,
          lookUp: 0,
          ends: [Pt(0, 0), Pt(0, 0), Pt(0, 0), Pt(0, 0)],
          styles: const [HandStyle.open, HandStyle.open],
          kinds: const [HoldType.jug, HoldType.jug],
          footFree: const [false, false],
          secs: 1,
          emote: emote,
          emoteStart: 7,
          chat: chat,
          chatStart: 9,
        );
    final raw = st(chat: 3).encode();
    expect(raw.sublist(18), [0, 0, 4, 9]);
    final back = ClimberState.decode(raw)!;
    expect((back.chat, back.chatStart, back.emote), (3, 9, null));
    expect(ClimberState.decode(st(emote: Emote.taunt, chat: 0).encode())!.emote, Emote.taunt);
    expect(ClimberState.decode([...raw]..[20] = 9)!.chat, isNull);
    expect(ClimberState.decode([...raw]..[20] = 0)!.chat, isNull, reason: 'taken out by the server');
  });
}
