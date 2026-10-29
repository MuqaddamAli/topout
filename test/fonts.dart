// The game's fonts for widget tests. Without them every letter is a square
// as wide as it is tall, and button labels no longer fit.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:topout/ui/fonts.dart';

Future<void> loadGameFonts() async {
  await loadFonts();
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
