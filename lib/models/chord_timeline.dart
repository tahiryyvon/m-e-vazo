import 'chord_event.dart';

class ChordTimeline {
  static int nextIndex(List<ChordEvent> chords, Duration position) {
    var lo = 0;
    var hi = chords.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (chords[mid].timestamp <= position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int activeIndex(List<ChordEvent> chords, Duration position) {
    final index = nextIndex(chords, position) - 1;
    if (index < 0) return -1;
    final chord = chords[index];
    if (chord.durationMs != null &&
        position >=
            chord.timestamp + Duration(milliseconds: chord.durationMs!)) {
      return -1;
    }
    return index;
  }
}
