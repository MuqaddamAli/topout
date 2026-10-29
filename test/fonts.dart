// The game's fonts for widget tests. Without them every letter is a square
// as wide as it is tall, and button labels no longer fit.
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadGameFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Atkinson', ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf']);
  await load('BigShoulders', ['BigShouldersDisplay-ExtraBold.ttf', 'BigShouldersDisplay-Black.ttf']);
  await load('PlexMono', ['IBMPlexMono-Medium.ttf']);
  await load('ArchivoXC', ['Archivo-ExtraCondensedBlack.ttf']);
  await load('CourierPrime', ['CourierPrime-Regular.ttf', 'CourierPrime-Bold.ttf']);
  await load('Reenie', ['ReenieBeanie-Regular.ttf']);
  // Real icons too, if the Flutter SDK is where we expect it.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
}
