import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audio_decoder/audio_decoder.dart' as ad;
import '../models/chord_event.dart';
import 'songsterr_service.dart';
import 'wav_pcm_decoder.dart';

/// FFT radix-2 iterative, en place. Necessite une taille puissance de 2.
class _Fft {
  static void transform(Float64List real, Float64List imag) {
    final n = real.length;
    if (n <= 1) return;

    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    for (int len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang);
      final wi = math.sin(ang);
      for (int i = 0; i < n; i += len) {
        double curWr = 1.0, curWi = 0.0;
        for (int k = 0; k < half; k++) {
          final aIdx = i + k;
          final bIdx = i + k + half;
          final ur = real[aIdx];
          final ui = imag[aIdx];
          final vr = real[bIdx] * curWr - imag[bIdx] * curWi;
          final vi = real[bIdx] * curWi + imag[bIdx] * curWr;
          real[aIdx] = ur + vr;
          imag[aIdx] = ui + vi;
          real[bIdx] = ur - vr;
          imag[bIdx] = ui - vi;
          final nwr = curWr * wr - curWi * wi;
          final nwi = curWr * wi + curWi * wr;
          curWr = nwr;
          curWi = nwi;
        }
      }
    }
  }
}

/// Detection d'accords par analyse du signal audio (chromagramme + template
/// matching), sans dependance a une API ou a un catalogue de morceaux.
///
/// Portee actuelle (MVP) :
/// - Entree : PCM mono 16-bit decode depuis un WAV (voir [WavPcmDecoder]).
/// - Accords reconnus : majeur / mineur sur les 12 fondamentales (24 types).
///   Les 7e, maj7, sus, add9 etc. ne sont PAS distingues dans cette version :
///   un accord "G7" sera detecte comme "G". A etendre plus tard si besoin.
/// - Le capo et la tonalite ne sont pas detectes (accordage standard supposé).
/// - MP3 / M4A / FLAC / AAC / OGG ne sont pas geres : il faut d'abord les
///   decoder en PCM (non fait ici, cf. note d'integration).
///
/// Algorithme valide sur signaux synthetiques (Python/numpy) avant portage :
/// 8/8 accords correctement identifies, latence moyenne de detection ~95ms,
/// max 142ms, sur une fenetre d'analyse de 8192 echantillons / hop 2048.
/// Le portage Dart lui-meme n'a pas ete execute (pas de SDK Dart disponible
/// ici) : a valider avec `flutter test` avant integration definitive.
class AudioChordDetectorService {
  static const List<String> _majorNames = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];
  static const List<String> _minorNames = [
    'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'Bbm', 'Bm'
  ];

  static final Map<String, List<double>> _templates = _buildTemplates();

  static Map<String, List<double>> _buildTemplates() {
    final templates = <String, List<double>>{};
    const majorIntervals = [0, 4, 7];
    const minorIntervals = [0, 3, 7];
    for (int root = 0; root < 12; root++) {
      templates[_majorNames[root]] = _normalizedTemplate(root, majorIntervals);
      templates[_minorNames[root]] = _normalizedTemplate(root, minorIntervals);
    }
    return templates;
  }

  static List<double> _normalizedTemplate(int root, List<int> intervals) {
    final vec = List<double>.filled(12, 0.0);
    for (final iv in intervals) {
      vec[(root + iv) % 12] = 1.0;
    }
    final norm = math.sqrt(vec.fold(0.0, (a, b) => a + b * b));
    if (norm > 0) {
      for (int i = 0; i < 12; i++) {
        vec[i] /= norm;
      }
    }
    return vec;
  }

  /// Extensions convertibles en WAV par le plugin natif `audio_decoder`
  /// (Media Foundation sur Windows, MediaExtractor/MediaCodec sur Android).
  static const List<String> _convertibleExtensions = [
    'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'wma', 'aiff', 'aif',
    'amr', 'caf', 'alac', 'webm',
  ];

  /// Point d'entree unique pour l'analyse d'un fichier local, quel que soit
  /// son format. WAV : decode directement. MP3/M4A/AAC/FLAC/... : converti
  /// au prealable en WAV mono 16-bit via `audio_decoder` (API native de
  /// l'OS, pas de FFmpeg), puis analyse normalement. Retourne null si le
  /// format n'est pas supporte ou si la conversion/decodage echoue.
  ///
  /// NON TESTE dans un environnement Flutter reel (dependance a des API
  /// natives Windows/Android indisponibles ici) : a valider avant usage.
  static Future<SongChordsResult?> analyzeAudioFile(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) {
      return analyzeWavFile(path);
    }

    final dotIdx = lower.lastIndexOf('.');
    if (dotIdx == -1) return null;
    final ext = lower.substring(dotIdx + 1);
    if (!_convertibleExtensions.contains(ext)) return null;

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('chord_detect_');
      final tempWavPath = '${tempDir.path}/decoded.wav';
      await ad.AudioDecoder.convertToWav(
        path,
        tempWavPath,
        sampleRate: 44100,
        channels: 1,
      );
      return await analyzeWavFile(tempWavPath);
    } catch (e) {
      return null;
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // best-effort cleanup
        }
      }
    }
  }

  /// Decode et analyse un fichier WAV local. Retourne null si le fichier
  /// n'existe pas ou n'est pas un PCM 16-bit supporte (fallback attendu
  /// cote appelant vers une autre source, ex. SongsterrService).
  static Future<SongChordsResult?> analyzeWavFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final wav = WavPcmDecoder.decode(bytes);
    if (wav == null) return null;
    return analyzePcm(wav.samples, wav.sampleRate);
  }

  /// Analyse un buffer PCM mono deja decode et retourne la timeline d'accords.
  static SongChordsResult analyzePcm(
    Float32List pcm,
    int sampleRate, {
    int frameSize = 8192,
    int hop = 2048,
    double minEnergy = 0.01,
    int voteWindow = 9,
    int minSegmentMs = 350,
  }) {
    final halfLen = frameSize ~/ 2 + 1;
    final freqs = List<double>.generate(halfLen, (k) => k * sampleRate / frameSize);
    final hann = List<double>.generate(
      frameSize,
      (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (frameSize - 1)),
    );

    final nFrames = pcm.length < frameSize ? 0 : 1 + (pcm.length - frameSize) ~/ hop;

    final times = <double>[];
    final labels = <String?>[];
    final flux = <double>[];
    List<double>? prevMag;

    for (int i = 0; i < nFrames; i++) {
      final start = i * hop;
      final real = Float64List(frameSize);
      final imag = Float64List(frameSize);
      double energySum = 0;
      for (int n = 0; n < frameSize; n++) {
        final sample = pcm[start + n];
        real[n] = sample * hann[n];
        energySum += sample * sample;
      }
      times.add(start / sampleRate);

      _Fft.transform(real, imag);

      final mag = List<double>.filled(halfLen, 0.0);
      for (int k = 0; k < halfLen; k++) {
        mag[k] = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
      }

      double fluxVal = 0;
      final prev = prevMag;
      if (prev != null) {
        for (int k = 0; k < halfLen; k++) {
          final d = mag[k] - prev[k];
          if (d > 0) fluxVal += d;
        }
      }
      flux.add(fluxVal);
      prevMag = mag;

      final rms = math.sqrt(energySum / frameSize);
      if (rms < minEnergy) {
        labels.add(null);
        continue;
      }

      final chroma = List<double>.filled(12, 0.0);
      for (int k = 1; k < halfLen; k++) {
        final f = freqs[k];
        if (f < 70 || f > 2000) continue;
        final midi = 69 + 12 * (math.log(f / 440) / math.ln2);
        var pc = midi.round() % 12;
        if (pc < 0) pc += 12;
        chroma[pc] += mag[k];
      }
      final chromaNorm = math.sqrt(chroma.fold(0.0, (a, b) => a + b * b));
      if (chromaNorm > 0) {
        for (int c = 0; c < 12; c++) {
          chroma[c] /= chromaNorm;
        }
      }

      String? bestName;
      double bestScore = -1;
      _templates.forEach((name, tmpl) {
        double score = 0;
        for (int c = 0; c < 12; c++) {
          score += chroma[c] * tmpl[c];
        }
        if (score > bestScore) {
          bestScore = score;
          bestName = name;
        }
      });
      labels.add(bestName);
    }

    final smoothed = _majorityVoteSmooth(labels, voteWindow);
    final segments = _toSegments(times, smoothed);
    final cleaned = _dropShortSegments(segments, minSegmentMs);
    final refined = _snapToOnsets(cleaned, times, flux, hop / sampleRate);

    final totalDurationSec = pcm.length / sampleRate;
    final events = <ChordEvent>[];
    for (int i = 0; i < refined.length; i++) {
      final t = refined[i].$1;
      final name = refined[i].$2;
      final nextT = i + 1 < refined.length ? refined[i + 1].$1 : totalDurationSec;
      final durMs = ((nextT - t) * 1000).round().clamp(200, 20000);
      events.add(ChordEvent(
        timestamp: Duration(milliseconds: (t * 1000).round()),
        chordName: name,
        durationMs: durMs,
        fretPositions: SongsterrService.standardChordPositions[name],
      ));
    }

    return SongChordsResult(
      chords: events,
      musicalKey: null, // non estime dans ce MVP
      capo: null, // non detecte : accordage standard suppose
      tuning: 'E A D G B E',
    );
  }

  static List<String?> _majorityVoteSmooth(List<String?> labels, int voteWindow) {
    final n = labels.length;
    final out = List<String?>.filled(n, null);
    final half = voteWindow ~/ 2;
    for (int i = 0; i < n; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(n, i + half + 1);
      final counts = <String, int>{};
      for (int j = lo; j < hi; j++) {
        final l = labels[j];
        if (l == null) continue;
        counts[l] = (counts[l] ?? 0) + 1;
      }
      if (counts.isEmpty) continue;
      String? best;
      int bestCount = -1;
      counts.forEach((k, v) {
        if (v > bestCount) {
          bestCount = v;
          best = k;
        }
      });
      out[i] = best;
    }
    return out;
  }

  static List<(double, String)> _toSegments(List<double> times, List<String?> labels) {
    final segs = <(double, String)>[];
    for (int i = 0; i < labels.length; i++) {
      final lab = labels[i];
      if (lab == null) continue;
      if (segs.isNotEmpty && segs.last.$2 == lab) continue;
      segs.add((times[i], lab));
    }
    return segs;
  }

  static List<(double, String)> _dropShortSegments(List<(double, String)> segs, int minMs) {
    if (segs.isEmpty) return segs;
    final out = <(double, String)>[segs.first];
    for (int i = 1; i < segs.length; i++) {
      final t = segs[i].$1;
      final lab = segs[i].$2;
      final nextT = i + 1 < segs.length ? segs[i + 1].$1 : t + 1;
      final durMs = (nextT - t) * 1000;
      if (durMs < minMs) continue;
      if (out.last.$2 == lab) continue;
      out.add((t, lab));
    }
    return out;
  }

  static List<(double, String)> _snapToOnsets(
    List<(double, String)> segs,
    List<double> times,
    List<double> flux,
    double hopSec, {
    double searchSec = 0.35,
  }) {
    if (segs.isEmpty || times.isEmpty) return segs;
    final out = <(double, String)>[];
    for (int i = 0; i < segs.length; i++) {
      final t = segs[i].$1;
      final lab = segs[i].$2;
      if (i == 0) {
        out.add((t, lab));
        continue;
      }
      final idx = (t / hopSec).round();
      final span = (searchSec / hopSec).round();
      final lo = math.max(0, idx - span);
      final hi = math.min(flux.length, idx + span);
      if (hi <= lo) {
        out.add((t, lab));
        continue;
      }
      double bestVal = -1;
      int bestIdx = idx.clamp(0, flux.length - 1);
      for (int k = lo; k < hi; k++) {
        if (flux[k] > bestVal) {
          bestVal = flux[k];
          bestIdx = k;
        }
      }
      out.add((times[bestIdx], lab));
    }
    return out;
  }
}
