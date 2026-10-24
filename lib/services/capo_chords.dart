import '../models/chord_event.dart';
import 'songsterr_service.dart';

/// Convert concert-pitch chords to shapes relative to a user-selected capo.
class CapoChords {
  static const _roots = {
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };
  static const _major = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'Ab',
    'A',
    'Bb',
    'B'
  ];
  static const _minor = [
    'C',
    'C#',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'Bb',
    'B'
  ];

  static ChordEvent shape(ChordEvent concert, int capo) {
    RangeError.checkValueInInterval(capo, 0, 12, 'capo');
    if (capo == 0 || capo == 12) return concert;
    String transpose(String part) {
      final match = RegExp(r'^([A-G][#b]?)(.*)$').firstMatch(part);
      if (match == null || !_roots.containsKey(match[1])) return part;
      final suffix = match[2]!;
      final names =
          suffix.startsWith('m') && !suffix.startsWith('maj') ? _minor : _major;
      return '${names[(_roots[match[1]]! - capo) % 12]}$suffix';
    }

    final name = concert.chordName.split('/').map(transpose).join('/');
    return ChordEvent(
      timestamp: concert.timestamp,
      chordName: name,
      durationMs: concert.durationMs,
      fretPositions: SongsterrService.standardChordPositions[name],
      lyricLineIndex: concert.lyricLineIndex,
    );
  }
}
