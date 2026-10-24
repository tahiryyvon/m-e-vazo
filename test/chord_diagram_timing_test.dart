import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/widgets/chord_diagram.dart';

void main() {
  testWidgets('replaces the chord immediately and clears it in a no-chord gap', (tester) async {
    Widget diagram(String? name) => MaterialApp(home: Scaffold(body: ChordDiagram(
      chord: name == null ? null : ChordEvent(timestamp: Duration.zero, chordName: name),
    )));
    await tester.pumpWidget(diagram('C'));
    expect(find.text('C'), findsOneWidget);
    await tester.pumpWidget(diagram('G'));
    expect(find.text('C'), findsNothing);
    expect(find.text('G'), findsOneWidget);
    await tester.pumpWidget(diagram(null));
    expect(find.text('G'), findsNothing);
    expect(find.text('—'), findsOneWidget);
  });
}
