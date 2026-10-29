// Climbing together: the climber state sent over the network, playing other
// climbers back smoothly a little in the past, the list of other players, and
// a whole online climb with a fake server (start, sending, drawing, leaving).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/online.dart';
import 'package:topout/game/remote.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';
import 'package:topout/ui/cards.dart';
import 'package:topout/ui/hud.dart';

import 'fake_link.dart';
import 'fonts.dart';

ClimberState state(int t, {double x = 180, double y = 100, bool falling = false, bool topped = false, double metres = 3.4, double? secs}) =>
    ClimberState(
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
      topped: topped,
      metres: metres,
      secs: secs,
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

    test('a state goes out as one argument, not one per number', () {
      // the Socket.io client spreads a list into separate arguments
      final wire = state(5).encode();
      expect(SocketLink.payload(wire), [wire]);
      expect(SocketLink.payload({'code': 'KXMP'}), {'code': 'KXMP'});
      expect(SocketLink.payload(null), isNull);
    });

    test('the seconds since the start ride along, and older states without them still read', () {
      final wire = state(1, secs: 75.04).encode();
      expect(wire.length, 18);
      expect(ClimberState.decode(wire)!.secs, closeTo(75.0, 1e-9));
      final old = state(1).encode();
      expect(old.length, 17);
      expect(ClimberState.decode(old)!.secs, isNull);
    });

    test('1st, 2nd, 3rd, 4th, 11th, 21st', () {
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(ordinal), ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '101st']);
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

    /// A started room of [n] players where you are player [at] (0 is the
    /// creator), with the lanes and sides the server gives at the start.
    Map<String, Object?> laneRoom(int n, int at, {String route = 'first'}) {
      final ids = [for (var k = 0; k < n; k++) k == at ? 'me' : 'p$k'];
      return {
        ...roomJson(host: ids[0], names: [for (var k = 0; k < n; k++) 'P$k'], started: true),
        'route': route,
        'lanes': lanesFor(n),
        'players': [
          for (var k = 0; k < n; k++)
            {'id': ids[k], 'name': 'P$k', 'climber': 'ada', 'connected': true, 'lane': k ~/ 2, 'side': k % 2},
        ],
      };
    }

    Future<void> startIn(WidgetTester tester, Map<String, Object?> started) async {
      await inLobby(tester, route: '${started['route']}');
      link.push('room', started);
      link.push('started', {'startsIn': 3000, 'lanes': started['lanes']});
      await frames(tester, 3.2);
      expect(game.phase, Phase.climb);
    }

    for (final (n, at) in [(2, 0), (2, 1), (5, 2), (8, 7)]) {
      testWidgets('$n players, you are number ${at + 1}: your lane and side, standing at your spawn', (tester) async {
        await startIn(tester, laneRoom(n, at));
        final r = game.route!, lane = at ~/ 2, side = at % 2;
        expect(r.lanes.length, lanesFor(n));
        expect(game.spawn, same(r.lanes[lane].spawns[side]));
        final s = game.spawn!;
        expect(game.standOn, 0, reason: 'standing on the ground');
        expect([game.limbs[0].h, game.limbs[1].h], [null, null], reason: 'both hands free');
        expect([game.limbs[2].h, game.limbs[3].h], [0, 0], reason: 'both feet on the ground');
        expect(game.c.x, closeTo(s.x, 0.5));
        expect(game.camX, closeTo(game.camXFor(game.cd.x), 30));
        expect(game.chalked, isEmpty);
        // the other spawn of the lane is far enough away not to overlap (a body is about 40 wide)
        expect((r.lanes[lane].spawns[1 - side].x - game.c.x).abs(), greaterThan(100));
        await done(tester);
      });
    }

    testWidgets('the same wall for everyone, and it keeps its lanes when someone leaves', (tester) async {
      await startIn(tester, laneRoom(5, 1));
      final r = game.route!;
      // the others build exactly this wall from the same room
      final again = game.roomWall(RoomView.fromJson(laneRoom(5, 3)));
      expect([for (final h in again.holds) (h.t, h.x, h.y, h.x2)], [for (final h in r.holds) (h.t, h.x, h.y, h.x2)]);
      // two players leave: 3 left, but the wall and your place stay
      link.push('room', {...laneRoom(5, 1), 'players': (laneRoom(5, 1)['players'] as List).sublist(0, 3)});
      await frames(tester, 0.3);
      expect(identical(game.route, r), isTrue);
      expect(r.lanes.length, 3);
      expect(game.spawn!.lane, 0);
      expect(game.spawn!.side, 1);
      await done(tester);
    });

    /// A hold in lane [lane] that hand [i] can grab from where the climber is.
    int reachable(ClimbRoute r, Lane lane, int i) => [
          for (var k = 0; k < r.holds.length; k++)
            if (r.holds[k].t == HoldType.jug && r.holds[k].x > lane.x0 && r.holds[k].x < lane.x1 &&
                feasible(game.limbs, i, attachPoint(r.holds[k], i), game.c, game.climber) != null)
              k
        ].first;

    /// Drags hand [i] to hold [k], straight to the game (a room message may
    /// cover that part of the screen).
    Future<void> grab(WidgetTester tester, int i, int k) async {
      final from = game.w2s(game.limbEnd(i).x, game.limbEnd(i).y), to = attachPoint(game.holds[k], i);
      game.pointerDown(1, from, false);
      for (var n = 1; n <= 8; n++) {
        game.pointerMove(1, Offset.lerp(from, game.w2s(to.x, to.y), n / 8)!);
        await frames(tester, 0.03);
      }
      game.pointerUp(1);
      await frames(tester, 0.4);
    }

    /// Feet off and no grip left: a fall, then the fall card.
    Future<void> fallOff(WidgetTester tester) async {
      game.limbs[2].h = null;
      game.limbs[3].h = null;
      game.grip[0] = game.grip[1] = 1;
      await frames(tester, 2.5);
      expect(game.phase, Phase.fallCard);
    }

    testWidgets('undo, a fall and Try again keep you in your own lane', (tester) async {
      await startIn(tester, laneRoom(4, 3));
      final r = game.route!, s = game.spawn!, lane = r.lanes[1];
      expect((s.lane, s.side), (1, 1));
      final start = game.c.copy();
      // a grab from standing starts the climb; undo stands you up again
      final k = reachable(r, lane, 0);
      await grab(tester, 0, k);
      expect(game.limbs[0].h, k);
      expect(game.standOn, isNull);
      game.undo();
      await frames(tester, 0.4);
      expect(game.standOn, 0);
      expect(game.limbs[0].h, isNull);
      expect(game.c.x, closeTo(start.x, 1));
      // climb, let go and fall: Try again puts you back where you stood, in lane 2
      await grab(tester, 0, k);
      await fallOff(tester);
      game.retry();
      await frames(tester, 0.4);
      expect(game.phase, Phase.climb);
      expect(game.standOn, 0);
      expect(game.c.x, closeTo(start.x, 1));
      expect(r.laneAt(game.c.x), lane);
      // starting again from the ground: the same spawn
      game.restart();
      await frames(tester, 0.2);
      expect(game.standOn, 0);
      expect(game.c.x, closeTo(start.x, 1));
      await done(tester);
    });

    testWidgets('on the Daily Wall, starting again after a fall is at your spawn too', (tester) async {
      await startIn(tester, laneRoom(3, 2, route: 'daily'));
      final r = game.route!, s = game.spawn!;
      expect(r.endless, isTrue);
      expect((r.lanes.length, s.lane, s.side), (2, 1, 0));
      final start = game.c.copy();
      await grab(tester, 1, reachable(r, r.lanes[1], 1));
      await fallOff(tester);
      game.retry();
      await frames(tester, 0.3);
      expect(game.standOn, 0);
      expect(game.c.x, closeTo(start.x, 1));
      await done(tester);
    });

    testWidgets('leaving the room forgets the spawn: alone you start on the start holds again', (tester) async {
      await startIn(tester, laneRoom(2, 1));
      game.goBack();
      await frames(tester, 0.4);
      expect(game.spawn, isNull);
      game.startRoute(game.routes.first);
      expect(game.limbs.take(2).map((l) => l.h), game.routes.first.startHands);
      await done(tester);
    });

    testWidgets('an online climb is not saved in the records', (tester) async {
      await inLobby(tester);
      await started(tester);
      expect(game.keepsRecords, isFalse);
      final r = game.route!, top = r.holds.indexWhere((h) => h.t == HoldType.top);
      game.maxY = 500;
      game.standOn = null;
      game.limbs[0].h = top;
      game.limbs[1].h = top;
      await frames(tester, 0.3);
      expect(game.toppedOut, isTrue);
      await frames(tester, 2.2);
      expect(game.screen, Screen.hud, reason: 'online the climb goes on at the top');
      game.goBack();
      await frames(tester, 0.4);
      final rec = game.records;
      expect((rec.tops, rec.falls, rec.catches, rec.metres, rec.secs), (0, 0, 0, 0.0, 0.0));
      expect(game.bestTime(r), isNull);
      expect(game.bestHeight(r), 0);
      // a climb alone afterwards counts again
      game.startRoute(game.routes.first);
      expect(game.keepsRecords, isTrue);
      await done(tester);
    });

    /// Puts both hands on the top: a top-out.
    Future<int> reachTop(WidgetTester tester) async {
      final r = game.route!, top = r.holds.indexWhere((h) => h.t == HoldType.top);
      game.standOn = null;
      game.limbs[0]
        ..h = top
        ..x = game.c.x - 20
        ..y = r.topY;
      game.limbs[1]
        ..h = top
        ..x = game.c.x + 20
        ..y = r.topY;
      game.c = Pt(game.c.x, r.topY - 60);
      game.cd = game.c.copy();
      await frames(tester, 0.2);
      return top;
    }

    /// The room after its climb: everyone's times (null: did not finish).
    Map<String, Object?> endedRoom(int n, int at, List<double?> finish) {
      final room = laneRoom(n, at);
      return {
        ...room,
        'ended': true,
        'round': 1,
        'players': [
          for (final (k, p) in (room['players'] as List).indexed) {...(p as Map), 'finish': finish[k]}
        ],
      };
    }

    testWidgets('the top: your time stops, the room hears it, and you stand and walk on the top', (tester) async {
      await startIn(tester, laneRoom(4, 0));
      final r = game.route!;
      final top = await reachTop(tester);
      expect(game.toppedOut, isTrue);
      expect(game.myFinish, isNotNull);
      expect(link.last('topped'), closeTo(game.myFinish!, 0.01));
      expect(link.sent.where((e) => e.$1 == 'topped').length, 1);
      final t0 = game.time;
      await frames(tester, 1.6);
      expect(game.time, t0, reason: 'your time stopped');
      expect(game.screen, Screen.hud, reason: 'no top card: the climb goes on');
      expect(game.standOn, top);
      expect(game.pillText, startsWith('Topped out'));
      final mine = ClimberState.decode(link.sent.lastWhere((e) => e.$1 == 'state').$2)!;
      expect((mine.topped, mine.standing), (true, true));
      // the top runs across both lanes
      expect(game.key(LogicalKeyboardKey.keyD), isTrue);
      await frames(tester, 12);
      game.keyUp(LogicalKeyboardKey.keyD);
      expect(r.laneAt(game.c.x).index, 1);
      expect(game.c.x, closeTo(r.holds[top].x2! - standMargin, 0.5));
      expect(link.sent.where((e) => e.$1 == 'topped').length, 1, reason: 'the time goes out once');
      await done(tester);
    });

    testWidgets('when the room ends everyone sees the results; the creator plays again', (tester) async {
      await startIn(tester, laneRoom(3, 0));
      await reachTop(tester);
      await frames(tester, 1.4);
      // the creator, waiting at the top, can end it from the HUD
      await tester.tap(find.descendant(of: find.byType(Hud), matching: find.text('End climb')));
      await frames(tester, 0.2);
      expect(link.did('end'), isTrue);
      link.push('room', endedRoom(3, 0, [game.myFinish, null, 80.5]));
      await frames(tester, 0.5);
      expect(game.screen, Screen.results);
      expect(find.text('RESULTS'), findsOneWidget);
      expect(find.text(fmtTime(game.myFinish!)), findsWidgets);
      expect(find.text(fmtTime(80.5)), findsWidgets);
      expect(find.textContaining('did not finish'), findsOneWidget);
      expect(find.text('PLAY AGAIN'), findsOneWidget);
      expect(find.text('LEAVE'), findsOneWidget);
      await tester.tap(find.text('PLAY AGAIN'));
      await frames(tester, 0.2);
      expect(link.did('again'), isTrue);
      // the server starts the next climb: a countdown, then everyone from the spawns
      link.push('started', {'startsIn': 1000, 'lanes': 2, 'round': 2});
      link.push('room', {...laneRoom(3, 0), 'round': 2});
      await frames(tester, 0.3);
      expect(find.text('Starting in 1'), findsOneWidget);
      await frames(tester, 1.2);
      expect(game.screen, Screen.hud);
      expect(game.toppedOut, isFalse);
      expect(game.myFinish, isNull);
      expect(game.standOn, 0);
      expect(game.c.x, closeTo(game.spawn!.x, 0.5));
      expect(game.time, lessThan(1), reason: 'a fresh clock');
      await done(tester);
    });

    testWidgets('the results for someone else: waiting for the creator, and Leave', (tester) async {
      await startIn(tester, laneRoom(2, 1));
      link.push('room', endedRoom(2, 1, [50, null]));
      await frames(tester, 0.5);
      expect(game.screen, Screen.results);
      expect(find.text('PLAY AGAIN'), findsNothing);
      expect(find.text('Waiting for P0 to play again…'), findsOneWidget);
      await tester.tap(find.text('LEAVE'));
      await frames(tester, 0.5);
      expect(game.onlineClimb, isFalse);
      expect(game.screen, Screen.menu);
      await done(tester);
    });

    testWidgets('End climb: on the pause card for the creator', (tester) async {
      await startIn(tester, laneRoom(2, 0));
      game.pause();
      await frames(tester, 0.4);
      // before the top the HUD has no End climb (it cannot be tapped)
      await tester.tap(find.descendant(of: find.byType(PauseCard), matching: find.text('END CLIMB')));
      await frames(tester, 0.2);
      expect(link.did('end'), isTrue);
      await done(tester);
    });

    testWidgets('End climb: not on the pause card for the others', (tester) async {
      await startIn(tester, laneRoom(2, 1));
      game.pause();
      await frames(tester, 0.4);
      expect(find.descendant(of: find.byType(PauseCard), matching: find.text('END CLIMB')), findsNothing);
      await done(tester);
    });

    testWidgets('Leave from the pause card goes back to the title screen with your own mode', (tester) async {
      await inLobby(tester);
      await started(tester);
      game.pause();
      await frames(tester, 0.4);
      expect(find.text('LEAVE'), findsOneWidget);
      expect(find.text('ROUTES'), findsNothing);
      await tester.tap(find.text('LEAVE'));
      await frames(tester, 0.4);
      expect(game.phase, Phase.menu);
      expect(game.screen, Screen.menu);
      expect(game.onlineClimb, isFalse);
      expect(game.remotes.isEmpty, isTrue);
      expect(game.mode, Mode.casual);
      expect(link.did('leave'), isTrue);
      await done(tester);
    });

    testWidgets('online, the game keeps going when the window loses focus', (tester) async {
      await inLobby(tester);
      await started(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await frames(tester, 0.2);
      expect(game.phase, Phase.climb);
      final before = link.sent.where((s) => s.$1 == 'state').length;
      await frames(tester, 0.5);
      expect(link.sent.where((s) => s.$1 == 'state').length, greaterThan(before));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await done(tester);
    });

    testWidgets('alone, losing focus still pauses as before', (tester) async {
      await inLobby(tester);
      game.leaveOnline();
      game.startRoute(game.routes.first);
      await frames(tester, 0.2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await frames(tester, 0.2);
      expect(game.phase, Phase.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await done(tester);
    });

    String? toastNow() => game.toastVisible ? game.toastText : null;

    /// Sends a state for player [id] and lets it play.
    Future<void> send(WidgetTester tester, String id, int t,
        {double metres = 1, bool falling = false, bool topped = false, double? secs}) async {
      link.push('state', [id, state(t, metres: metres, falling: falling, topped: topped, secs: secs).encode()]);
      await frames(tester, 0.3);
    }

    testWidgets('the heights list: everyone, highest first, the finished at the top in order', (tester) async {
      await inLobby(tester);
      await started(tester);
      await send(tester, 'p1', 0, metres: 4.2);
      await send(tester, 'p2', 0, metres: 7.5);
      await frames(tester, 0.3);
      expect(game.standings.map((x) => x.name), ['Cy', 'Bo', 'Me']);
      expect(game.standings.last.you, isTrue);
      expect(find.text('7.5 m'), findsOneWidget);
      expect(find.text('4.2 m'), findsOneWidget);
      expect(find.text('0.0 m'), findsOneWidget);

      // Bo tops out first, then Cy: they go to the top of the list in that order
      await send(tester, 'p1', 3000, metres: 5.1, topped: true, secs: 95);
      expect(toastNow(), 'Bo topped out! 1st · 1:35');
      await send(tester, 'p2', 6000, metres: 5.1, topped: true, secs: 131);
      expect(toastNow(), 'Cy topped out! 2nd · 2:11');
      await frames(tester, 0.3);
      expect(game.standings.map((x) => x.name), ['Bo', 'Cy', 'Me']);
      expect(find.text('1:35'), findsOneWidget);
      await done(tester);
    });

    testWidgets('messages: someone falls, drops out, comes back and leaves', (tester) async {
      await inLobby(tester);
      await started(tester);
      await send(tester, 'p1', 0, metres: 2);
      await send(tester, 'p1', 1000, metres: 2, falling: true);
      expect(toastNow(), 'Bo fell');
      // one message per fall, not one per state
      game.toastText = null;
      await send(tester, 'p1', 1100, falling: true);
      expect(toastNow(), isNull);

      final players = (room['players'] as List).cast<Map<String, Object?>>();
      link.push('room', {...room, 'started': true, 'players': [players[0], {...players[1], 'connected': false}, players[2]]});
      await frames(tester, 0.1);
      expect(toastNow(), 'Bo lost the connection');
      link.push('room', {...room, 'started': true});
      await frames(tester, 0.1);
      expect(toastNow(), 'Bo is back');
      link.push('room', {...room, 'started': true, 'players': [players[0], players[2]]});
      await frames(tester, 0.1);
      expect(toastNow(), 'Bo left');
      await done(tester);
    });

    testWidgets('the lobby says who joined and who left', (tester) async {
      await inLobby(tester);
      final players = (room['players'] as List).cast<Map<String, Object?>>();
      link.push('room', {
        ...room,
        'players': [...players, {'id': 'p3', 'name': 'Dee', 'climber': 'kai', 'connected': true}],
      });
      await frames(tester, 0.2);
      expect(toastNow(), 'Dee joined');
      expect(find.text('Dee joined'), findsOneWidget);
      link.push('room', {...room, 'players': [players[0], players[1]]});
      await frames(tester, 0.2);
      expect(toastNow(), 'Cy and Dee left');
      await done(tester);
    });

    testWidgets('at the top: the finishing order and times', (tester) async {
      await inLobby(tester);
      await started(tester);
      await send(tester, 'p1', 0, metres: 5.1, topped: true, secs: 70);
      await send(tester, 'p2', 0, metres: 2.3);
      game.myFinish = 92;
      await frames(tester, 0.3);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TopCard(game: game, data: TopCardData('First Wall', 92, 30, 0, 'Your first time at the top!', false, 'Next route', 'Ada')),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINISHING ORDER'), findsOneWidget);
      expect(find.text('1st'), findsOneWidget);
      expect(find.text('Bo'), findsOneWidget);
      expect(find.text('1:10'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      expect(find.text('Me (you)'), findsOneWidget);
      expect(find.text('1:32'), findsWidgets);
      expect(find.text('climbing · 2.3 m'), findsOneWidget);
      // online there is no next route
      expect(find.text('NEXT ROUTE'), findsNothing);
      expect(find.text('LEAVE'), findsOneWidget);
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
