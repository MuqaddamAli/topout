// Checks the wide wall for online rooms: one lane per two players, each lane
// a copy of the route (every other one mirrored), bridges between them, and
// two spawns per lane. The balance bot climbs every lane to show they are
// all as hard as the route on its own.
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/core.dart';

import 'balance_test.dart' show ClimbResult, botClimb;

final DateTime _day = DateTime(2026, 10, 27);

List<ClimbRoute> _bases() => [...buildRoutes(), dailyWallFor(_day, chunks: 4)];

/// Hold [h] of lane [l] in the lane's own x, as in the route on its own.
(HoldType, double, double, double?) _local(Lane l, Hold h) {
  if (!l.mirrored) return (h.t, h.x - l.x0, h.y, h.x2 == null ? null : h.x2! - l.x0);
  if (h.x2 == null) return (h.t, l.x1 - h.x, h.y, null);
  return (h.t, l.x1 - h.x2!, h.y, l.x1 - h.x);
}

/// The holds of lane [l] (not the shared ground and top), in its own x.
List<(HoldType, double, double, double?)> _laneHolds(ClimbRoute r, Lane l) => [
      for (final h in r.holds)
        if (h.t != HoldType.ground && h.t != HoldType.top && h.x >= l.x0 && h.x <= l.x1) _local(l, h),
    ]..sort((a, b) => '$a'.compareTo('$b'));

/// The same wall moved left so lane [l] is where lane 1 is, starting from
/// that lane's start holds. Moving does not change any distance, so the
/// bot sees exactly the lane.
ClimbRoute _shifted(ClimbRoute r, Lane l) {
  final m = ClimbRoute(id: r.id, name: r.name, level: r.level, blurb: r.blurb, endless: r.endless);
  m.holds
    ..clear()
    ..addAll([for (final h in r.holds) Hold(h.t, h.x - l.x0, h.y, h.x2 == null ? null : h.x2! - l.x0)]);
  m.startHands = l.startHands;
  m.topY = r.topY;
  return m;
}

/// The balance bot's search, started from a spawn (standing, one hand on a
/// start jug) instead of the route's start. Ends when [done] says so.
int? _spawnClimb(ClimbRoute r, Spawn s, Climber k, bool Function(List<Limb> limbs, Pt c) done,
    {required double Function(Pt c) left, int budget = 60000}) {
  final h = r.holds, p = spawnPose(r, s, k);
  final open = <(double, List<Limb>, Pt, int, bool)>[(0, p.limbs, p.c, 0, false)];
  final seen = <String>{};
  var expanded = 0;
  while (open.isNotEmpty && expanded < budget) {
    var bi = 0;
    for (var i = 1; i < open.length; i++) {
      if (open[i].$1 < open[bi].$1) bi = i;
    }
    final (_, limbs, c, moves, hanging) = open.removeAt(bi);
    final key = '${limbs.map((l) => l.h ?? -1).join(',')}${hanging ? 'h' : ''}';
    if (!seen.add(key)) continue;
    if (!hanging && done(limbs, c)) return moves;
    expanded++;
    for (var i = 0; i < 4; i++) {
      final l = limbs[i];
      final rest = [for (var m = 0; m < 4; m++) m == i ? Limb(null, limbs[m].x, limbs[m].y) : limbs[m]];
      if (l.h != null && !supportInfo(rest, h).supported) continue;
      final jx = c.x + jointOffset[i][0];
      for (var n = r.firstAtOrAbove(c.y - 230); n < r.byY.length; n++) {
        final hk = r.byY[n], hold = h[hk];
        if (hold.y > c.y + 230) break;
        if (hk == l.h || quality(hold, i) == Quality.no || holdDist(hold, c.x, c.y) > 230) continue;
        if (hold.y < l.y - 30 && l.h != null) continue;
        final pt = hold.t.wide ? attachPoint(hold, i, jx) : attachPoint(hold, i);
        final f = feasible(rest, i, pt, c, k);
        if (f != null) {
          final next = [for (var m = 0; m < 4; m++) m == i ? Limb(hk, pt.x, pt.y) : limbs[m].copy()];
          final at = Pt(f.x, f.y);
          open.add((moves + 1 + left(at), next, at, moves + 1, false));
        } else if (isHand[i]) {
          final d = dynoCheck(rest, i, pt, c, k);
          if (d.ok) {
            final next = [for (var m = 0; m < 4; m++) m == i ? Limb(hk, pt.x, pt.y) : Limb(null, limbs[m].x, limbs[m].y)];
            open.add((moves + 1.5 + left(d.end!), next, d.end!, moves + 1, true));
          }
        }
      }
    }
  }
  return null;
}

