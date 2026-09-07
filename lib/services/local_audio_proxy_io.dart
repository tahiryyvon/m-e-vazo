import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Lightweight in-app loopback proxy server to stream YouTube audio directly
/// to media_kit on Windows without 403 Forbidden or platform restrictions.
///
/// Features:
/// - Prioritizes muxed MP4 streams (ratebypass=yes) which completely eliminates
///   YouTube's 403 Forbidden bandwidth throttling that hits standalone audio streams.
/// - Media_kit (libmpv) decodes the audio track natively from the MP4 container.
/// - Instant start (< 1 second) via loopback HTTP streaming with immediate flush.
class LocalAudioProxy {
  static final LocalAudioProxy instance = LocalAudioProxy._internal();
  LocalAudioProxy._internal();

  HttpServer? _server;
  final YoutubeExplode _yt = YoutubeExplode();
  int _port = 0;
  bool _isStarting = false;

  // Stream info cache to avoid multiple manifest lookups for the same song
  final Map<String, StreamInfo> _streamInfoCache = {};
  final Map<String, Future<StreamInfo?>> _inFlightFetches = {};

  int get port => _port;

  /// Starts the local HTTP proxy server if not already running.
  Future<int> start() async {
    if (_server != null) return _port;
    if (_isStarting) {
      while (_isStarting) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _port;
    }

    _isStarting = true;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[LocalAudioProxy] Started on http://127.0.0.1:$_port');
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('[LocalAudioProxy] Server error: $e');
      });
    } catch (e) {
      debugPrint('[LocalAudioProxy] Failed to bind server: $e');
    } finally {
      _isStarting = false;
    }
    return _port;
  }

  /// Returns the loopback streaming URL for [videoId] with .m4a extension.
  Future<String> getProxyStreamUrl(String videoId) async {
    final serverPort = await start();
    // Warm up manifest fetch in background so HEAD/GET has it ready
    unawaited(_getStreamInfo(videoId));
    return 'http://127.0.0.1:$serverPort/audio_$videoId.m4a';
  }

  Future<StreamInfo?> _getStreamInfo(String videoId) async {
    if (_streamInfoCache.containsKey(videoId)) {
      return _streamInfoCache[videoId];
    }
    if (_inFlightFetches.containsKey(videoId)) {
      return await _inFlightFetches[videoId];
    }

    final future = () async {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);

        // 1. Prioritize muxed MP4 (e.g. 360p itag 18):
        // YouTube attaches ratebypass=yes to muxed streams, which completely eliminates
        // the 403 Forbidden bandwidth throttling that cuts off standalone audio streams at ~384KB.
        // media_kit (libmpv) natively decodes the AAC audio track directly from the MP4 container.
        final muxedMp4 = manifest.muxed
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .toList();
        if (muxedMp4.isNotEmpty) {
          final selected = muxedMp4.first; // 360p / fast & lightweight
          _streamInfoCache[videoId] = selected;
          return selected;
        }

        // 2. Fallback to audio-only
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final selected = audioStreams
                  .where((s) => s.container.name.toLowerCase() == 'mp4')
                  .firstOrNull ??
              audioStreams.withHighestBitrate();
          _streamInfoCache[videoId] = selected;
          return selected;
        }

        return null;
      } catch (e) {
        debugPrint('[LocalAudioProxy] Error getting manifest for $videoId: $e');
        return null;
      } finally {
        _inFlightFetches.remove(videoId);
      }
    }();

    _inFlightFetches[videoId] = future;
    return await future;
  }

  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final match = RegExp(r'/audio_([a-zA-Z0-9_\-]+)\.m4a').firstMatch(path);
    final videoId = match?.group(1);
    final clientRange = request.headers.value('range');

    debugPrint('[LocalAudioProxy] >>> Incoming ${request.method} $path (Range: $clientRange)');

    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      try { await request.response.close(); } catch (_) {}
      return;
    }

    try {
      final selectedStream = await _getStreamInfo(videoId);
      if (selectedStream == null) {
        debugPrint('[LocalAudioProxy] Stream info null for $videoId');
        request.response.statusCode = HttpStatus.notFound;
        try { await request.response.close(); } catch (_) {}
        return;
      }

      final contentType = selectedStream.container.name.toLowerCase() == 'webm'
          ? 'audio/webm'
          : 'video/mp4';

      // Media player sends HEAD request first to detect format and duration
      if (request.method == 'HEAD') {
        debugPrint('[LocalAudioProxy] Responding to HEAD with size ${selectedStream.size.totalBytes}');
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
            HttpHeaders.contentLengthHeader, selectedStream.size.totalBytes);
        try { await request.response.close(); } catch (_) {}
        return;
      }

      // Handle GET streaming request
      final ytRequest = http.Request('GET', selectedStream.url);
      ytRequest.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      ytRequest.headers['Range'] = clientRange ?? 'bytes=0-';

      final client = http.Client();
      final streamedResponse = await client.send(ytRequest);
      debugPrint('[LocalAudioProxy] Upstream YouTube status: ${streamedResponse.statusCode}, contentLength: ${streamedResponse.contentLength}, contentRange: ${streamedResponse.headers["content-range"]}');

      request.response.statusCode = streamedResponse.statusCode;
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      if (streamedResponse.contentLength != null) {
        request.response.headers.set(
            HttpHeaders.contentLengthHeader, streamedResponse.contentLength!);
      }

      final contentRange = streamedResponse.headers['content-range'];
      if (contentRange != null) {
        request.response.headers.set('Content-Range', contentRange);
      }

      // Stream chunks with immediate flush so playback starts instantly
      int totalBytesSent = 0;
      try {
        await for (final chunk in streamedResponse.stream) {
          totalBytesSent += chunk.length;
          request.response.add(chunk);
          await request.response.flush();
        }
        debugPrint('[LocalAudioProxy] Successfully sent $totalBytesSent bytes to client');
      } catch (e) {
        debugPrint('[LocalAudioProxy] Client disconnected after $totalBytesSent bytes ($e)');
      } finally {
        client.close();
      }

      try { await request.response.close(); } catch (_) {}
    } catch (e) {
      debugPrint('[LocalAudioProxy] Stream proxy error for $videoId: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _streamInfoCache.clear();
    _inFlightFetches.clear();
    _yt.close();
  }
}
