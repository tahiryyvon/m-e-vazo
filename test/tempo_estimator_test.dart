import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/tempo_estimator.dart';

/// Strummed-guitar-like test signal: a held chord plus a decaying attack on
/// every beat, accent on beat 1, light noise.
Float32List song({required double bpm, required double firstBeat, double seconds = 30, int sr = 44100}) {
  final rnd = math.Random(7);
  final pcm = Float32List((seconds * sr).round());
  final period = 60 / bpm;
  for (var i = 0; i < pcm.length; i++) {
    final t = i / sr;
    var s = 0.08 * (math.sin(2 * math.pi * 196 * t) + math.sin(2 * math.pi * 246.9 * t));
    if (t >= firstBeat) {
      final beat = ((t - firstBeat) / period).floor();
      final since = t - firstBeat - beat * period;
      final accent = beat % 4 == 0 ? 1.0 : 0.6;
      s += accent * 0.6 * math.exp(-since * 40) * (rnd.nextDouble() * 2 - 1);
    }
    s += 0.01 * (rnd.nextDouble() * 2 - 1);
    pcm[i] = s;
  }
  return pcm;
}

void main() {
  for (final (bpm, first) in [(100.0, 0.37), (128.0, 0.05), (72.0, 0.6), (150.0, 0.2)]) {
    test('finds $bpm BPM and the first beat at ${first}s', () {
      final t = TempoEstimator.estimate(song(bpm: bpm, firstBeat: first), 44100)!;
      expect(t.bpm, closeTo(bpm, 1.0), reason: '$t');
      final period = 60 / bpm;
      final expected = first % period;
      var error = (t.firstBeat.inMicroseconds / 1e6 - expected).abs();
      error = math.min(error, period - error); // phase is circular
      expect(error, lessThan(0.03), reason: '$t');
    });
  }

  test('silence and steady tones have no tempo', () {
    expect(TempoEstimator.estimate(Float32List(44100 * 10), 44100), isNull);
    final tone = Float32List.fromList(List.generate(44100 * 10, (i) => 0.3 * math.sin(2 * math.pi * 220 * i / 44100)));
    expect(TempoEstimator.estimate(tone, 44100), isNull);
  });

  test('a long song stays fast', () {
    final sw = Stopwatch()..start();
    TempoEstimator.estimate(song(bpm: 110, firstBeat: 0.1, seconds: 300), 44100);
    expect(sw.elapsedMilliseconds, lessThan(4000));
  });
}
