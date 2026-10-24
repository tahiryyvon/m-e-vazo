import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/services/song_key_estimator.dart';

List<ChordEvent> progression(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    ChordEvent(timestamp: Duration(seconds: i * 4), chordName: names[i], durationMs: 4000),
];

void main() {
  test('estimates major, minor with dominant, and transposed progressions', () {
    expect(SongKeyEstimator.estimate(progression(['C', 'F', 'G', 'C'])), 'C');
    expect(SongKeyEstimator.estimate(progression(['Am', 'Dm', 'E', 'Am'])), 'Am');
    expect(SongKeyEstimator.estimate(progression(['D', 'Bm', 'G', 'A', 'D'])), 'D');
    expect(SongKeyEstimator.estimate(progression(['Bb', 'Eb', 'F', 'Bb'])), 'Bb');
  });
  test('duration weighting is invariant to splitting repeated chords', () {
    final original = progression(['G', 'C', 'D', 'G']);
    final split = [
      original.first,
      for (var i = 0; i < 40; i++)
        ChordEvent(timestamp: Duration(milliseconds: 4000 + i * 100), chordName: 'C', durationMs: 100),
      ...original.skip(2),
    ];
    expect(SongKeyEstimator.estimate(split), SongKeyEstimator.estimate(original));
  });
  test('does not invent a key without usable chords', () {
    expect(SongKeyEstimator.estimate([]), isNull);
    expect(SongKeyEstimator.estimate(progression(['N', 'X'])), isNull);
  });
}
