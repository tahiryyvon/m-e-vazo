import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/services/stream_chord_analyzer.dart';

void main() {
  test('rejects oversized audio before invoking analysis', () async {
    final analyzer = StreamChordAnalyzer(
      maxDownloadBytes: 2,
      createClient: () => MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      analyzeFile: (_) async => fail('Oversized download must not be analyzed'),
    );
    await expectLater(analyzer.analyze(Uri.parse('http://127.0.0.1/audio'),
        isCurrent: () => true), throwsStateError);
  });
  final uri = Uri.parse('http://127.0.0.1/audio_test.m4a');
  test('analyzes complete playback stream and removes temporary file',
      () async {
    String? analyzedPath;
    final expected = SongChordsResult(chords: [
      ChordEvent(timestamp: const Duration(seconds: 7), chordName: 'C'),
    ]);
    final analyzer = StreamChordAnalyzer(
      createClient: () => MockClient((request) async {
        expect(request.url, uri);
        expect(request.headers['Range'], 'bytes=0-');
        return http.Response.bytes([1, 2, 3], 206,
            headers: {
              'content-range': 'bytes 0-2/3',
              'content-type': 'audio/mp4',
            });
      }),
      analyzeFile: (path) async {
        analyzedPath = path;
        expect(await File(path).readAsBytes(), [1, 2, 3]);
        return expected;
      },
    );
    final result = await analyzer.analyze(uri, isCurrent: () => true);
    expect(result, same(expected)); // no lyric-derived retiming
    expect(await File(analyzedPath!).exists(), isFalse);
  });

  for (final range in ['bytes 0-1/3', 'bytes 1-2/3', 'bytes 0-2/*']) {
    test('rejects partial or unverifiable range $range', () async {
      final analyzer = StreamChordAnalyzer(
        createClient: () => MockClient((_) async => http.Response.bytes(
            [1, 2], 206,
            headers: {'content-range': range})),
        analyzeFile: (_) async => fail('Partial audio must not be analyzed'),
      );
      await expectLater(
          analyzer.analyze(uri, isCurrent: () => true), throwsStateError);
    });
  }

  test('rejects a body shorter than the full range', () async {
    final analyzer = StreamChordAnalyzer(
      createClient: () => MockClient((_) async => http.Response.bytes(
          [1, 2], 206,
          headers: {'content-range': 'bytes 0-2/3'})),
      analyzeFile: (_) async => fail('Truncated audio must not be analyzed'),
    );
    await expectLater(
        analyzer.analyze(uri, isCurrent: () => true), throwsStateError);
  });

  test('does not analyze a request for a superseded song', () async {
    final analyzer = StreamChordAnalyzer(
      createClient: () =>
          MockClient((_) async => http.Response.bytes([1], 200)),
      analyzeFile: (_) async => fail('Superseded audio must not be analyzed'),
    );
    expect(await analyzer.analyze(uri, isCurrent: () => false), isNull);
  });
}
