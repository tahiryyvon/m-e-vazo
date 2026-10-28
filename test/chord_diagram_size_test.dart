import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/services/songsterr_service.dart';
import 'package:guitar_lyrics_player/widgets/chord_diagram.dart';

ChordEvent chord(String name) => ChordEvent(
    timestamp: Duration.zero, chordName: name,
    fretPositions: SongsterrService.standardChordPositions[name]);

void main() {
  testWidgets('barre, open and empty diagrams have exactly the same size', (tester) async {
    final sizes = <Size>[];
    for (final c in [chord('F'), chord('C'), chord('Bm'), chord('Em'), null]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
          child: ChordDiagram(chord: c, size: 88)))));
      sizes.add(tester.getSize(find.byType(ChordDiagram)));
    }
    expect(find.textContaining('Barré'), findsNothing); // last pumped: empty
    expect(sizes.toSet().length, 1, reason: '$sizes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a barre chord still shows its fret label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: ChordDiagram(chord: chord('F'), size: 88)))));
    expect(find.text('Barré · case 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
