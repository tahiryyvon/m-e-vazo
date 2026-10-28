import 'dart:math' as math;
import 'dart:typed_data';

/// Tempo of a song: beats per minute and the time of a beat, so a
/// metronome can click on the song's own beats.
class TempoEstimate {
  final double bpm;

  /// Time of the first beat at or after 0, within one beat period.
  final Duration firstBeat;

  /// 0..1, how clearly the beat stands out.
  final double confidence;

  const TempoEstimate(this.bpm, this.firstBeat, this.confidence);

  Duration get period => Duration(microseconds: (60e6 / bpm).round());

  @override
  String toString() => 'TempoEstimate(${bpm.toStringAsFixed(1)} BPM, '
      'first beat ${firstBeat.inMilliseconds} ms, conf ${confidence.toStringAsFixed(2)})';
}

/// Estimates tempo and beat phase from mono PCM.
///
/// 1. Onset envelope: rectified rise of log energy of the first difference
///    of the signal (emphasises attacks: drums, strums), one value per hop.
/// 2. Autocorrelation of the envelope over 50–220 BPM, weighted by a
///    log-normal prior around 120 BPM so half/double tempos lose.
/// 3. Phase: the offset whose beat grid collects the most onset energy.
class TempoEstimator {
  static const int _hop = 512;
  static const int _window = 1024;
  static const double _minBpm = 50, _maxBpm = 220;

  /// Where an attack sits relative to the start of the frame whose energy
  /// rise detects it (measured on synthetic attacks, see tests).
  static const double _onsetDelaySamples = _window / 2 + _hop / 2;

  /// At most this much audio is analysed (from the start), enough for a
  /// stable estimate and cheap even for long songs.
  static const int maxSeconds = 240;

  static TempoEstimate? estimate(Float32List pcm, int sampleRate) {
    final usable = math.min(pcm.length, sampleRate * maxSeconds);
    final frames = (usable - _window) ~/ _hop;
    if (frames < 200) return null; // under ~2.5 s
    final hopSec = _hop / sampleRate;

    // 1. Onset envelope.
    final energy = Float64List(frames);
    var peak = 0.0;
    for (var f = 0; f < frames; f++) {
      final start = f * _hop;
      var sum = 0.0;
      var prev = start > 0 ? pcm[start - 1] : 0.0;
      for (var n = start; n < start + _window; n++) {
        final d = pcm[n] - prev;
        prev = pcm[n];
        sum += d * d;
      }
      energy[f] = sum;
      if (sum > peak) peak = sum;
    }
    if (peak <= 1e-9) return null; // silence
    final onset = Float64List(frames);
    for (var f = 1; f < frames; f++) {
      final rise = math.log(1 + 1000 * energy[f] / peak) - math.log(1 + 1000 * energy[f - 1] / peak);
      onset[f] = rise > 0 ? rise : 0;
    }
    // Remove the slow trend (local mean over ~0.5 s) and keep what sticks out.
    final half = (0.25 / hopSec).round();
    final prefix = Float64List(frames + 1);
    for (var f = 0; f < frames; f++) {
      prefix[f + 1] = prefix[f] + onset[f];
    }
    final env = Float64List(frames);
    var envSum = 0.0;
    for (var f = 0; f < frames; f++) {
      final a = math.max(0, f - half), b = math.min(frames, f + half + 1);
      final mean = (prefix[b] - prefix[a]) / (b - a);
      final v = onset[f] - mean;
      env[f] = v > 0 ? v : 0;
      envSum += env[f];
    }
    // A steady tone or a fade has no real attacks: tiny numeric rises must
    // not be mistaken for a pulse.
    if (envSum / frames < 0.004) return null;

    // 2. Weighted autocorrelation.
    final minLag = (60 / (_maxBpm * hopSec)).floor();
    final maxLag = (60 / (_minBpm * hopSec)).ceil();
    if (maxLag >= frames ~/ 2) return null;
    final ac = Float64List(maxLag + 3);
    var acZero = 0.0;
    for (var f = 0; f < frames; f++) {
      acZero += env[f] * env[f];
    }
    for (var lag = math.max(1, minLag - 1); lag <= maxLag + 1; lag++) {
      var sum = 0.0;
      for (var f = 0; f + lag < frames; f++) {
        sum += env[f] * env[f + lag];
      }
      ac[lag] = sum / (frames - lag);
    }
    var bestLag = -1;
    var bestScore = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      final bpm = 60 / (lag * hopSec);
      final octaves = math.log(bpm / 120) / math.ln2;
      final weight = math.exp(-0.5 * octaves * octaves / (0.9 * 0.9));
      // A period between two integer lags splits its peak over both:
      // smoothing over neighbours keeps fast tempos from losing to half speed.
      final smoothed = 0.5 * ac[lag - 1] + ac[lag] + 0.5 * ac[lag + 1];
      final score = smoothed * weight;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    if (bestLag <= minLag || bestLag >= maxLag) return null;
    // Parabolic refinement of the lag for a sub-frame period.
    final y0 = ac[bestLag - 1], y1 = ac[bestLag], y2 = ac[bestLag + 1];
    final denom = y0 - 2 * y1 + y2;
    final shift = denom == 0 ? 0.0 : (0.5 * (y0 - y2) / denom).clamp(-0.5, 0.5);
    final periodFrames = bestLag + shift;
    final confidence = acZero <= 0 ? 0.0 : (ac[bestLag] * frames / acZero).clamp(0.0, 1.0);
    if (confidence < 0.05) return null; // no steady pulse (speech, ambient…)

    // 3. Period and phase refined together: a tiny period error accumulates
    // over a whole song and drags the beat grid, so the grid that collects the
    // most onset energy over the whole envelope wins.
    double beatEnergy(double phase, double period) {
      var sum = 0.0;
      for (var t = phase; t < frames; t += period) {
        final i = t.round();
        if (i < frames) {
          sum += env[i] + 0.5 * ((i > 0 ? env[i - 1] : 0) + (i + 1 < frames ? env[i + 1] : 0));
        }
      }
      return sum;
    }

    var bestPeriod = periodFrames;
    var bestPhase = 0.0;
    var bestPhaseScore = -1.0;
    for (var period = periodFrames - 1.0; period <= periodFrames + 1.0; period += 0.05) {
      for (var phase = 0; phase < period.ceil(); phase++) {
        final score = beatEnergy(phase.toDouble(), period);
        if (score > bestPhaseScore) {
          bestPhaseScore = score;
          bestPeriod = period;
          bestPhase = phase.toDouble();
        }
      }
    }
    // Sub-frame phase: parabola through the neighbouring phase scores.
    final left = beatEnergy(bestPhase - 1 < 0 ? bestPhase - 1 + bestPeriod : bestPhase - 1, bestPeriod);
    final right = beatEnergy(bestPhase + 1, bestPeriod);
    final curve = left - 2 * bestPhaseScore + right;
    if (curve < 0) bestPhase += (0.5 * (left - right) / curve).clamp(-0.5, 0.5);
    final bpm = 60 / (bestPeriod * hopSec);

    // A frame's onset reflects audio in its window, centred half a hop on.
    final firstBeatSec = (bestPhase * _hop + _onsetDelaySamples) / sampleRate;
    final periodSec = 60 / bpm;
    final wrapped = firstBeatSec % periodSec;
    return TempoEstimate(
      bpm,
      Duration(microseconds: (wrapped * 1e6).round()),
      confidence,
    );
  }
}