bool _onTop(ClimbRoute r, List<Limb> l) =>
    l[0].h != null && l[1].h != null && r.holds[l[0].h!].t == HoldType.top && r.holds[l[1].h!].t == HoldType.top;

void main() {
  test('one lane per two players, at most four', () {
    expect([for (var p = 1; p <= 8; p++) lanesFor(p)], [1, 1, 2, 2, 3, 3, 4, 4]);
    expect(lanesFor(0), 1);
    expect(lanesFor(12), maxLanes);
  });

  test('one lane is the route exactly as it is today', () {
    for (final b in _bases()) {
      final r = laneWall(b, 1);
      expect(identical(r, b), isTrue, reason: b.name);
      expect(r.lanes.length, 1);
      expect(r.wallLeft, Wall.left);
      expect(r.wallRight, Wall.right);
      expect(r.bridges, isEmpty);
      expect(r.lanes[0].startHands, b.startHands);
      expect(r.holds[0].x2, 560);
      for (final h in r.holds.where((h) => h.t == HoldType.top)) {
        expect((h.x, h.x2), (40.0, 320.0));
      }
    }
    // and building the routes again still gives the same holds
    final again = buildRoutes();
    final first = buildRoutes();
    for (var i = 0; i < first.length; i++) {
      expect([for (final h in laneWall(again[i], 1).holds) (h.t, h.x, h.y, h.x2)],
          [for (final h in first[i].holds) (h.t, h.x, h.y, h.x2)]);
    }
  });

  test('2 to 4 lanes: the width, the ground, the top and every lane the same', () {
    for (final b in _bases()) {
      final one = _laneHolds(laneWall(b, 2), laneWall(b, 2).lanes[0]);
      for (var n = 2; n <= maxLanes; n++) {
        final r = laneWall(b, n), why = '${b.name}, $n lanes';
        expect(r.lanes.length, n, reason: why);
        expect(r.wallRight - r.wallLeft, n * Wall.right, reason: why);
        expect((r.holds[0].t, r.holds[0].x, r.holds[0].x2), (HoldType.ground, -200.0, 560.0 + (n - 1) * Wall.right));
        final tops = r.holds.where((h) => h.t == HoldType.top).toList();
        if (b.endless) {
          expect(tops, isEmpty, reason: why);
        } else {
          expect(tops.length, 1, reason: why);
          expect((tops[0].x, tops[0].x2, tops[0].y), (40.0, n * Wall.right - 40, b.topY), reason: why);
        }
        expect(r.topY, b.topY);
        for (final l in r.lanes) {
          expect(l.x0, l.index * Wall.right, reason: why);
          expect(l.mirrored, l.index.isOdd, reason: why);
          expect(_laneHolds(r, l), one, reason: '$why, lane ${l.index + 1}');
          // the start holds are the route's own, with the left hand on the left one
          final s0 = r.holds[l.startHands[0]], s1 = r.holds[l.startHands[1]];
          expect(s0.t, HoldType.jug);
          expect(s0.x, lessThan(s1.x), reason: why);
          expect(r.laneAt(l.mid), l);
        }
        // the lane holds without the bridges are the route's own holds
        final own = [
          for (final h in b.holds)
            if (h.t != HoldType.ground && h.t != HoldType.top) (h.t, h.x, h.y, h.x2)
        ]..sort((a, c) => '$a'.compareTo('$c'));
        final bridgeIds = {for (final br in r.bridges) ...br.holds};
        final lane0 = r.lanes[0];
        final lane0Own = [
          for (var k = 0; k < r.holds.length; k++)
            if (!bridgeIds.contains(k) && r.holds[k].t != HoldType.ground && r.holds[k].t != HoldType.top &&
                r.holds[k].x <= lane0.x1)
              _local(lane0, r.holds[k])
        ];
        // lane 1's own holds plus its bridge halves on its outer (left) edge
        expect(lane0Own.length, greaterThanOrEqualTo(own.length));
        for (final h in own) {
          expect(lane0Own, contains(h), reason: why);
        }
        // every small hold is drawn fully inside the wall
        for (final h in r.holds) {
          if (h.t.wide) continue;
          expect(h.x, inInclusiveRange(r.wallLeft + 12, r.wallRight - 12), reason: '$why: $h');
        }
      }
    }
  });

  test('spawns: two per lane, apart, and every climber can stand there', () {
    for (final b in _bases()) {
      for (var n = 1; n <= maxLanes; n++) {
        final r = laneWall(b, n);
        final xs = <double>[];
        for (final l in r.lanes) {
          expect(l.spawns.length, 2);
          final sl = l.spawns[0], sr = l.spawns[1];
          expect((sl.lane, sl.side, sl.hold, sr.side, sr.hold), (l.index, 0, l.startHands[0], 1, l.startHands[1]));
          expect(sl.x, lessThan(r.holds[sl.hold].x));
          expect(sr.x, greaterThan(r.holds[sr.hold].x));
          xs.addAll([sl.x, sr.x]);
          for (final s in l.spawns) {
            expect(s.x, inInclusiveRange(l.x0 + 40, l.x1 - 40));
            for (final k in Climber.all) {
              final p = spawnPose(r, s, k);
              expect(p.err, lessThan(1.2), reason: '${b.name} lane ${l.index + 1} side ${s.side} ${k.name}');
              expect(supportInfo(p.limbs, r.holds).supported, isTrue);
              expect(p.limbs[s.hand].h, s.hold);
              expect(p.limbs[1 - s.hand].h, isNull);
            }
          }
          // the two bodies (about 40 wide) do not overlap, nor do their feet
          for (final k in Climber.all) {
            final a = spawnPose(r, sl, k), c = spawnPose(r, sr, k);
            expect(c.c.x - a.c.x, greaterThan(60), reason: k.name);
            expect(c.limbs[2].x - a.limbs[3].x, greaterThan(100), reason: k.name);
          }
        }
        xs.sort();
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], greaterThan(100), reason: '${b.name}, $n lanes');
        }
      }
    }
  });

  test('bridges join every pair of neighbouring lanes, flat and inside the wall', () {
    for (final b in _bases()) {
      for (var n = 2; n <= maxLanes; n++) {
        final r = laneWall(b, n), why = '${b.name}, $n lanes';
        for (var k = 0; k + 1 < n; k++) {
          final mine = r.bridges.where((x) => x.lane == k).toList();
          expect(mine, isNotEmpty, reason: '$why: lanes ${k + 1} and ${k + 2}');
          final edge = r.lanes[k].x1;
          var last = -1e9;
          for (final br in mine) {
            expect(br.y - last, greaterThanOrEqualTo(260), reason: why);
            last = br.y;
            expect(br.y, inInclusiveRange(230, b.topY - 150), reason: why);
            final hs = [for (final i in br.holds) r.holds[i]];
            expect(hs.length, 8);
            // half on each side of the edge, mirror images of each other
            expect(hs.where((h) => h.x < edge).length, 4);
            for (final h in hs.where((h) => h.x < edge)) {
              expect(hs.any((o) => o.t == h.t && o.y == h.y && o.x == 2 * edge - h.x), isTrue, reason: why);
            }
            // flat: no hold in it is more than a few cm above the row
            for (final h in hs) {
              expect(h.y, inInclusiveRange(br.y - 44, br.y + 6), reason: why);
              expect((h.x - edge).abs(), lessThanOrEqualTo(46), reason: why);
            }
          }
        }
      }
    }
  });

  test('building twice from the same inputs gives the same wall', () {
    for (var n = 1; n <= maxLanes; n++) {
      final a = [for (final b in _bases()) laneWall(b, n)];
      final c = [...buildRoutes(), dailyWallFor(_day, chunks: 4)].map((b) => laneWall(b, n)).toList();
      for (var i = 0; i < a.length; i++) {
        expect([for (final h in c[i].holds) (h.t, h.x, h.y, h.x2)], [for (final h in a[i].holds) (h.t, h.x, h.y, h.x2)]);
        expect([for (final br in c[i].bridges) (br.lane, br.y, '${br.holds}')], [for (final br in a[i].bridges) (br.lane, br.y, '${br.holds}')]);
        expect([for (final l in c[i].lanes) '${l.startHands} ${[for (final s in l.spawns) s.x]}'],
            [for (final l in a[i].lanes) '${l.startHands} ${[for (final s in l.spawns) s.x]}']);
      }
    }
    // the full Daily Wall too, for two different days
    for (final d in [_day, DateTime(2026, 11, 3)]) {
      final x = laneWall(dailyWallFor(d), 3), y = laneWall(dailyWallFor(d), 3);
      expect(x.holds.length, y.holds.length);
      expect([for (final h in y.holds) (h.x, h.y)], [for (final h in x.holds) (h.x, h.y)]);
    }
  });

  test('the balance bot climbs every lane of a 4-lane wall like the route on its own', () {
    final table = StringBuffer('climber    route            alone  lanes 1-4');
    for (final b in _bases()) {
      final r = laneWall(b, 4);
      for (final k in Climber.all) {
        ClimbResult go(ClimbRoute x) => x.endless ? botClimb(x, k, goalY: 1600, step: 60) : botClimb(x, k, step: 60);
        final alone = go(b);
        expect(alone.ok, isTrue);
        final lanes = [for (final l in r.lanes) go(_shifted(r, l))];
        table.write('\n${k.name.padRight(11)}${b.name.padRight(17)}${'${alone.moves}'.padRight(7)}'
            '${lanes.map((x) => x.ok ? '${x.moves}' : 'no').join(' ')}');
        for (var i = 0; i < lanes.length; i++) {
          expect(lanes[i].ok, isTrue, reason: '${k.name} on ${b.name}, lane ${i + 1}');
        }
        final m = lanes.map((x) => x.moves).toList();
        final lo = m.reduce((a, c) => a < c ? a : c), hi = m.reduce((a, c) => a > c ? a : c);
        // every lane takes about as many moves; next to the route on its own the
        // bot varies by a move or two (the bridges and the next lane's edge add holds)
        expect(hi - lo, lessThanOrEqualTo(1), reason: '${k.name} on ${b.name}: $m');
        expect(lo, greaterThanOrEqualTo(alone.moves - 2), reason: '${k.name} on ${b.name}: $m vs ${alone.moves}');
      }
    }
    // ignore: avoid_print
    print(table);
  });

  test('from the left and the right spawn of every lane, the climb is the same', () {
    final table = StringBuffer('climber    route            lane 1 L/R ... lane 4 L/R');
    for (final b in buildRoutes()) {
      final r = laneWall(b, 4);
      for (final k in [Climber.ada, Climber.mei]) {
        final m = <int>[];
        for (final l in r.lanes) {
          for (final s in l.spawns) {
            final res = _spawnClimb(r, s, k, (limbs, _) => _onTop(r, limbs), left: (c) => (b.topY - c.y).clamp(0, 1e9) / 60);
            expect(res, isNotNull, reason: '${k.name} on ${b.name}, lane ${l.index + 1} side ${s.side}');
            m.add(res!);
          }
        }
        table.write('\n${k.name.padRight(11)}${b.name.padRight(17)}${m.join(' ')}');
        final lo = m.reduce((a, c) => a < c ? a : c), hi = m.reduce((a, c) => a > c ? a : c);
        expect(hi - lo, lessThanOrEqualTo(1), reason: '${k.name} on ${b.name}: $m');
      }
    }
    // ignore: avoid_print
    print(table);
  });

  test('a climber can cross every bridge into the next lane', () {
    for (final b in buildRoutes()) {
      final r = laneWall(b, 2);
      for (final br in r.bridges) {
        final edge = r.lanes[br.lane].x1;
        // start in the left lane, end with both hands in the right one
        final res = _spawnClimb(
          r,
          r.lanes[br.lane].spawns[1],
          Climber.ada,
          (l, c) => l[0].h != null && l[1].h != null && r.holds[l[0].h!].x > edge + 20 && r.holds[l[1].h!].x > edge + 20,
          left: (c) => ((br.y - c.y).abs() + (edge + 60 - c.x).clamp(0, 1e9)) / 50,
        );
        expect(res, isNotNull, reason: '${b.name}: bridge at ${br.y}');
      }
    }
  });
}
