import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/models/chord_barre.dart';
import 'package:guitar_lyrics_player/services/capo_chords.dart';
import 'package:guitar_lyrics_player/services/songsterr_service.dart';
import 'package:guitar_lyrics_player/widgets/chord_diagram.dart';

ChordEvent chord(String name) => ChordEvent(timestamp: Duration.zero, chordName: name,
    fretPositions: SongsterrService.standardChordPositions[name]);

void main() {
  test('full and partial barres exclude open and alternate shapes', () {
    expect(ChordBarre.resolve(chord('F'), chord('F').fretPositions)?.fret, 1);
    final bm = ChordBarre.resolve(chord('Bm'), chord('Bm').fretPositions)!;
    expect([bm.fret, bm.firstString, bm.lastString], [2, 1, 5]);
    for (final name in ['C', 'D', 'E', 'A', 'Em', 'Am', 'B7']) {
      expect(ChordBarre.resolve(chord(name), chord(name).fretPositions), isNull);
    }
    expect(ChordBarre.resolve(chord('F'), [-1, -1, 3, 2, 1, 1]), isNull);
    final shape = CapoChords.shape(chord('G'), 2);
    expect(ChordBarre.resolve(shape, shape.fretPositions)?.fret, 1);
  });
  testWidgets('barre label appears and clears with the next open chord', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChordDiagram(chord: chord('F')))));
    expect(find.text('Barré · case 1'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChordDiagram(chord: chord('C')))));
    expect(find.textContaining('Barré'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
