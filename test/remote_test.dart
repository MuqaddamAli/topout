// Climbing together: the climber state sent over the network, playing other
// climbers back smoothly a little in the past, the list of other players, and
// a whole online climb with a fake server (start, sending, drawing, leaving).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/online.dart';
import 'package:topout/game/remote.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';

import 'fake_link.dart';
import 'fonts.dart';

ClimberState state(int t, {double x = 180, double y = 100, bool falling = false}) => ClimberState(
      t: t,
      climber: 'mei',
      c: Pt(x, y),
      tilt: 0.05,
      lookX: -1.2,
      lookUp: 0.5,
      ends: [Pt(x - 20, y + 60), Pt(x + 20, y + 62), Pt(x - 15, y - 80), Pt(x + 15, y - 78)],
      styles: [HandStyle.grip, HandStyle.open],
      kinds: [HoldType.crimp, HoldType.jug],
      footFree: [false, true],
      falling: falling,
      metres: 3.4,
    );

RoomPlayer player(String id, String name) => RoomPlayer(id: id, name: name, climber: 'ada', connected: true);

void main() {
  group('climber state', () {
    test('goes over the wire and back', () {
      final s = ClimberState(
        t: 123456,
        climber: 'kai',
        c: Pt(181.23, 1502.77),
        tilt: -0.1234,
        lookX: 2.345,
        lookUp: -0.6,
        ends: [Pt(1, 2), Pt(3, 4), Pt(5, 6), Pt(7, 8.05)],
        styles: [HandStyle.fist, HandStyle.open],
        kinds: [HoldType.sloper, HoldType.top],
        footFree: [true, false],
        falling: true,
        topped: true,
        metres: 14.06,
      );
      final wire = s.encode();
      expect(wire.length, 17);
      final b = ClimberState.decode(wire)!;
      expect(b.t, 123456);
      expect(b.climber, 'kai');
      expect(b.c.x, closeTo(181.2, 1e-9));
      expect(b.c.y, closeTo(1502.8, 1e-9));
      expect(b.tilt, closeTo(-0.123, 1e-9));
      expect(b.lookX, closeTo(2.35, 1e-9));
      expect(b.ends[3].y, closeTo(8.1, 1e-9));
      expect(b.styles, [HandStyle.fist, HandStyle.open]);
      expect(b.kinds, [HoldType.sloper, HoldType.top]);
      expect(b.footFree, [true, false]);
      expect(b.falling, isTrue);
      expect(b.topped, isTrue);
      expect(b.metres, closeTo(14.1, 1e-9));
    });

    test('a small state: well under 200 bytes as JSON', () {
      final json = state(987654321).encode().toString();
      expect(json.length, lessThan(200));
    });

    test('junk is not a state', () {
      for (final junk in <Object?>[
        null,
        'hello',
        [1, 2, 3],
        [0, 7, ...List.filled(15, 0)], // climber is not a name
        [0, 'ada', 'x', ...List.filled(14, 0)],
      ]) {
        expect(ClimberState.decode(junk), isNull, reason: '$junk');
      }
    });
  });

  group('playback', () {
    test('shows the climber 100 ms in the past, blended between two states', () {
      final r = RemoteClimber('a', 'Ann');
      // each state takes 50 ms to arrive
      r.add(state(1000, x: 100), 1050);
      r.add(state(1100, x: 200), 1150);
      expect(r.sample(1200)!.c.x, closeTo(150, 1e-9)); // 1200 - 50 - 100 = 1050: halfway
      expect(r.sample(1175)!.c.x, closeTo(125, 1e-9));
      // nothing newer yet: it waits at the newest state, it does not guess on
      expect(r.sample(5000)!.c.x, 200);
      expect(r.sample(0)!.c.x, 100);
    });

    test('a slow state does not drag the clock: the quickest trip counts', () {
      final r = RemoteClimber('a', 'Ann');
      r.add(state(0, x: 0), 80);
      r.add(state(100, x: 100), 150); // the quick one: 50 ms
      r.add(state(200, x: 200), 320);
      expect(r.sample(200)!.c.x, closeTo(50, 1e-9));
    });

    test('old and doubled states are dropped, and about a second is kept', () {
      final r = RemoteClimber('a', 'Ann');
      for (var t = 0; t <= 3000; t += 100) {
        r.add(state(t, x: t / 10), t + 40);
      }
      r.add(state(2500, x: -999), 3100);
      expect(r.states.last.t, 3000);
      expect(r.states.length, lessThanOrEqualTo(12));
      expect(r.states.last.t - r.states.first.t, lessThanOrEqualTo(1100));
    });

    test('a jump across the wall is not swept across', () {
      final a = state(0, y: 2000), b = state(100, y: 100);
      expect(ClimberState.lerp(a, b, 0.3).c.y, 100);
      final near = ClimberState.lerp(state(0, y: 100), state(100, y: 140), 0.25);
      expect(near.c.y, closeTo(110, 1e-9));
    });

    test('hand grip and hold switch halfway, positions blend', () {
      final a = state(0), b = ClimberState.decode(state(100, x: 190).encode())!;
      final s = ClimberState(
        t: 100,
        climber: 'mei',
        c: b.c,
        tilt: 0,
        lookX: 0,
        lookUp: 0,
        ends: b.ends,
        styles: [HandStyle.open, HandStyle.grip],
        kinds: [HoldType.jug, HoldType.crimp],
        footFree: [true, false],
      );
      expect(ClimberState.lerp(a, s, 0.4).styles, a.styles);
      expect(ClimberState.lerp(a, s, 0.6).styles, s.styles);
      expect(ClimberState.lerp(a, s, 0.5).ends[0].x, closeTo(165, 1e-9));
    });

    test('update builds a pose and swinging gear for the climber in the state', () {
      final r = RemoteClimber('a', 'Ann');
      r.add(state(0), 10);
      r.update(500, 1 / 60, 1);
      expect(r.pose, isNotNull);
      expect(r.gear, isNotNull);
      expect(r.look, isNotNull);
      expect(r.pose!.c.x, 180);
      // Mei's hands end where the state says
      expect(r.pose!.arms[0].e.y, greaterThan(r.pose!.c.y));
    });
  });

  group('other players', () {
    test('players come and go with the room list, without you', () {
      final o = RemoteClimbers();
      o.sync([player('me', 'Me'), player('b', 'Bo'), player('c', 'Cy')], 'me');
      expect(o.byId.keys, unorderedEquals(['b', 'c']));
      o.receive('b', state(0).encode(), 20);
      o.sync([player('me', 'Me'), player('b', 'Bobby')], 'me');
      expect(o.byId.keys, ['b']);
      expect(o.byId['b']!.name, 'Bobby');
      expect(o.byId['b']!.states.length, 1, reason: 'kept across list updates');
      o.receive('zz', state(0).encode(), 20); // not in the room
      o.receive('b', 'junk', 20);
      expect(o.byId.length, 1);
      o.clear();
      expect(o.isEmpty, isTrue);
    });
  });

  group('an online climb', () {
    late Game game;
    late FakeLink link;
    late Map<String, Object?> room;

    setUpAll(loadGameFonts);

    Future<void> frames(WidgetTester tester, double seconds) async {
      for (var k = 0; k < (seconds * 60).round(); k++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
    }

    Future<void> inLobby(WidgetTester tester, {String route = 'first', String dateKey = '2026-10-28'}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      game = Game(
        store: Store.memory(),
        audio: GameAudio(musicOn: false, sfxOn: false, enabled: false),
        netLink: () => link = FakeLink(),
      );
      game.setMode(Mode.casual);
      await tester.pumpWidget(TopoutApp(game: game));
      await tester.pump(const Duration(milliseconds: 100));
      game.showOnline();
      link.up!();
      room = roomJson(names: ['Me', 'Bo', 'Cy'])
        ..['route'] = route
        ..['dateKey'] = dateKey;
      link.answer = (e, d) => entered(room);
      await game.online.create(name: 'Me', route: route, mode: 'normal', dateKey: dateKey, climber: 'ada');
      await frames(tester, 0.2);
    }

    Future<void> started(WidgetTester tester) async {
      await game.online.start();
      link.push('room', {...room, 'started': true});
      link.push('started', {'startsIn': 3000});
      await frames(tester, 1.1);
      expect(find.text('Starting in 2'), findsOneWidget);
      expect(game.phase, Phase.menu);
      await frames(tester, 2);
    }

    Future<void> done(WidgetTester tester) async {
      game.online.close();
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('everyone starts the route together and sees the others', (tester) async {
      await inLobby(tester);
      expect(game.remotes.byId.keys, unorderedEquals(['p1', 'p2']));
      await started(tester);
      expect(game.phase, Phase.climb);
      expect(game.onlineClimb, isTrue);
      expect(game.route!.id, 'first');
      expect(game.mode, Mode.normal, reason: "the room's mode");

      // about 10 states a second go out
      final before = link.sent.where((s) => s.$1 == 'state').length;
      await frames(tester, 1);
      final sent = link.sent.where((s) => s.$1 == 'state').toList();
      expect(sent.length - before, inInclusiveRange(9, 11));
      final mine = ClimberState.decode(sent.last.$2)!;
      expect(mine.climber, game.climber.id);
      expect(mine.c.x, closeTo(game.cd.x, 0.5));
      expect(mine.ends.length, 4);

      // Bo climbs next to us; the game draws Bo (the painter runs in each pump)
      for (var k = 0; k < 10; k++) {
        link.push('state', ['p1', state(k * 100, x: 230, y: 100 + k * 2.0).encode()]);
        await frames(tester, 0.1);
      }
      final bo = game.remotes.byId['p1']!;
      expect(bo.pose, isNotNull);
      expect(bo.shown!.c.y, inInclusiveRange(100, 118));
      expect(game.remotes.byId['p2']!.pose, isNull, reason: 'Cy has not sent anything');
      expect(tester.takeException(), isNull);

      // Cy leaves the room
      link.push('room', (roomJson(names: ['Me', 'Bo'])..['started'] = true));
      await frames(tester, 0.1);
      expect(game.remotes.byId.keys, ['p1']);
      await done(tester);
    });

    testWidgets('the Daily Wall of the creator\'s day, even on another day here', (tester) async {
      await inLobby(tester, route: 'daily', dateKey: '2026-01-02');
      await started(tester);
      expect(game.route!.endless, isTrue);
      expect(game.route!.date, '2026-01-02');
      await done(tester);
    });

    testWidgets('Leave from the pause card goes back to the title screen with your own mode', (tester) async {
      await inLobby(tester);
      await started(tester);
      game.pause();
      await frames(tester, 0.4);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Routes'), findsNothing);
      await tester.tap(find.text('Leave'));
      await frames(tester, 0.4);
      expect(game.phase, Phase.menu);
      expect(game.screen, Screen.menu);
      expect(game.onlineClimb, isFalse);
      expect(game.remotes.isEmpty, isTrue);
      expect(game.mode, Mode.casual);
      expect(link.did('leave'), isTrue);
      await done(tester);
    });

    testWidgets('leaving during the countdown does not start a climb', (tester) async {
      await inLobby(tester);
      await game.online.start();
      link.push('started', {'startsIn': 3000});
      await frames(tester, 0.5);
      game.leaveOnline();
      await frames(tester, 3);
      expect(game.phase, Phase.menu);
      expect(game.onlineClimb, isFalse);
      await done(tester);
    });
  });
}
