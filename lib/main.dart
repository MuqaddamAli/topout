import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game/audio.dart';
import 'game/game.dart';
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
  // also opens that route (used to measure performance).
  final perf = kIsWeb ? Uri.base.queryParameters['perf'] : null;
  if (perf != null) _measure(game, perf);
}

void _measure(Game game, String routeId) {
  final route = game.routes.where((r) => r.id == routeId).firstOrNull;
  if (route != null) SchedulerBinding.instance.addPostFrameCallback((_) => game.startRoute(route));
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
