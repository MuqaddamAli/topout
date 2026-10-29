// Checks that the climbers are fair: a small bot climbs every route with
// every climber, using the real rules (reach, support, jumps, the hang after
// a catch). It ignores grip, so it shows what each body can reach, and it
// prints how many moves and jumps each one needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart' show Game;
import 'package:topout/game/mountain.dart';

class _Node {
  _Node(this.limbs, this.c, this.moves, this.jumps, this.hanging, [this.parent]);
  final List<Limb> limbs;
  final Pt c;
  final int moves, jumps;
  final bool hanging;
  final _Node? parent;
  double f = 0;
}

/// A binary heap ordered by [_Node.f].
class _Heap {
  final List<_Node> _a = [];
  bool get isEmpty => _a.isEmpty;

  void push(_Node n) {
    _a.add(n);
    var i = _a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_a[p].f <= _a[i].f) break;
      final t = _a[p];
      _a[p] = _a[i];
      _a[i] = t;
      i = p;
    }
  }

  _Node pop() {
    final top = _a.first, last = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = last;
      var i = 0;
      while (true) {
        final l = i * 2 + 1, r = l + 1;
        var m = i;
        if (l < _a.length && _a[l].f < _a[m].f) m = l;
        if (r < _a.length && _a[r].f < _a[m].f) m = r;
        if (m == i) break;
        final t = _a[m];
        _a[m] = _a[i];
        _a[i] = t;
        i = m;
      }
    }
    return top;
  }
}

class ClimbResult {
  ClimbResult(this.ok, this.moves, this.jumps, this.expanded, [this.stances = const []]);
  final bool ok;
  final int moves, jumps, expanded;

  /// The limbs after each move, from the start to the end.
  final List<List<Limb>> stances;
}

/// Best-first search from the start of [r] until both hands are on the top,
/// or the body is above [goalY] (for the Daily Wall).
ClimbResult botClimb(ClimbRoute r, Climber k, {double? goalY, int budget = 60000, double step = 38, bool jumps = true}) {
  final h = r.holds;
  final goal = goalY ?? r.topY;
  final p0 = attachPoint(h[r.startHands[0]], 0), p1 = attachPoint(h[r.startHands[1]], 1);
  final start = [Limb(r.startHands[0], p0.x, p0.y), Limb(r.startHands[1], p1.x, p1.y), Limb(0, 164, 0), Limb(0, 198, 0)];
  final anc = [for (var i = 0; i < 4; i++) Anchor(i, start[i].x, start[i].y)];
  final s0 = solve(Pt(180, 100), anc, 80, k.reach);
  final open = _Heap()..push(_Node(start, Pt(s0.x, s0.y), 0, 0, false));
  final seen = <String>{};
  var expanded = 0;

  bool done(_Node n) {
    if (goalY != null) return n.c.y >= goal && !n.hanging;
    final a = n.limbs[0].h, b = n.limbs[1].h;
    return a != null && b != null && h[a].t == HoldType.top && h[b].t == HoldType.top;
  }

  while (!open.isEmpty && expanded < budget) {
    final n = open.pop();
    final key = '${n.limbs.map((l) => l.h ?? -1).join(',')}${n.hanging ? 'h' : ''}';
    if (!seen.add(key)) continue;
    if (done(n)) {
      final stances = <List<Limb>>[];
      for (_Node? p = n; p != null; p = p.parent) {
        stances.insert(0, p.limbs);
      }
      return ClimbResult(true, n.moves, n.jumps, expanded, stances);
    }
    expanded++;
    for (var i = 0; i < 4; i++) {
      final l = n.limbs[i];
      final rest = [for (var m = 0; m < 4; m++) m == i ? Limb(null, n.limbs[m].x, n.limbs[m].y) : n.limbs[m]];
      if (l.h != null && !supportInfo(rest, h).supported) continue;
      final jx = n.c.x + jointOffset[i][0];
      for (var hk = 0; hk < h.length; hk++) {
        final hold = h[hk];
        if (hk == l.h || quality(hold, i) == Quality.no) continue;
        // the same window the game uses when it marks holds you can reach
        if ((hold.y - n.c.y).abs() > 230 || holdDist(hold, n.c.x, n.c.y) > 230) continue;
        // only moves that do not go back down much
        if (hold.y < l.y - 30 && l.h != null) continue;
        final pt = hold.t.wide ? attachPoint(hold, i, jx) : attachPoint(hold, i);
        final f = feasible(rest, i, pt, n.c, k);
        _Node? next;
        if (f != null) {
          final limbs = [for (var m = 0; m < 4; m++) m == i ? Limb(hk, pt.x, pt.y) : n.limbs[m].copy()];
          next = _Node(limbs, Pt(f.x, f.y), n.moves + 1, n.jumps, false, n);
        } else if (jumps && isHand[i]) {
          final d = dynoCheck(rest, i, pt, n.c, k);
          if (d.ok) {
            final limbs = [for (var m = 0; m < 4; m++) m == i ? Limb(hk, pt.x, pt.y) : Limb(null, n.limbs[m].x, n.limbs[m].y)];
            next = _Node(limbs, d.end!, n.moves + 1, n.jumps + 1, true, n);
          }
        }
        if (next == null) continue;
        // fewer moves is better, height is the guide; jumps cost a little extra
        next.f = next.moves + next.jumps * 0.5 + (goal - next.c.y).clamp(0, 1e9) / step;
        open.push(next);
      }
    }
  }
  return ClimbResult(false, 0, 0, expanded);
}

