import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/chord_timeline_filter.dart';

void main() {
  const segments = [(0.0, 'G'), (2.0, 'Em'), (2.5, 'G'), (4.0, 'C')];
  const times = [2.0, 2.1, 2.2, 2.3, 2.4];
  test('removes an ambiguous short detour and keeps the next true change', () {
    final result = ChordTimelineFilter.stabilize(segments, times,
        List.generate(5, (_) => {'G': 0.80, 'Em': 0.83}));
    expect(result, [(0.0, 'G'), (4.0, 'C')]);
  });
  test('retains a clearly supported 500ms chord with its exact timestamps', () {
    final result = ChordTimelineFilter.stabilize(segments, times,
        List.generate(5, (_) => {'G': 0.60, 'Em': 0.90}));
    expect(result, segments);
  });
  test('does not turn a fast progression into a held chord', () {
    const progression = [(0.0, 'G'), (2.0, 'Em'), (2.5, 'D')];
    expect(ChordTimelineFilter.stabilize(progression, times,
        List.generate(5, (_) => {'G': 0.80, 'Em': 0.83})), progression);
  });
}
