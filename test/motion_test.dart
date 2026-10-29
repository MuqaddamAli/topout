// The shared motions (lib/ui/motion.dart): they end where they should, they
// stop by themselves, and with less motion they show the end at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topout/game/game.dart' show Pulse;
import 'package:topout/ui/motion.dart';

Widget _app(Widget child, {bool still = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
    );

/// The text of [TypeIn] that shows (the rest is there, but clear).
String _shown(WidgetTester tester) {
  InlineSpan s = tester.widget<RichText>(find.byType(RichText)).text;
  // Text.rich wraps the spans once more; TypeIn's are the typed part, then the rest
  while (s is TextSpan && s.children?.length == 1) {
    s = s.children!.first;
  }
  if (s is TextSpan && s.children != null) return (s.children!.first as TextSpan).text ?? '';
  return s.toPlainText();
}

void main() {
  testWidgets('typed text types out, and is all there from the start', (tester) async {
    await tester.pumpWidget(_app(const TypeIn('0.0 m up')));
    expect(find.text('0.0 m up'), findsOneWidget);
    expect(_shown(tester), '');
    // a ticker counts from its first frame
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester).length, inInclusiveRange(2, 6));
    await tester.pumpAndSettle();
    expect(_shown(tester), '0.0 m up');
  });

  testWidgets('with less motion everything shows at once', (tester) async {
    await tester.pumpWidget(_app(
      const Column(mainAxisSize: MainAxisSize.min, children: [
        TypeIn('typed'),
        WriteIn(child: Text('written')),
        Settle(child: Text('settled')),
      ]),
      still: true,
    ));
    expect(_shownAll(tester), contains('typed'));
    expect(find.byType(ClipRect), findsNothing);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('a knocked tag swings and comes to rest by itself', (tester) async {
    final knocks = Pulse();
    await tester.pumpWidget(_app(Swing(kicks: knocks, child: const SizedBox(width: 40, height: 60))));
    double angle() => tester.widget<Transform>(find.byType(Transform)).transform.getRotation().entry(1, 0);
    expect(angle(), 0);
    knocks.fire();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));
    expect(angle().abs(), greaterThan(0.01));
    await tester.pumpAndSettle();
    expect(angle(), 0);
  });
}

String _shownAll(WidgetTester tester) => tester.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join(' ');
