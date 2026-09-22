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
  'Am': [-1, 0, 2, 2, 1, 0],
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

  test('reste stable (peu de flicker) sur un signal bruite realiste', () {
    // Meme progression que le test propre, mais avec bruit de fond et
    // quelques "clics" large bande simulant le mediator / bruit de piece.
    final rng = math.Random(7);
    final seq = [
      const MapEntry('G', 2.0),
      const MapEntry('Em', 2.0),
      const MapEntry('C', 2.0),
      const MapEntry('D', 2.0),
    ];
    final clean = _synthProgression(seq);
    final noisy = Float32List(clean.length);
    for (int i = 0; i < clean.length; i++) {
      noisy[i] = clean[i] + (rng.nextDouble() - 0.5) * 0.12; // bruit de fond
    }
    // quelques clics ponctuels
    for (int c = 0; c < 5; c++) {
      final pos = rng.nextInt(noisy.length - 200);
      for (int k = 0; k < 80; k++) {
        noisy[pos + k] += (rng.nextDouble() - 0.5) * 0.6;
      }
    }

    final result = AudioChordDetectorService.analyzePcm(noisy, _sr);

    // Anti-regression : avant le lissage EMA + hysteresis, ce type de
    // signal produisait des dizaines de segments parasites. On tolere une
    // marge (bruit synthetique different a chaque run de reglages) mais
    // pas un retour au flicker massif.
    expect(
      result.chords.length,
      lessThan(20),
      reason: 'trop de segments (${result.chords.length}) : possible regression anti-flicker',
    );

    // L'ordre chronologique des accords principaux doit rester respecte.
    final order = result.chords.map((c) => c.chordName).toList();
    final gIdx = order.indexOf('G');
    final emIdx = order.indexOf('Em');
    final dIdx = order.lastIndexOf('D');
    expect(gIdx, greaterThanOrEqualTo(0));
    expect(emIdx, greaterThan(gIdx));
    expect(dIdx, greaterThan(emIdx));
  });

  test('ne derive pas et ne se perd pas au milieu d un morceau long avec dynamique variable', () {
    // Morceau plus long (16s) : progression G -> Em -> C -> D -> Am -> C -> G -> D
    // Section du milieu (6s-12s) avec dynamique plus forte et bruit pour simuler
    // le refrain (batterie/voix) qui provoquait le blocage mid-song.
    final seq = [
      const MapEntry('G', 2.0),
      const MapEntry('Em', 2.0),
      const MapEntry('C', 2.0),
      const MapEntry('D', 2.0),
      const MapEntry('Am', 2.0),
      const MapEntry('C', 2.0),
      const MapEntry('G', 2.0),
      const MapEntry('D', 2.0),
    ];
    final clean = _synthProgression(seq);
    final mixed = Float32List(clean.length);
    final rng = math.Random(99);

    for (int i = 0; i < clean.length; i++) {
      final t = i / _sr;
      double factor = 1.0;
      if (t >= 6.0 && t <= 12.0) {
        // Milieu du morceau : gain plus fort et perturbations (bruit de fond / percussions)
        factor = 1.8;
      }
      mixed[i] = clean[i] * factor + (rng.nextDouble() - 0.5) * 0.05;
    }

    final result = AudioChordDetectorService.analyzePcm(mixed, _sr);

    expect(result.chords, isNotEmpty);

    // Verifie que les accords de la 2e moitie (milieu et fin) sont bien detectes
    final detectedNames = result.chords.map((c) => c.chordName).toSet();
    expect(detectedNames.contains('G'), isTrue, reason: 'G manquant');
    expect(detectedNames.contains('Em'), isTrue, reason: 'Em manquant');
    expect(detectedNames.contains('C'), isTrue, reason: 'C manquant');
    expect(detectedNames.contains('D'), isTrue, reason: 'D manquant');
    expect(detectedNames.contains('Am'), isTrue, reason: 'Am manquant en milieu de morceau');

    // Verifie que le debut ET la fin ont bien detecte des accords
    final firstChord = result.chords.first;
    final lastChord = result.chords.last;
    expect(firstChord.timestamp.inMilliseconds, lessThan(1000));
    expect(lastChord.timestamp.inMilliseconds, greaterThan(12000));
  });

  test('reinitialise correctement apres une pause / silence au milieu du morceau', () {
    // Progression : G (2s) -> Silence (1s) -> C (2s)
    final gSamples = _synthChord('G', 2.0);
    final silence = Float32List((1.0 * _sr).round());
    final cSamples = _synthChord('C', 2.0);

    final total = gSamples.length + silence.length + cSamples.length;
    final pcm = Float32List(total);
    pcm.setRange(0, gSamples.length, gSamples);
    // silence reste a 0
    pcm.setRange(gSamples.length + silence.length, total, cSamples);

    final result = AudioChordDetectorService.analyzePcm(pcm, _sr);

    expect(result.chords, isNotEmpty);
    final gChord = result.chords.firstWhere((c) => c.chordName == 'G');
    final cChord = result.chords.firstWhere((c) => c.chordName == 'C');

    expect(gChord.timestamp.inMilliseconds, lessThan(300));
    // C doit apparaitre apres le silence (vers 3.0s)
    final cSec = cChord.timestamp.inMilliseconds / 1000;
    expect(cSec, greaterThanOrEqualTo(2.8));
    expect(cSec, lessThan(3.5));
  });
}
