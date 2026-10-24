import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/chord_event.dart';
import 'songsterr_service.dart';

/// Native NNLS / HMM analysis. A failed engine must not trigger guessed chords.
class ChordinoService {
  static Future<SongChordsResult> analyzeWav(
      String path, double durationSeconds) async {
    final roots = [
      '${File(Platform.resolvedExecutable).parent.path}/data/chordino',
      '${Directory.current.path}/tools/chordino-runtime',
    ];
    String? root;
    for (final candidate in roots) {
      if (await File('$candidate/host/sonic-annotator.exe').exists() &&
          await File('$candidate/plugins/nnls-chroma.dll').exists()) {
        root = candidate;
        break;
      }
    }
    if (root == null) {
      throw StateError('Chordino absent: run tools/setup_chordino.ps1');
    }
    final process = await Process.start('$root/host/sonic-annotator.exe', [
      '-d',
      'vamp:nnls-chroma:chordino:simplechord',
      File(path).absolute.path,
      '-w',
      'csv',
      '--csv-stdout',
      '--csv-omit-filename',
    ], environment: {
      'VAMP_PATH': Directory('$root/plugins').absolute.path
    });
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode =
          await process.exitCode.timeout(const Duration(minutes: 3));
      final csv = await output;
      final error = await errors;
      if (exitCode != 0) {
        throw StateError('Chordino failed ($exitCode): $error');
      }
      return parseCsv(csv, durationSeconds);
    } on TimeoutException {
      process.kill();
      await Future.wait([output, errors]);
      rethrow;
    }
  }

  /// Preserve no-chord boundaries; reduce ornamental variants for the playing
  /// view without inventing roots or changing major/minor quality.
  static SongChordsResult parseCsv(String csv, double durationSeconds) {
    final segments = <(double, String?)>[];
    for (final line in const LineSplitter().convert(csv)) {
      if (line.trim().isEmpty) continue;
      final match =
          RegExp(r'^([0-9]+(?:\.[0-9]+)?),"([^"]+)"$').firstMatch(line.trim());
      if (match == null) throw FormatException('Invalid Chordino output', line);
      final time = double.parse(match[1]!);
      if (!time.isFinite ||
          time < 0 ||
          time > durationSeconds + 0.1 ||
          (segments.isNotEmpty && time <= segments.last.$1)) {
        throw FormatException('Invalid Chordino timestamp', line);
      }
      final label = match[2]!;
      String? name;
      if (label != 'N' && label != 'X') {
        final chord = RegExp(r'^([A-G][#b]?)(.*)$').firstMatch(label);
        if (chord == null) throw FormatException('Invalid chord', label);
        final suffix = chord[2]!.split('/').first;
        // Diminished/augmented/suspended harmonies cannot safely become triads.
        if (!suffix.contains('dim') &&
            !suffix.contains('aug') &&
            !suffix.contains('sus') &&
            !suffix.contains('+') &&
            !suffix.contains('b5') &&
            suffix != '5') {
          final minor = suffix.startsWith('m') && !suffix.startsWith('maj');
          name = '${chord[1]}${minor ? 'm' : ''}';
          const aliases = {
            'C#': 'Db',
            'D#': 'Eb',
            'G#': 'Ab',
            'A#': 'Bb',
            'Dbm': 'C#m',
            'Gbm': 'F#m',
            'Abm': 'G#m',
            'A#m': 'Bbm',
            'D#m': 'Ebm',
            'Gb': 'F#'
          };
          name = aliases[name] ?? name;
        }
      }
      // Even an identical label is retained initially for timestamp validation.
      segments.add((time.clamp(0, durationSeconds), name));
    }
    if (segments.isEmpty) throw const FormatException('Empty Chordino output');
    final merged = <(double, String?)>[];
    for (final segment in segments) {
      if (merged.isEmpty || merged.last.$2 != segment.$2) merged.add(segment);
    }
    final events = <ChordEvent>[];
    for (var i = 0; i < merged.length; i++) {
      final name = merged[i].$2;
      if (name == null) continue;
      final start = (merged[i].$1 * 1000).round();
      final end =
          ((i + 1 < merged.length ? merged[i + 1].$1 : durationSeconds) * 1000)
              .round();
      // Do not display tiny fragments, nor stretch the previous chord over them.
      if (end - start < 400) continue;
      events.add(ChordEvent(
          timestamp: Duration(milliseconds: start),
          chordName: name,
          durationMs: end - start,
          fretPositions: SongsterrService.standardChordPositions[name]));
    }
    return SongChordsResult(
        chords: events,
        tuning: 'E A D G B E',
        analysisMethod: 'Chordino · accords simplifiés estimés');
  }
}
