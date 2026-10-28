// A climb alone on a wall with lanes (?lanes=N): the camera follows the
// climber across the lanes and over a bridge, Look shows the lane you are
// in, and the wall is drawn across every lane. One lane draws as before.
// Screenshots go to build/screens/ (4x_*).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/art.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/core.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/scene.dart';
import 'package:topout/game/store.dart';
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

  Future<Game> open(WidgetTester tester, int lanes) async {
    await loadGameFonts();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false), today: DateTime(2026, 10, 27))
      ..debugLanes = lanes;
    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: TopoutApp(game: game)));
    await frames(tester, 0.5);
    return game;
  }

  /// Puts the climber on holds [hands] and [feet] (feet on the ground if
  /// null, under the body), as if they had climbed there.
  void place(Game g, List<int> hands, {List<int>? feet, double? footX}) {
    final h = g.holds;
    final p0 = attachPoint(h[hands[0]], 0), p1 = attachPoint(h[hands[1]], 1);
    final fx = footX ?? (p0.x + p1.x) / 2;
    g.limbs = [
      Limb(hands[0], p0.x, p0.y),
      Limb(hands[1], p1.x, p1.y),
      if (feet == null) Limb(0, fx - 17, 0) else Limb(feet[0], h[feet[0]].x - 3, h[feet[0]].y),
      if (feet == null) Limb(0, fx + 17, 0) else Limb(feet[1], h[feet[1]].x + 3, h[feet[1]].y),
    ];
    final s = solve(Pt((p0.x + p1.x) / 2, (p0.y + p1.y) / 2 - 60), g.anchors(), 80, g.climber.reach);
    g.c = Pt(s.x, s.y);
    g.cd = g.c.copy();
    g.endDraw = g.limbs.map((l) => Pt(l.x, l.y)).toList();
  }

  testWidgets('one lane draws as before: the summit, the ground and the climb', (tester) async {
    final g = await open(tester, 1);
    g.startRoute(g.routes[0]);
    await frames(tester, 0.3);
    final r = g.route!;
    expect(identical(r, g.routes[0]), isTrue);
    expect(g.keepsRecords, isTrue);
    // the summit line is the one it always was
    double before(double x) {
      final d = x < 40 ? 40 - x : (x > 320 ? x - 320 : 0.0), f = math.min(1.0, d / 40);
      return r.topY + 1 - math.min(d, 240) * 0.42 + f * (math.sin(x * 0.057 + 1.3) * 7 + math.sin(x * 0.13) * 3);
    }

    for (var x = -400.0; x <= 800; x += 7) {
      expect(ScenePainter.wallEdgeY(r, x), before(x));
    }
    // the grass and pebbles of one lane are the same as before, more only follow them
    final rg = Rng(31), tufts = <(double, double)>[];
    for (var x = -420.0; x < 780; x += 9 + rg() * 16) {
      tufts.add((x, 5 + rg() * 9));
      rg();
      rg();
    }
    final art = Art.instance;
    expect([for (var i = 0; i < tufts.length; i++) (art.tufts[i].x, art.tufts[i].h)], tufts);
    final pebbles = [for (var i = 0; i < 70; i++) (-420 + rg() * 1200, -8 - rg() * 60, rg(), rg(), rg())];
    expect([for (var i = 0; i < 70; i++) (art.pebbles[i].x, art.pebbles[i].y)], [for (final p in pebbles) (p.$1, p.$2)]);
    expect(art.tufts.last.x, greaterThan(Art.groundRight - 30));
    // Look stays where it was, over the middle of the wall
    g.setLook(true);
    await frames(tester, 1.5);
    expect(g.camX, closeTo(180, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('four lanes: the camera follows across the wall, Look shows your lane', (tester) async {
    final g = await open(tester, 4);
    g.startRoute(g.routes[1]);
    await frames(tester, 0.8);
    final r = g.route!;
    expect(r.lanes.length, 4);
    expect(r.id, 'steps');
    expect(g.keepsRecords, isFalse, reason: 'a wall with lanes is not saved in the records');
    expect(g.camX, lessThan(Wall.right), reason: 'the climb starts in lane 1');
    await shot(tester, '40_lanes_start');

    // over in lane 3, the camera comes along
    place(g, r.lanes[2].startHands, footX: r.lanes[2].mid);
    await frames(tester, 1.5);
    expect(g.camX, closeTo(g.camXFor(g.cd.x), 1));
    expect(r.laneAt(g.cd.x).index, 2);
    expect(g.camX, inInclusiveRange(r.lanes[2].x0, r.lanes[2].x1));
    await shot(tester, '41_lanes_lane3');
    g.setLook(true);
    await frames(tester, 1.5);
    expect(g.camX, closeTo(r.lanes[2].mid, 1));
    await shot(tester, '42_lanes_look_lane3');
    g.setLook(false);
    await frames(tester, 1.0);

    // on a bridge between lane 3 and lane 4, both hands across the edge
    final br = r.bridges.firstWhere((b) => b.lane == 2);
    final edge = r.lanes[2].x1;
    int nearest(bool left, HoldType t) {
      final ids = br.holds.where((i) => r.holds[i].t == t && (r.holds[i].x < edge) == left).toList()
        ..sort((a, b) => (r.holds[a].x - edge).abs().compareTo((r.holds[b].x - edge).abs()));
      return ids.first;
    }

    place(g, [nearest(true, HoldType.jug), nearest(false, HoldType.jug)],
        feet: [nearest(true, HoldType.chip), nearest(false, HoldType.chip)]);
    await frames(tester, 1.5);
    expect(g.cd.x, closeTo(edge, 30));
    expect(g.camX, closeTo(g.camXFor(g.cd.x), 1));
    await shot(tester, '43_lanes_bridge');
    // the climber steps over: now Look shows lane 4
    place(g, [nearest(false, HoldType.jug), nearest(false, HoldType.jug)], feet: [nearest(false, HoldType.chip), nearest(false, HoldType.chip)]);
    g.c.x = g.cd.x = math.max(g.c.x, edge + 4);
    g.setLook(true);
    await frames(tester, 1.5);
    expect(g.camX, closeTo(r.lanes[3].mid, 1));
    g.setLook(false);
    await frames(tester, 0.5);

    // a camera pan (recenter) still works on the wide wall
    g.camManual = r.topY - 40;
    await frames(tester, 1.5);
    await shot(tester, '44_lanes_summit');
    g.recenter();
    await frames(tester, 1.2);
    expect(g.camY, closeTo(g.cd.y + 40, 2));

    // the right edge: the camera stops at the wall's edge
    place(g, r.lanes[3].startHands, footX: r.lanes[3].mid + 60);
    await frames(tester, 1.5);
    final half = g.cw / g.scale / 2;
    expect(g.camX, lessThanOrEqualTo(r.wallRight - half + 8 + 0.5));
    await shot(tester, '45_lanes_right_edge');

    // the ground between lane 1 and lane 2, with both crash pads
    place(g, r.lanes[0].startHands, footX: Wall.right);
    await frames(tester, 1.5);
    await shot(tester, '46_lanes_ground_edge');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Daily Wall with three lanes, up in the snow', (tester) async {
    final g = await open(tester, 3);
    g.startRoute(g.routes.last);
    await frames(tester, 0.5);
    final r = g.route!;
    expect(r.endless, isTrue);
    expect(r.lanes.length, 3);
    final br = r.bridges.lastWhere((b) => b.lane == 1 && b.y < 2500);
    List<int> inner(HoldType t) => br.holds.where((i) => r.holds[i].t == t).toList()
      ..sort((a, b) => r.holds[a].x.compareTo(r.holds[b].x));
    final hands = inner(HoldType.jug), feet = inner(HoldType.chip);
    place(g, [hands[1], hands[2]], feet: [feet[1], feet[2]]);
    g.camManual = br.y + 30;
    await frames(tester, 1.5);
    await shot(tester, '47_lanes_daily_snow');
    await tester.pumpWidget(const SizedBox());
  });
}
