import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/chordino_service.dart';
import 'package:guitar_lyrics_player/services/audio_chord_detector_service.dart';
import 'package:guitar_lyrics_player/models/chord_timeline.dart';

void main() {
  test('preserves no-chord gaps and exact native timestamps', () {
    final result = ChordinoService.parseCsv(
        '0.0,"N"\n1.25,"A"\n3.5,"N"\n5.0,"D"\n7.0,"N"', 8);
    expect(result.chords.length, 2);
    expect(result.chords.first.timestamp.inMilliseconds, 1250);
    expect(result.chords.first.durationMs, 2250);
    expect(ChordTimeline.activeIndex(result.chords, const Duration(seconds: 4)),
        -1);
    expect(
        ChordTimeline.nextIndex(result.chords, const Duration(seconds: 4)), 1);
    expect(ChordTimeline.activeIndex(result.chords, const Duration(seconds: 8)),
        -1);
    expect(ChordTimeline.activeIndex(result.chords, const Duration(seconds: 2)),
        0);
  });
  test('merges ornamental variants and removes tiny fragments without bridging',
      () {
    final result = ChordinoService.parseCsv(
        '0.0,"Dmaj7"\n1.0,"D6"\n2.0,"D"\n3.0,"Em"\n3.1,"A"', 5);
    expect(result.chords.map((c) => c.chordName), ['D', 'A']);
    expect(result.chords.first.durationMs, 3000);
    expect(
        ChordTimeline.activeIndex(
            result.chords, const Duration(milliseconds: 3050)),
        -1);
    expect(result.chords.last.timestamp.inMilliseconds, 3100);
  });
  test('does not invent major triads for unsupported suspended harmonies', () {
    final result = ChordinoService.parseCsv('0.0,"Dsus4"\n1.0,"F#m7"', 3);
    expect(result.chords.single.chordName, 'F#m');
    expect(result.chords.single.timestamp.inSeconds, 1);
  });
  test('malformed or out-of-order output fails instead of creating chords', () {
    expect(() => ChordinoService.parseCsv('bad output', 10),
        throwsFormatException);
    expect(() => ChordinoService.parseCsv('2.0,"C"\n1.0,"D"', 10),
        throwsFormatException);
  });
  test('native engine analyzes the actual diagnostic recording', () async {
    final result = await AudioChordDetectorService.analyzeWavFile(
        'build/diagnostics/someone_like_you.wav');
    expect(result, isNotNull);
    expect(result!.analysisMethod, contains('Chordino'));
    expect(result.chords, isNotEmpty);
    for (var i = 1; i < result.chords.length; i++) {
      final previous = result.chords[i - 1];
      expect(
          result.chords[i].timestamp.inMilliseconds,
          greaterThanOrEqualTo(
              previous.timestamp.inMilliseconds + previous.durationMs!));
    }
    final summary = {
      'engine': result.analysisMethod,
      'events': result.chords.length,
      'under_1_second': result.chords.where((c) => c.durationMs! < 1000).length,
      'chords': result.chords
          .map((c) => {
                'time_ms': c.timestamp.inMilliseconds,
                'duration_ms': c.durationMs,
                'chord': c.chordName,
              })
          .toList(),
    };
    await File('build/diagnostics/chordino_result.json')
        .writeAsString(jsonEncode(summary));
    // This verifies execution and timeline integrity, not musical ground truth.
  }, skip: !const bool.fromEnvironment('RUN_CHORDINO_DIAGNOSTIC'));
}
