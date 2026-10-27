import 'package:flutter/material.dart';
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
}
