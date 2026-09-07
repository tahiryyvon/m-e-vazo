import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GuitarLyricsPlayerApp());
    expect(find.byType(GuitarLyricsPlayerApp), findsOneWidget);
  });
}
