import 'dart:math' as math;
import 'dart:typed_data';
import 'audio_chord_detector_service.dart';

/// What the microphone currently hears.
class LiveDetection {
  final String? chord;
  final String? note; // e.g. "A4"
  final double? frequency; // Hz
  final double cents; // deviation from the nearest semitone, -50..50
  final double level; // RMS 0..1
  final double noteStrength; // 0..1, how dominant the pitch is

  const LiveDetection({
    this.chord,
    this.note,
    this.frequency,
    this.cents = 0,
    this.level = 0,
    this.noteStrength = 0,
  });

  static const silent = LiveDetection();
}

/// Sliding-window chord and pitch detection on microphone PCM, reusing the
/// song chord engine ([AudioChordDetectorService.analyzePcm]) on the last
/// couple of seconds of audio.
class LiveChordDetector {
  final int sampleRate;
  final Float32List _ring;
  int _write = 0;
  int _filled = 0;

  LiveChordDetector({required this.sampleRate, double windowSeconds = 2.0})
      : _ring = Float32List((sampleRate * windowSeconds).round());

  /// Low byte of a sample split across two chunks, or null.
  int? _pendingByte;

  /// Appends little-endian 16-bit mono PCM. Chunks are not guaranteed to
  /// hold whole samples: an odd trailing byte is kept for the next chunk so
  /// the stream never shifts by one byte (which would turn audio into noise).
  void feedPcm16(Uint8List bytes) {
    if (bytes.isEmpty) return;
    var offset = 0;
    var count = 0;
    if (_pendingByte != null) {
      final value = (_pendingByte! | (bytes[0] << 8)).toSigned(16);
      _push(value / 32768.0);
      _pendingByte = null;
      offset = 1;
      count++;
    }
    final data = ByteData.sublistView(bytes);
    final whole = (bytes.length - offset) ~/ 2;
    for (var i = 0; i < whole; i++) {
      _push(data.getInt16(offset + i * 2, Endian.little) / 32768.0);
    }
    count += whole;
    if ((bytes.length - offset).isOdd) _pendingByte = bytes[bytes.length - 1];
    _filled = math.min(_ring.length, _filled + count);
  }

  void _push(double sample) {
    _ring[_write] = sample;
    _write = (_write + 1) % _ring.length;
  }

  /// Copy of the window in chronological order (oldest first).
  Float32List snapshot() {
    final out = Float32List(_filled);
    if (_filled == 0) return out;
    final start = _filled < _ring.length ? 0 : _write;
    for (var i = 0; i < _filled; i++) {
      out[i] = _ring[(start + i) % _ring.length];
    }
    return out;
  }

  LiveDetection analyze() => analyzeWindow(snapshot(), sampleRate);

  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  /// Pure function so it can run in an isolate.
  static LiveDetection analyzeWindow(Float32List window, int sampleRate) {
    if (window.length < 8192) return LiveDetection.silent;
    double energy = 0;
    double peak = 0;
    for (final s in window) {
      energy += s * s;
      final a = s.abs();
      if (a > peak) peak = a;
    }
    final level = math.sqrt(energy / window.length);
    if (peak < 0.003) return LiveDetection(level: level);

    // Microphone input is quiet: normalize so the song engine's energy
    // threshold behaves as it does on a decoded track.
    final gain = 0.9 / peak;
    final scaled = Float32List(window.length);
    for (var i = 0; i < window.length; i++) {
      scaled[i] = window[i] * gain;
    }

    String? chord;
    final result = AudioChordDetectorService.analyzePcm(
      scaled, sampleRate, confirmFrames: 3, minSegmentMs: 250,
    );
    if (result.chords.isNotEmpty) {
      final last = result.chords.last;
      final endSec = window.length / sampleRate;
      final lastEnd = (last.timestamp.inMilliseconds + (last.durationMs ?? 0)) / 1000;
      // Only report a chord still sounding at the end of the window.
      if (last.durationMs == null || lastEnd >= endSec - 0.4) chord = last.chordName;
    }

    String? note;
    double? frequency;
    var cents = 0.0;
    var strength = 0.0;
    final pitch = AudioChordDetectorService.estimatePitch(scaled, sampleRate);
    if (pitch != null && pitch.$1 > 0) {
      frequency = pitch.$1;
      strength = pitch.$2;
      final midi = 69 + 12 * (math.log(frequency / 440) / math.ln2);
      final nearest = midi.round();
      cents = ((midi - nearest) * 100).clamp(-50.0, 50.0);
      note = '${_noteNames[nearest % 12]}${nearest ~/ 12 - 1}';
    }
    return LiveDetection(
      chord: chord, note: note, frequency: frequency, cents: cents,
      level: level, noteStrength: strength,
    );
  }
}
