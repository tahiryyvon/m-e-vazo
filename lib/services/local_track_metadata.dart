import 'package:audio_decoder/audio_decoder.dart' as ad;
import 'package:flutter/foundation.dart';
import 'audio_tags.dart';
import 'browser_audio_file.dart';

/// What the lyrics lookup should use for a local file.
class LocalTrackInfo {
  final String title;
  final String artist;
  final int? durationSeconds;
  const LocalTrackInfo(this.title, this.artist, this.durationSeconds);
}

/// Gathers the best title, artist and duration for a local file before the
/// LRCLIB lookup:
/// - title / artist: embedded tags, else the cleaned file name;
/// - duration: the real duration read from the audio container (fast, no
///   full decode on Android / Windows; one decode of the played file in the
///   browser), else a known duration, else the tag's declared length.
/// The real duration is preferred because tag lengths are often wrong.
class LocalTrackMetadata {
  final Future<AudioTags?> Function(String path) readTags;
  final Future<int?> Function(String path) probeDuration;

  LocalTrackMetadata({
    Future<AudioTags?> Function(String path)? readTags,
    Future<int?> Function(String path)? probeDuration,
  })  : readTags = readTags ?? _readTags,
        probeDuration = probeDuration ?? _probeDuration;

  static const Duration _probeTimeout = Duration(seconds: 8);

  Future<LocalTrackInfo> resolve({
    required String path,
    required String title,
    required String artist,
    int? knownDuration,
  }) async {
    final tagsFuture = _safely(() => readTags(path));
    final durationFuture = _safely(() => probeDuration(path));
    final tags = await tagsFuture;
    final realDuration = await durationFuture;
    return LocalTrackInfo(
      tags?.title ?? title,
      tags?.artist ?? artist,
      realDuration ?? knownDuration ?? tags?.durationSeconds,
    );
  }

  /// Runs a metadata source; a failure or a slow answer only means "unknown".
  static Future<T?> _safely<T>(Future<T?> Function() run) async {
    try {
      return await run().timeout(_probeTimeout);
    } catch (e) {
      debugPrint('[LocalTrackMetadata] skipped: $e');
      return null;
    }
  }

  static Future<AudioTags?> _readTags(String path) async {
    if (kIsWeb || path.startsWith('content://')) return null;
    return AudioTagReader.read(path);
  }

  static Future<int?> _probeDuration(String path) async {
    final ad.AudioInfo info;
    if (kIsWeb) {
      final bytes = await readBlobUrl(path);
      if (bytes == null) return null;
      info = await ad.AudioDecoder.getAudioInfoBytes(bytes, formatHint: 'audio');
    } else {
      info = await ad.AudioDecoder.getAudioInfo(path);
    }
    final seconds = (info.duration.inMilliseconds / 1000).round();
    return seconds > 0 ? seconds : null;
  }
}
