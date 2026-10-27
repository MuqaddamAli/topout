// Checks the Dart rules against data made by the web prototype
// (tool/make_fixtures.js), so both versions build the same walls and the
// body moves the same way.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/core.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/core_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
  final routes = buildRoutes();

  List<Limb> limbsFrom(List<dynamic> raw) => raw.map((l) {
        final v = l as List<dynamic>;
        return Limb(v[0] as int?, (v[1] as num).toDouble(), (v[2] as num).toDouble());
      }).toList();

  void expectHolds(ClimbRoute r, Map<String, dynamic> want) {
    expect(r.topY, (want['topY'] as num).toDouble());
    expect(r.startHands, (want['startHands'] as List<dynamic>).cast<int>());
    final holds = want['holds'] as List<dynamic>;
    expect(r.holds.length, holds.length, reason: 'hold count for ${r.id}');
    for (var k = 0; k < holds.length; k++) {
      final w = holds[k] as List<dynamic>, h = r.holds[k];
      final got = [h.t.name, h.x, h.y, h.x2];
      final exp = [w[0], (w[1] as num).toDouble(), (w[2] as num).toDouble(), (w[3] as num?)?.toDouble()];
      expect(got, exp, reason: 'hold $k of ${r.id}');
    }
  }

  test('random numbers match the web build', () {
    final rng = fx['rng'] as Map<String, dynamic>;
    rng.forEach((seed, values) {
      final r = Rng(int.parse(seed));
      for (final v in values as List<dynamic>) {
        expect(r(), (v as num).toDouble());
      }
    });
    (fx['seeds'] as Map<String, dynamic>).forEach((s, v) => expect(dailySeed(s), v));
  });

  test('fixed routes match the web build', () {
    final want = fx['routes'] as List<dynamic>;
    expect(routes.length, want.length);
    for (var k = 0; k < routes.length; k++) {
      expect(routes[k].id, (want[k] as Map<String, dynamic>)['id']);
      expectHolds(routes[k], want[k] as Map<String, dynamic>);
    }
  });

  test('daily walls match the web build', () {
    for (final d in fx['daily'] as List<dynamic>) {
      final m = d as Map<String, dynamic>;
      final parts = (m['date'] as String).split('-').map(int.parse).toList();
      expectHolds(dailyWallFor(DateTime(parts[0], parts[1], parts[2])), m);
    }
  });

  test('the body solver matches', () {
    for (final c in fx['solve'] as List<dynamic>) {
      final m = c as Map<String, dynamic>;
      final cc = (m['c'] as List<dynamic>).cast<num>();
      final anchors = (m['anchors'] as List<dynamic>).map((a) {
        final v = (a as List<dynamic>).cast<num>();
        return Anchor(v[0].toInt(), v[1].toDouble(), v[2].toDouble());
      }).toList();
      final s = solve(Pt(cc[0].toDouble(), cc[1].toDouble()), anchors, m['iters'] as int);
      final out = (m['out'] as List<dynamic>).cast<num>();
      expect(s.x, closeTo(out[0], 1e-6));
      expect(s.y, closeTo(out[1], 1e-6));
      expect(s.err, closeTo(out[2], 1e-6));
    }
  });

  test('reach checks and jumps match', () {
    for (final c in fx['feasible'] as List<dynamic>) {
      final m = c as Map<String, dynamic>;
      final pt = (m['pt'] as List<dynamic>).cast<num>(), cc = (m['c'] as List<dynamic>).cast<num>();
      final f = feasible(limbsFrom(m['limbs'] as List<dynamic>), m['i'] as int, Pt(pt[0].toDouble(), pt[1].toDouble()),
          Pt(cc[0].toDouble(), cc[1].toDouble()));
      final out = m['out'] as List<dynamic>?;
      expect(f == null, out == null);
      if (f != null && out != null) {
        expect(f.x, closeTo(out[0] as num, 1e-6));
        expect(f.y, closeTo(out[1] as num, 1e-6));
      }
    }
    for (final c in fx['dyno'] as List<dynamic>) {
      final m = c as Map<String, dynamic>;
      final pt = (m['pt'] as List<dynamic>).cast<num>(), cc = (m['c'] as List<dynamic>).cast<num>();
      final d = dynoCheck(limbsFrom(m['limbs'] as List<dynamic>), m['i'] as int, Pt(pt[0].toDouble(), pt[1].toDouble()),
          Pt(cc[0].toDouble(), cc[1].toDouble()));
      expect(d.ok, m['ok']);
      expect(d.why, m['why']);
      if (d.ok) {
        final end = (m['end'] as List<dynamic>).cast<num>();
        expect(d.end!.x, closeTo(end[0], 1e-6));
        expect(d.end!.y, closeTo(end[1], 1e-6));
      }
    }
  });

  test('grip drain matches', () {
    final holds = routes[0].holds;
    for (final c in fx['grip'] as List<dynamic>) {
      final m = c as Map<String, dynamic>;
      final g = gripRates(limbsFrom(m['limbs'] as List<dynamic>), holds, Mode.fromName(m['mode'] as String));
      final rates = (m['rates'] as List<dynamic>).cast<num>();
      expect(g.rates[0], closeTo(rates[0], 1e-9));
      expect(g.rates[1], closeTo(rates[1], 1e-9));
      expect(g.s.standing, m['standing']);
      expect(g.s.supported, m['supported']);
      expect(g.s.feetW, closeTo(m['feetW'] as num, 1e-9));
    }
  });

  test('holds stay inside the wall and every route has a top', () {
    for (final r in [...routes, dailyWallFor(DateTime(2026, 10, 27))]) {
      for (final h in r.holds) {
        if (h.t.wide) continue;
        expect(h.x, inInclusiveRange(Wall.holdLeft - 8, Wall.holdRight + 8));
      }
      expect(r.topY, greaterThan(0));
      expect(r.startHands.length, 2);
    }
  });
}
