// Smoke test: the app starts on the title screen with all four routes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/audio.dart';
import 'package:topout/game/game.dart';
import 'package:topout/game/store.dart';
import 'package:topout/ui/app.dart';

void main() {
  testWidgets('starts on the title screen', (tester) async {
    final game = Game(store: Store.memory(), audio: GameAudio(musicOn: false, sfxOn: false, enabled: false));
    await tester.pumpWidget(TopoutApp(game: game));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ROUTES'), findsOneWidget);
    expect(game.routes.length, 4);
    expect(game.phase, Phase.menu);
    await tester.pumpWidget(const SizedBox());
  });
}
