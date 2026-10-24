import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/chord_event.dart';
import 'audio_chord_detector_service.dart';

/// Analyze the same stream as playback, preserving its audio time origin.
/// Never publish a timeline from a truncated download.
class StreamChordAnalyzer {
  final http.Client Function() createClient;
  final Future<SongChordsResult?> Function(String) analyzeFile;

  StreamChordAnalyzer({
    http.Client Function()? createClient,
    Future<SongChordsResult?> Function(String)? analyzeFile,
  })  : createClient = createClient ?? http.Client.new,
        analyzeFile = analyzeFile ?? AudioChordDetectorService.analyzeAudioFile;

  Future<SongChordsResult?> analyze(
    Uri uri, {
    required bool Function() isCurrent,
  }) async {
    final client = createClient();
    Directory? directory;
    IOSink? sink;
    try {
      final request = http.Request('GET', uri);
      request.headers['Range'] = 'bytes=0-';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (!isCurrent()) return null;
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw StateError('Audio download failed: ${response.statusCode}');
      }
      int? expectedBytes = response.contentLength;
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes 0-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        if (match == null || int.parse(match[1]!) + 1 != int.parse(match[2]!)) {
          throw StateError('Incomplete audio range');
        }
        expectedBytes = int.parse(match[2]!);
      }
      directory = await Directory.systemTemp.createTemp('stream_chords_');
      final extension =
          (response.headers['content-type'] ?? '').contains('webm')
              ? 'webm'
              : 'm4a';
      final file = File('${directory.path}/audio.$extension');
      sink = file.openWrite();
      var receivedBytes = 0;
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        if (!isCurrent()) return null;
        receivedBytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (receivedBytes == 0 ||
          (expectedBytes != null && receivedBytes != expectedBytes)) {
        throw StateError('Truncated audio download');
      }
      if (!isCurrent()) return null;
      return await analyzeFile(file.path);
    } finally {
      client.close();
      if (sink != null) await sink.close();
      if (directory != null) await directory.delete(recursive: true);
    }
  }
}
