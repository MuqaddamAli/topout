// The game's fonts, by family, and a way to load them by hand.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Every family in pubspec.yaml and its files in assets/fonts.
const Map<String, List<String>> gameFonts = {
  'Atkinson': ['AtkinsonHyperlegible-Regular.ttf', 'AtkinsonHyperlegible-Bold.ttf'],
  'ArchivoXC': ['Archivo-ExtraCondensedBlack.ttf'],
  'CourierPrime': ['CourierPrime-Regular.ttf', 'CourierPrime-Bold.ttf'],
  'Reenie': ['ReenieBeanie-Regular.ttf'],
};

/// Loads [families] from their files (all of them by default).
Future<void> loadFonts([Iterable<String>? families]) {
  Future<void> load(String family) {
    final loader = FontLoader(family);
    for (final f in gameFonts[family]!) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    return loader.load();
  }

  return Future.wait([for (final family in families ?? gameFonts.keys) load(family)]);
}

/// On the web the engine loads the families that assets/FontManifest.json
/// lists. A browser that kept the manifest of an older build in its cache
/// would show every label in a fallback font, so the families missing from
/// it are loaded here.
Future<void> loadUnlistedFonts() async {
  try {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json', cache: false)) as List;
    final listed = {for (final e in manifest) (e as Map)['family']};
    final missing = [for (final f in gameFonts.keys) if (!listed.contains(f)) f];
    if (missing.isEmpty) return;
    debugPrint('Loading fonts the font manifest does not list: ${missing.join(', ')}');
    await loadFonts(missing);
  } catch (e) {
    debugPrint('Could not check the fonts: $e');
  }
}
