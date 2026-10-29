// The game's fonts for widget tests. Without them every letter is a square
// as wide as it is tall, and button labels no longer fit.
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
}
