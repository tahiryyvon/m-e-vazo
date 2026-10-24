import 'package:flutter/foundation.dart';
import 'chord_event.dart';
import '../services/songsterr_service.dart';

class ChordBarre {
  final int fret;
  final int firstString;
  final int lastString;
  const ChordBarre(this.fret, this.firstString, this.lastString);

  static const _standard = {
    'F': ChordBarre(1, 0, 5), 'Fm': ChordBarre(1, 0, 5),
    'F7': ChordBarre(1, 0, 5), 'F#': ChordBarre(2, 0, 5),
    'Gb': ChordBarre(2, 0, 5), 'F#m': ChordBarre(2, 0, 5),
    'F#7': ChordBarre(2, 0, 5), 'F#m7': ChordBarre(2, 0, 5),
    'Gm': ChordBarre(3, 0, 5), 'Ab': ChordBarre(4, 0, 5),
    'G#m': ChordBarre(4, 0, 5), 'B': ChordBarre(2, 1, 5),
    'Bm': ChordBarre(2, 1, 5), 'Bb': ChordBarre(1, 1, 5),
    'Bbm': ChordBarre(1, 1, 5), 'Cm': ChordBarre(3, 1, 5),
    'C#m': ChordBarre(4, 1, 5), 'Db': ChordBarre(1, 3, 5),
    'Eb': ChordBarre(3, 3, 5), 'Dm7': ChordBarre(1, 4, 5),
    'Dmaj7': ChordBarre(2, 3, 5),
  };

  /// String indexes run from low E (0) to high e (5).
  static ChordBarre? resolve(ChordEvent chord, List<int>? positions) {
    if (positions == null || positions.length != 6) return null;
    ChordBarre? barre;
    final strings = chord.barreStrings;
    if (chord.barreFret != null && strings != null && strings.length >= 2) {
      final sorted = strings.toList()..sort();
      barre = ChordBarre(chord.barreFret!, sorted.first, sorted.last);
    } else if (listEquals(positions, SongsterrService.standardChordPositions[chord.chordName])) {
      barre = _standard[chord.chordName];
    }
    if (barre == null || barre.fret < 1 || barre.firstString < 0 ||
        barre.lastString > 5 || barre.firstString >= barre.lastString) {
      return null;
    }
    for (var i = barre.firstString; i <= barre.lastString; i++) {
      if (positions[i] < barre.fret) return null;
    }
    return barre;
  }
}
