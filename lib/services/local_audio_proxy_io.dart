import 'dart:async';
import 'dart:io';
import 'dart:math';
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
  Future<int>? _starting;
  final String _token = List.generate(32, (_) => Random.secure().nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final Map<String, DateTime> _cachedAt = {};

  // Stream info cache to avoid multiple manifest lookups for the same song
  final Map<String, StreamInfo> _streamInfoCache = {};
  final Map<String, Future<StreamInfo?>> _inFlightFetches = {};

  int get port => _port;

  /// Starts the local HTTP proxy server if not already running.
  Future<int> start() async {
    if (_server != null) return _port;
    return _starting ??= _bind();
  }

  Future<int> _bind() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[LocalAudioProxy] Started on http://127.0.0.1:$_port');
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('[LocalAudioProxy] Server error: $e');
      });
    } catch (e) {
      debugPrint('[LocalAudioProxy] Failed to bind server: $e');
      rethrow;
    } finally {
      _starting = null;
    }
    return _port;
  }

  /// Returns the loopback streaming URL for [videoId] with .m4a extension.
  Future<String> getProxyStreamUrl(String videoId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
    }
    final serverPort = await start();
    // Warm up manifest fetch in background so HEAD/GET has it ready
    unawaited(_getStreamInfo(videoId));
    return 'http://127.0.0.1:$serverPort/$_token/audio_$videoId.m4a';
  }

  void _cache(String id, StreamInfo stream) {
    if (_streamInfoCache.length >= 64) {
      final oldest = _streamInfoCache.keys.first;
      _streamInfoCache.remove(oldest);
      _cachedAt.remove(oldest);
    }
    _streamInfoCache[id] = stream;
    _cachedAt[id] = DateTime.now();
  }

  Future<StreamInfo?> _getStreamInfo(String videoId) async {
    final cachedAt = _cachedAt[videoId];
    if (cachedAt != null && DateTime.now().difference(cachedAt) > const Duration(minutes: 15)) {
      _streamInfoCache.remove(videoId);
      _cachedAt.remove(videoId);
    }
    if (_streamInfoCache.containsKey(videoId)) {
      return _streamInfoCache[videoId];
    }
    if (_inFlightFetches.containsKey(videoId)) {
      return await _inFlightFetches[videoId];
    }

    final future = () async {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId)
            .timeout(const Duration(seconds: 20));

        // 1. Prioritize muxed MP4 (e.g. 360p itag 18):
        // YouTube attaches ratebypass=yes to muxed streams, which completely eliminates
        // the 403 Forbidden bandwidth throttling that cuts off standalone audio streams at ~384KB.
        // media_kit (libmpv) natively decodes the AAC audio track directly from the MP4 container.
        final muxedMp4 = manifest.muxed
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .toList();
        if (muxedMp4.isNotEmpty) {
          final selected = muxedMp4.first; // 360p / fast & lightweight
          _cache(videoId, selected);
          return selected;
        }

        // 2. Fallback to audio-only
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final selected = audioStreams
                  .where((s) => s.container.name.toLowerCase() == 'mp4')
                  .firstOrNull ??
              audioStreams.withHighestBitrate();
          _cache(videoId, selected);
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
    if (!path.startsWith('/$_token/') ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      try { await request.response.close(); } catch (_) {}
      return;
    }
    final match = RegExp(r'^audio_([a-zA-Z0-9_-]{11})\.m4a$')
        .firstMatch(path.substring(_token.length + 2));
    final videoId = match?.group(1);
    final clientRange = request.headers.value('range');

    debugPrint('[LocalAudioProxy] Incoming ${request.method} (Range: $clientRange)');

    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      try { await request.response.close(); } catch (_) {}
      return;
    }

    http.Client? client;
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
          : 'audio/mp4';

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

      if (clientRange != null && clientRange.isNotEmpty) {
        ytRequest.headers['Range'] = clientRange;
      }

      client = http.Client();
      final streamedResponse = await client.send(ytRequest).timeout(const Duration(seconds: 30));
      debugPrint('[LocalAudioProxy] Upstream YouTube status: ${streamedResponse.statusCode}, contentLength: ${streamedResponse.contentLength}, contentRange: ${streamedResponse.headers["content-range"]}');

      if (streamedResponse.statusCode != HttpStatus.ok &&
          streamedResponse.statusCode != HttpStatus.partialContent) {
        debugPrint('[LocalAudioProxy] Upstream error status: ${streamedResponse.statusCode}');
        request.response.statusCode = streamedResponse.statusCode;
        try { await request.response.close(); } catch (_) {}
        return;
      }

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
        await for (final chunk in streamedResponse.stream.timeout(const Duration(seconds: 30))) {
          totalBytesSent += chunk.length;
          request.response.add(chunk);
          await request.response.flush();
        }
        debugPrint('[LocalAudioProxy] Successfully sent $totalBytesSent bytes to client');
      } catch (e) {
        debugPrint('[LocalAudioProxy] Client disconnected after $totalBytesSent bytes ($e)');
      }

      try { await request.response.close(); } catch (_) {}
    } catch (e) {
      debugPrint('[LocalAudioProxy] Stream proxy error for $videoId: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    } finally {
      client?.close();
    }
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _streamInfoCache.clear();
    _cachedAt.clear();
    _inFlightFetches.clear();
    _yt.close();
  }
}
