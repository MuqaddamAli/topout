// The fonts the game can load by hand (lib/ui/fonts.dart) are the ones in
// pubspec.yaml, file for file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:topout/ui/fonts.dart';

void main() {
  test('the font list matches pubspec.yaml', () {
    final spec = File('pubspec.yaml').readAsStringSync();
    final families = [for (final m in RegExp(r'- family: (\w+)').allMatches(spec)) m[1]];
    final files = {for (final m in RegExp(r'asset: assets/fonts/([\w.-]+)').allMatches(spec)) m[1]};
    expect(families, gameFonts.keys.toList());
    expect(files, {for (final f in gameFonts.values) ...f});
  });
}
