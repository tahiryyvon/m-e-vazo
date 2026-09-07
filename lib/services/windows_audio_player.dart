import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Windows audio player backed by media_kit (libmpv).
/// Avoids Windows Media Foundation (WMF) restrictions that prevent
/// playback from loopback proxy URLs or direct YouTube CDN URLs.
class WindowsAudioPlayer {
  final Player _player = Player();

  Stream<bool> get playingStream => _player.stream.playing;
  Stream<Duration> get positionStream => _player.stream.position;
  Stream<Duration?> get durationStream => _player.stream.duration.map(
        (d) => d == Duration.zero ? null : d,
      );
  Stream<bool> get completedStream => _player.stream.completed;
  Stream<String?> get errorStream => _player.stream.error;
  Stream<bool> get bufferingStream => _player.stream.buffering;

  bool get playing => _player.state.playing;
  Duration get position => _player.state.position;
  Duration? get duration {
    final d = _player.state.duration;
    return d == Duration.zero ? null : d;
  }

  WindowsAudioPlayer() {
    _player.stream.playing.listen((v) => debugPrint('[WindowsAudioPlayer] playing=$v'));
    _player.stream.buffering.listen((v) => debugPrint('[WindowsAudioPlayer] buffering=$v'));
    _player.stream.error.listen((e) {
      if (e.isNotEmpty) debugPrint('[WindowsAudioPlayer] error=$e');
    });
  }

  /// Load and play a URL (YouTube proxy URL or direct stream)
  Future<void> playUrl(String url) async {
    debugPrint('[WindowsAudioPlayer] Opening URL: $url');
    try {
      await _player.open(Media(url), play: true);
      debugPrint('[WindowsAudioPlayer] open() completed for $url');
    } catch (e) {
      debugPrint('[WindowsAudioPlayer] playUrl error: $e');
      rethrow;
    }
  }

  /// Play a local file on Windows (normalizes slashes to prevent libmpv escape errors)
  Future<void> playFile(String path) async {
    debugPrint('[WindowsAudioPlayer] Playing local file: $path');
    try {
      final file = File(path);
      final resource = file.existsSync() ? file.uri.toString() : path.replaceAll(r'\', '/');
      await _player.open(Media(resource), play: true);
      debugPrint('[WindowsAudioPlayer] playFile open() completed');
    } catch (e) {
      debugPrint('[WindowsAudioPlayer] playFile error: $e');
      rethrow;
    }
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> stop() => _player.stop();

  Future<void> setVolume(double volume) =>
      _player.setVolume((volume * 100).clamp(0, 100));

  void dispose() => _player.dispose();
}
