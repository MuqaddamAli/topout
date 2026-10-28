import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/core.dart';
import 'game/game.dart';
import 'game/online.dart';
import 'game/store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The game is made for phones held upright.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = await Store.open();
  final audio = GameAudio(musicOn: store.getBool('music', true), sfxOn: store.getBool('sfx', true));
  final game = Game(store: store, audio: audio);
  runApp(TopoutApp(game: game));
  // On the web, ?perf logs frame times to the console, and ?perf=<route id>
  // also opens that route (used to measure performance). ?perf=online makes
  // a room and prints its code: fill it with bots and it starts by itself.
  final perf = kIsWeb ? Uri.base.queryParameters['perf'] : null;
  // For development: ?lanes=N makes climbs alone use a wall with N lanes.
  // Debug and profile builds only; the live site (a release build) ignores it.
  final lanes = kIsWeb && !kReleaseMode ? int.tryParse(Uri.base.queryParameters['lanes'] ?? '') : null;
  if (lanes != null) game.debugLanes = lanes.clamp(1, maxLanes);
  if (perf != null) _measure(game, perf);
}

void _measure(Game game, String routeId) {
  final route = game.routes.where((r) => r.id == routeId).firstOrNull;
  if (route != null) SchedulerBinding.instance.addPostFrameCallback((_) => game.startRoute(route));
  if (routeId == 'online') _measureRoom(game);
  var frames = 0, build = 0, raster = 0, worst = 0;
  var since = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      frames++;
      build += t.buildDuration.inMicroseconds;
      raster += t.rasterDuration.inMicroseconds;
      if (t.totalSpan.inMicroseconds > worst) worst = t.totalSpan.inMicroseconds;
    }
    final now = DateTime.now(), secs = now.difference(since).inMicroseconds / 1e6;
    if (secs < 2 || frames == 0) return;
    debugPrint('perf fps ${(frames / secs).toStringAsFixed(1)} build ${(build / frames / 1000).toStringAsFixed(2)} ms '
        'raster ${(raster / frames / 1000).toStringAsFixed(2)} ms worst ${(worst / 1000).toStringAsFixed(1)} ms');
    frames = build = raster = worst = 0;
    since = now;
  });
}

/// Makes a room on First Wall, starts it when 8 climbers are in (or after
/// 60 s), and after 15 s of climbing turns Look on so everyone is in view.
void _measureRoom(Game game) {
  final o = game.online;
  var made = false, started = false;
  final t0 = DateTime.now();
  void check() {
    if (!made && o.status == NetStatus.online) {
      made = true;
      o.create(name: 'Perf', route: 'first', mode: 'normal', dateKey: game.todayKey, climber: game.climber.id).then((_) {
        debugPrint('perf room ${o.room?.code}: npm run bots -- ${o.room?.code} 7');
      });
    }
    final r = o.room;
    if (!started && r != null && o.isHost && (r.players.length >= 8 || DateTime.now().difference(t0).inSeconds > 60)) {
      started = true;
      debugPrint('perf start with ${r.players.length} climbers');
      o.start();
      Future.delayed(const Duration(seconds: 18), () {
        debugPrint('perf look on');
        game.setLook(true);
      });
    }
  }

  o.addListener(check);
  SchedulerBinding.instance.addPostFrameCallback((_) => game.showOnline());
}
