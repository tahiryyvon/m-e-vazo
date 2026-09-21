// Test a executer avec `flutter test test/audio_chord_detector_test.dart`
// (ou `dart test` si le fichier est deplace dans un projet dart pur).
//
// Ce test n'a PAS ete execute par Claude (pas de SDK Dart disponible dans
// l'environnement de generation). L'algorithme equivalent a ete valide
// numeriquement en Python/numpy (8/8 accords corrects, latence ~95-140ms)
// avant portage. A lancer et corriger si besoin avant integration.

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/audio_chord_detector_service.dart';

const int _sr = 44100;

// Frequences des cordes a vide, standard tuning, du Mi grave au mi aigu.
const List<double> _stringOpen = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

// Positions de frettes [E A D G B e], -1 = corde etouffee.
const Map<String, List<int>> _shapes = {
  'G': [3, 2, 0, 0, 0, 3],
  'Em': [0, 2, 2, 0, 0, 0],
  'C': [-1, 3, 2, 0, 1, 0],
  'D': [-1, -1, 0, 2, 3, 2],
};

double _stringFreq(int stringIdx, int fret) => _stringOpen[stringIdx] * math.pow(2, fret / 12);

Float32List _synthChord(String name, double durSec) {
  final n = (durSec * _sr).round();
  final out = Float32List(n);
  final shape = _shapes[name]!;
  for (int s = 0; s < 6; s++) {
    final fret = shape[s];
    if (fret < 0) continue;
    final freq = _stringFreq(s, fret);
    for (int i = 0; i < n; i++) {
      final t = i / _sr;
      final decay = math.exp(-t * 3.0);
      double sample = 0;
      for (int h = 1; h <= 6; h++) {
        sample += (1.0 / h) * math.sin(2 * math.pi * freq * h * t);
      }
      out[i] += sample * decay;
    }
  }
  // normalisation approximative + leger bruit pour realisme
  double maxAbs = 0;
  for (final v in out) {
    if (v.abs() > maxAbs) maxAbs = v.abs();
  }
  final rng = math.Random(42);
  if (maxAbs > 0) {
    for (int i = 0; i < n; i++) {
      out[i] = (out[i] / maxAbs) * 0.8 + (rng.nextDouble() - 0.5) * 0.02;
    }
  }
  return out;
}

Float32List _synthProgression(List<MapEntry<String, double>> seq) {
  final chunks = seq.map((e) => _synthChord(e.key, e.value)).toList();
  final total = chunks.fold<int>(0, (a, c) => a + c.length);
  final out = Float32List(total);
  int offset = 0;
  for (final c in chunks) {
    out.setRange(offset, offset + c.length, c);
    offset += c.length;
  }
  return out;
}

void main() {
  test('detecte une progression G - Em - C - D avec latence < 300ms', () {
    final seq = [
      const MapEntry('G', 2.0),
      const MapEntry('Em', 2.0),
      const MapEntry('C', 2.0),
      const MapEntry('D', 2.0),
    ];
    final pcm = _synthProgression(seq);

    final result = AudioChordDetectorService.analyzePcm(pcm, _sr);

    expect(result.chords, isNotEmpty, reason: 'aucun accord detecte');

    // Attendu: G a 0s, Em a ~2s, C a ~4s, D a ~6s, avec une latence de
    // detection typique (l'analyse ne peut identifier un accord qu'apres
    // en avoir entendu une partie -> jamais avant l'attaque reelle).
    final expected = {'G': 0.0, 'Em': 2.0, 'C': 4.0, 'D': 6.0};

    for (final chordName in expected.keys) {
      final match = result.chords.firstWhere(
        (c) => c.chordName == chordName,
        orElse: () => throw TestFailure('accord $chordName jamais detecte'),
      );
      final expectedSec = expected[chordName]!;
      final actualSec = match.timestamp.inMilliseconds / 1000;
      final diffMs = ((actualSec - expectedSec) * 1000).abs();
      expect(
        diffMs,
        lessThan(300),
        reason: '$chordName detecte a ${actualSec}s, attendu ~${expectedSec}s (ecart ${diffMs}ms)',
      );
    }

    // L'ordre chronologique des accords doit respecter la progression.
    final order = result.chords.map((c) => c.chordName).toList();
    final gIdx = order.indexOf('G');
    final emIdx = order.indexOf('Em');
    final cIdx = order.indexOf('C');
    final dIdx = order.indexOf('D');
    expect(gIdx, lessThan(emIdx));
    expect(emIdx, lessThan(cIdx));
    expect(cIdx, lessThan(dIdx));
  });

  test('un frame silencieux ne produit aucun accord', () {
    final silence = Float32List(_sr * 2); // 2s de silence
    final result = AudioChordDetectorService.analyzePcm(silence, _sr);
    expect(result.chords, isEmpty);
  });
}
