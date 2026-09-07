import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Web implementation of LocalAudioProxy (direct stream URL without raw TCP server)
class LocalAudioProxy {
  static final LocalAudioProxy instance = LocalAudioProxy._internal();
  LocalAudioProxy._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  int get port => 0;

  Future<int> start() async => 0;

  Future<String> getProxyStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      final selectedStream = audioStreams.where((s) => s.container.name.toLowerCase() == 'mp4').firstOrNull ??
          audioStreams.withHighestBitrate();
      return selectedStream.url.toString();
    } catch (e) {
      debugPrint('[LocalAudioProxy Web] Stream extraction error: $e');
      rethrow;
    }
  }

  void dispose() {
    _yt.close();
  }
}
