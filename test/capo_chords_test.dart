import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/services/capo_chords.dart';

void main() {
  test('capo 2 displays a C shape for a sounding D without changing time', () {
    final concert = ChordEvent(
        timestamp: const Duration(milliseconds: 1234),
        chordName: 'D',
        durationMs: 567);
    final shape = CapoChords.shape(concert, 2);
    expect(shape.chordName, 'C');
    expect(shape.fretPositions, [-1, 3, 2, 0, 1, 0]);
    expect(shape.timestamp, concert.timestamp);
    expect(shape.durationMs, concert.durationMs);
    expect(CapoChords.shape(concert, 0), same(concert));
    expect(CapoChords.shape(concert, 5).chordName, 'A');
  });
  test('minor chords and slash bass transpose relative to the capo', () {
    final minor = ChordEvent(timestamp: Duration.zero, chordName: 'F#m');
    expect(CapoChords.shape(minor, 2).chordName, 'Em');
    final slash = ChordEvent(timestamp: Duration.zero, chordName: 'D/F#');
    expect(CapoChords.shape(slash, 2).chordName, 'C/E');
    expect(() => CapoChords.shape(minor, -1), throwsRangeError);
  });
}
