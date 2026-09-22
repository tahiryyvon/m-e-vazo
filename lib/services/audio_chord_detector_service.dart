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
/// - Signal propre : 8/8 accords corrects, latence moyenne ~95ms (max 142ms).
/// - Signal bruite realiste (bruit de fond + clics + vibrato) : le lissage
///   EMA du chroma + l'hysteresis a marge (voir `_debounce`) fait passer le
///   nombre de segments parasites de 17 a 9 pour 8 accords attendus, sans
///   rien degrader sur le signal propre.
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
    double chromaSmoothing = 0.3, // alpha EMA : 0.3 reactif et lisse sans accumulation de lag
    int confirmFrames = 5, // frames requises avant bascule (~230ms a hop 2048/44.1k)
    double switchMargin = 0.04, // marge minimale de score pour basculer
    double minConfidence = 0.48, // score minimal pour valider un accord
    int minSegmentMs = 700,
  }) {
    final halfLen = frameSize ~/ 2 + 1;
    final freqs = List<double>.generate(halfLen, (k) => k * sampleRate / frameSize);
    final hann = List<double>.generate(
      frameSize,
      (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (frameSize - 1)),
    );

    final nFrames = pcm.length < frameSize ? 0 : 1 + (pcm.length - frameSize) ~/ hop;

    // Passe 1 : chroma normalise par frame, energie, flux spectral.
    // La normalisation de chaque vecteur chroma avant le lissage EMA est
    // cruciale : sans elle, les sections fortes (refrain, batterie) surponderent
    // massivement l'etat interne de l'EMA, causant une derive et un blocage
    // au milieu du morceau.
    final times = <double>[];
    final rawChroma = <List<double>?>[]; // null = frame silencieuse
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
        rawChroma.add(null);
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

      // Normalisation L2 par frame pour rendre l'EMA invariante a la dynamique sonore
      final cNorm = math.sqrt(chroma.fold(0.0, (a, b) => a + b * b));
      if (cNorm > 1e-9) {
        for (int c = 0; c < 12; c++) {
          chroma[c] /= cNorm;
        }
      }
      rawChroma.add(chroma);
    }

    // Passe 2 : lissage EMA du chroma dans le temps (attenue le bruit/transitoires)
    final smoothedChroma = _emaSmoothChroma(rawChroma, chromaSmoothing);

    // Passe 3 : score de chaque accord candidat par frame (chroma normalise).
    final scoresPerFrame = _scoreFrames(smoothedChroma);

    // Passe 4 : hysteresis et debounce avec gestion de perte de support
    final committed = _debounce(
      scoresPerFrame,
      confirmFrames: confirmFrames,
      margin: switchMargin,
      minConfidence: minConfidence,
    );

    final segments = _toSegments(times, committed);
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

  /// Moyenne mobile exponentielle sur le chroma brut, frame par frame.
  /// Les silences reinitialisent l'etat interne pour eviter de propager un
  /// ancien accord apres une pause ou au debut d'une nouvelle section.
  static List<List<double>?> _emaSmoothChroma(List<List<double>?> raw, double alpha) {
    final out = List<List<double>?>.filled(raw.length, null);
    List<double>? prev;
    for (int i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == null) {
        out[i] = null;
        prev = null; // Reinitialise l'EMA sur les silences
        continue;
      }
      List<double> smoothed;
      if (prev == null) {
        smoothed = List<double>.from(c);
      } else {
        smoothed = List<double>.generate(12, (k) => alpha * c[k] + (1 - alpha) * prev![k]);
      }
      out[i] = smoothed;
      prev = smoothed;
    }
    return out;
  }

  /// Pour chaque frame : score de similarite (produit scalaire, chroma
  /// normalise) avec chacun des 24 templates majeur/mineur. null si silence.
  static List<Map<String, double>?> _scoreFrames(List<List<double>?> smoothedChroma) {
    return smoothedChroma.map((c) {
      if (c == null) return null;
      final norm = math.sqrt(c.fold(0.0, (a, b) => a + b * b));
      if (norm <= 1e-9) return null;
      final cn = List<double>.generate(12, (k) => c[k] / norm);
      final scores = <String, double>{};
      _templates.forEach((name, tmpl) {
        double s = 0;
        for (int k = 0; k < 12; k++) {
          s += cn[k] * tmpl[k];
        }
        scores[name] = s;
      });
      return scores;
    }).toList();
  }

  /// Machine a etats hysteresis / debounce :
  /// - Bascule quand un accord candidat maintient l'avantage avec score >= minConfidence
  /// - Libere automatiquement l'accord engage si celui-ci perd son support (score s'effondre)
  ///   ou apres un silence soutenu, empechant le blocage en milieu de morceau.
  static List<String?> _debounce(
    List<Map<String, double>?> scoresPerFrame, {
    required int confirmFrames,
    required double margin,
    required double minConfidence,
  }) {
    final out = List<String?>.filled(scoresPerFrame.length, null);
    String? committed;
    String? candidate;
    int candidateCount = 0;
    int silenceStreak = 0;
    int committedLowStreak = 0;

    for (int i = 0; i < scoresPerFrame.length; i++) {
      final scores = scoresPerFrame[i];
      if (scores == null) {
        silenceStreak++;
        if (silenceStreak >= 4) {
          // Plus de ~180ms de silence : libere l'accord engage pour repartir proprement
          committed = null;
          candidate = null;
          candidateCount = 0;
        }
        out[i] = committed;
        continue;
      }
      silenceStreak = 0;

      String bestName = scores.keys.first;
      double bestScore = -1;
      scores.forEach((name, s) {
        if (s > bestScore) {
          bestScore = s;
          bestName = name;
        }
      });

      if (committed == null) {
        if (bestScore >= minConfidence) committed = bestName;
        out[i] = committed;
        continue;
      }

      final committedScore = scores[committed] ?? -1;

      // Perte de support : l'accord precedent s'effondre
      if (committedScore < minConfidence - 0.08 || (bestScore - committedScore) > 0.15) {
        committedLowStreak++;
      } else {
        committedLowStreak = 0;
      }

      // Si l'accord engage n'a plus de support, on reduit la barriere d'entree
      final bool committedWeak = committedLowStreak >= confirmFrames;
      final effectiveMargin = committedWeak ? 0.0 : margin;
      final effectiveConfirm = committedWeak ? (confirmFrames ~/ 2).clamp(2, confirmFrames) : confirmFrames;

      if (bestName == committed) {
        candidate = null;
        candidateCount = 0;
        out[i] = committed;
        continue;
      }

      if ((bestScore - committedScore) < effectiveMargin || bestScore < minConfidence) {
        // En cas de micro-dip d'une seule frame (transitoire/percussion), ne pas
        // detruire immediatement tout l'historique de confirmation du candidat.
        if (candidateCount > 0) {
          candidateCount--;
        } else {
          candidate = null;
        }
        out[i] = committed;
        continue;
      }

      if (candidate == bestName) {
        candidateCount++;
      } else {
        candidate = bestName;
        candidateCount = 1;
      }

      if (candidateCount >= effectiveConfirm) {
        committed = candidate;
        candidate = null;
        candidateCount = 0;
        committedLowStreak = 0;
      }
      out[i] = committed;
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
