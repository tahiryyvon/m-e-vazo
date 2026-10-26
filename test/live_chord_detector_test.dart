import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/live_chord_detector.dart';

Uint8List pcm16(List<double> freqs, {int sampleRate = 44100, double seconds = 2.0, double amp = 0.08}) {
  final n = (sampleRate * seconds).round();
  final bytes = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var s = 0.0;
    for (final f in freqs) {
      // fundamental plus two softer harmonics, like a plucked string
      s += math.sin(2 * math.pi * f * t) +
          0.4 * math.sin(2 * math.pi * 2 * f * t) +
          0.2 * math.sin(2 * math.pi * 3 * f * t);
    }
    bytes.setInt16(i * 2, (s / freqs.length * amp * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('hears a quiet G major chord from the microphone stream', () {
    final detector = LiveChordDetector(sampleRate: 44100);
    final data = pcm16([196.0, 246.94, 293.66]); // G3 B3 D4
    // Feed in small chunks like a real recorder.
    for (var i = 0; i < data.length; i += 4096) {
      detector.feedPcm16(Uint8List.sublistView(data, i, math.min(i + 4096, data.length)));
    }
    final d = detector.analyze();
    expect(d.chord, 'G');
    expect(d.level, greaterThan(0.01));
  });

  test('names the dominant note with its deviation in cents', () {
    final detector = LiveChordDetector(sampleRate: 44100);
    detector.feedPcm16(pcm16([443.0])); // slightly sharp A4
    final d = detector.analyze();
    expect(d.note, 'A4');
    expect(d.cents, closeTo(12, 6));
    expect(d.frequency, closeTo(443, 2));
  });

  test('silence yields nothing', () {
    final detector = LiveChordDetector(sampleRate: 44100);
    detector.feedPcm16(Uint8List(44100 * 2 * 2));
    final d = detector.analyze();
    expect(d.chord, isNull);
    expect(d.note, isNull);
  });
}