/// How much grip the hands spend climbing [stances] on [r], holding each
/// stance [hold] seconds with the real grip rules (what they get back while
/// resting is not counted). With [snow], the holds start under snow as in
/// the game and each limb brushes its hold off as it does there.
double gripSpent(ClimbRoute r, Climber k, List<List<Limb>> stances, {required bool snow, double hold = 2.5}) {
  final covered = snow ? {for (var i = 0; i < r.holds.length; i++) if (Mountain.snowCovered(r, i)) i} : <int>{};
  final wear = <int, double>{};
  var spent = 0.0;
  const dt = 0.05;
  for (final limbs in stances) {
    for (var t = 0.0; t < hold; t += dt) {
      final slick = <int>{};
      for (var i = 0; i < 4; i++) {
        final h = limbs[i].h;
        if (h == null || !covered.contains(h) || (wear[h] ?? 0) >= 1) continue;
        wear[h] = (wear[h] ?? 0) + dt / (isHand[i] ? Game.brushHand : Game.brushFoot);
        if (wear[h]! < 1) slick.add(h);
      }
      final g = gripRates(limbs, r.holds, Mode.normal, k, slick);
      for (final rate in g.rates) {
        if (rate < 0) spent -= rate * dt;
      }
    }
  }
  return spent;
}

void main() {
  test('every climber has the same stat budget and a different perk', () {
    expect(Climber.all.length, 4);
    for (final k in Climber.all) {
      expect(k.statTotal, statBudget, reason: k.name);
      for (final s in [k.reachStat, k.gripStat, k.restStat, k.jumpStat]) {
        expect(s, inInclusiveRange(1, 5));
      }
    }
    expect(Climber.all.map((k) => k.perk).toSet().length, Climber.all.length);
    expect(Climber.all.map((k) => k.id).toSet().length, Climber.all.length);
  });

  test('the base climber keeps the original numbers', () {
    final k = Climber.base;
    expect(k.reach, reach);
    expect(k.dynoExtra, dynoExtra);
    expect(k.hangTime, hangTime);
    expect(k.drainMul, 1);
    expect(k.restMul, 1);
    expect(k.catchMul, 1);
  });

  test('every climber can reach the top of every route', () {
    final routes = buildRoutes();
    final daily = dailyWallFor(DateTime(2026, 10, 27), chunks: 4);
    final table = StringBuffer('climber    ');
    for (final r in routes) {
      table.write(r.name.padRight(18));
    }
    table.write('Daily (15 m)');
    final moves = <String, List<int>>{};
    for (final k in Climber.all) {
      table.write('\n${k.name.padRight(11)}');
      for (final r in [...routes, daily]) {
        final res = r.endless ? botClimb(r, k, goalY: 1600, step: 60) : botClimb(r, k, step: 60);
        expect(res.ok, isTrue, reason: '${k.name} on ${r.name} (${res.expanded} stances tried)');
        moves.putIfAbsent(r.id, () => []).add(res.moves);
        table.write('${res.moves} moves, ${res.jumps} jumps'.padRight(18));
      }
    }
    // ignore: avoid_print
    print(table);
    // nobody needs a lot more moves than the others on any route
    for (final m in moves.values) {
      final lo = m.reduce((a, b) => a < b ? a : b), hi = m.reduce((a, b) => a > b ? a : b);
      expect(hi, lessThanOrEqualTo((lo * 1.4).ceil() + 1));
    }
  });

  test('snow on the upper part of a route costs the hands a little more grip, about the same for everyone', () {
    final table = StringBuffer('grip spent, dry / with snow');
    for (final r in buildRoutes()) {
      final extra = <double>[];
      for (final k in Climber.all) {
        final res = botClimb(r, k, step: 60);
        expect(res.ok, isTrue);
        final dry = gripSpent(r, k, res.stances, snow: false), wet = gripSpent(r, k, res.stances, snow: true);
        extra.add(wet / dry - 1);
        table.write('\n${r.name.padRight(16)} ${k.name.padRight(5)} ${dry.toStringAsFixed(0).padLeft(4)} / ${wet.toStringAsFixed(0)}'
            ' (+${((wet / dry - 1) * 100).toStringAsFixed(0)}%)');
        expect(wet, greaterThan(dry), reason: '${k.name} on ${r.name}: the snow is felt');
        expect(wet / dry, lessThan(1.25), reason: '${k.name} on ${r.name}: but it costs only a little');
      }
      final lo = extra.reduce((a, b) => a < b ? a : b), hi = extra.reduce((a, b) => a > b ? a : b);
      expect(hi - lo, lessThan(0.12), reason: '${r.name}: nobody is hit much harder than the others');
    }
    // ignore: avoid_print
    print(table);
  });

  test('every climber can do the lesson wall without jumping', () {
    final r = buildRoutes().first;
    final moves = <int>[];
    for (final k in Climber.all) {
      final res = botClimb(r, k, jumps: false, budget: 200000);
      expect(res.ok, isTrue, reason: k.name);
      moves.add(res.moves);
    }
    // ignore: avoid_print
    print('First Wall without jumps: ${[for (var i = 0; i < moves.length; i++) '${Climber.all[i].name} ${moves[i]}'].join(', ')}');
  });
}
