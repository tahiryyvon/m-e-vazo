import '../models/chord_event.dart';

/// Global major/minor estimate from duration-weighted concert-pitch chords.
/// Relative keys and songs that modulate can remain ambiguous.
class SongKeyEstimator {
  static const _names = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
  static const _roots = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

  static String? estimate(List<ChordEvent> chords) {
    final weights = List<double>.filled(24, 0);
    int? first;
    int? last;
    for (var i = 0; i < chords.length; i++) {
      final chord = chords[i];
      final match = RegExp(r'^([A-G])([#b]?)(m?)(?:/.*)?$').firstMatch(chord.chordName);
      if (match == null) continue;
      final root = (_roots[match[1]]! + (match[2] == '#' ? 1 : match[2] == 'b' ? -1 : 0)) % 12;
      final index = root + (match[3] == 'm' ? 12 : 0);
      final duration = chord.durationMs != null ? Duration(milliseconds: chord.durationMs!) : (i + 1 < chords.length
          ? chords[i + 1].timestamp - chord.timestamp : const Duration(seconds: 1));
      if (duration.inMilliseconds <= 0) continue;
      weights[index] += duration.inMilliseconds / 1000;
      first ??= index;
      last = index;
    }
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    if (total == 0) return null;
    var bestScore = double.negativeInfinity;
    var best = 0;
    for (var candidate = 0; candidate < 24; candidate++) {
      final tonic = candidate % 12;
      final minor = candidate >= 12;
      // Root interval + 12 denotes a minor chord. Include both minor v and
      // major V in minor keys, to allow the harmonic-minor dominant.
      final harmony = minor
          ? {12: 1.4, 3: 0.8, 17: 0.9, 19: 0.7, 7: 1.0, 8: 0.9, 10: 0.8}
          : {0: 1.4, 14: 0.8, 16: 0.7, 5: 0.9, 7: 1.0, 21: 0.8};
      var score = 0.0;
      for (var chord = 0; chord < 24; chord++) {
        final relative = (chord % 12 - tonic) % 12 + (chord >= 12 ? 12 : 0);
        score += weights[chord] * (harmony[relative] ?? -0.8);
      }
      if (first == candidate) score += total * 0.08;
      if (last == candidate) score += total * 0.12;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return '${_names[best % 12]}${best >= 12 ? 'm' : ''}';
  }
}
