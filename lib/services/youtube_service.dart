import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';

/// Service for searching and extracting audio from YouTube
/// Uses direct Innertube API for search (immune to web parser breakages)
/// and youtube_explode_dart for stream extraction
class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isDisposed = false;

  /// Searches YouTube for songs matching [query].
  Future<List<Song>> searchSongs(String query, {int maxResults = 20}) async {
    if (_isDisposed) return [];

    // Attempt 1: Fast & reliable Innertube search API
    try {
      final songs = await _searchViaInnertube(query, maxResults);
      if (songs.isNotEmpty) return songs;
    } catch (e) {
      _log('Innertube search failed ($e) — falling back to searchContent');
    }

    // Attempt 2: Fallback to youtube_explode searchContent
    try {
      final searchResults = await _yt.search.searchContent(query);
      final songs = <Song>[];
      for (final item in searchResults) {
        if (item is SearchVideo) {
          songs.add(Song(
            id: item.id.value,
            title: item.title,
            artist: item.author,
            durationSeconds: _parseDurationText(item.duration),
            thumbnailUrl: 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg',
            isLocal: false,
          ));
          if (songs.length >= maxResults) break;
        }
      }
      return songs;
    } catch (e) {
      _log('Search fallback failed: $e');
      return [];
    }
  }

  Future<List<Song>> _searchViaInnertube(String query, int maxResults) async {
    const endpoint = 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
    final payload = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20240101.00.00',
          'hl': 'en',
          'gl': 'US',
        }
      },
      'query': query,
    };

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw HttpException('Innertube returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final contents = data['contents']?['twoColumnSearchResultsRenderer']
        ?['primaryContents']?['sectionListRenderer']?['contents'] as List?;

    if (contents == null) return [];

    final results = <Song>[];
    for (final section in contents) {
      final itemSection = section['itemSectionRenderer']?['contents'] as List?;
      if (itemSection == null) continue;

      for (final item in itemSection) {
        final vr = item['videoRenderer'];
        if (vr == null) continue;

        try {
          final id = vr['videoId'] as String?;
          final title = vr['title']?['runs']?[0]?['text'] as String? ??
              vr['title']?['simpleText'] as String?;
          final author = vr['ownerText']?['runs']?[0]?['text'] as String? ??
              vr['shortBylineText']?['runs']?[0]?['text'] as String? ??
              'Unknown Artist';
          final durationText = vr['lengthText']?['simpleText'] as String?;
          final thumbs = vr['thumbnail']?['thumbnails'] as List?;
          final thumb = (thumbs != null && thumbs.isNotEmpty)
              ? thumbs.last['url'] as String?
              : (id != null ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null);

          if (id != null && title != null && title.isNotEmpty) {
            results.add(Song(
              id: id,
              title: title,
              artist: author,
              durationSeconds: _parseDurationText(durationText),
              thumbnailUrl: thumb,
              isLocal: false,
            ));
            if (results.length >= maxResults) return results;
          }
        } catch (_) {}
      }
    }

    return results;
  }

  int? _parseDurationText(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return null;
  }

  // Fast stream URL cache to make re-plays instantaneous
  final Map<String, String> _streamCache = {};

  // Cache of downloaded temp files per videoId
  final Map<String, File> _tempFileCache = {};
  final Map<String, Future<File?>> _inFlightDownloads = {};

  /// Gets the best audio-only MP4/AAC stream info for [videoId].
  /// IMPORTANT: Windows Media Foundation requires MP4/AAC — WebM/Opus will NOT play.
  /// The android client is used because it returns 3 MP4 streams (androidSdkless only returns WebM).
  Future<AudioOnlyStreamInfo?> _getBestStreamInfo(String videoId) async {
    // Primary: android client returns both MP4 and WebM — we need MP4
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.android],
      );
      final audioOnly = manifest.audioOnly;
      _log('Android client: ${audioOnly.length} audio streams total');

      // Must have MP4/AAC — Windows cannot play WebM
      final mp4 = audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      _log('MP4 streams available: ${mp4.length}');

      if (mp4.isNotEmpty) {
        final best = mp4.withHighestBitrate();
        _log('Selected MP4 stream: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps');
        return best;
      }
    } catch (e) {
      _log('Android client failed: $e');
    }

    // Fallback: tv client (also returns MP4 streams)
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.tv],
      );
      final mp4 = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (mp4.isNotEmpty) {
        final best = mp4.withHighestBitrate();
        _log('TV client fallback: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps MP4');
        return best;
      }
    } catch (e) {
      _log('TV client failed: $e');
    }

    // Last resort: default client, any format
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioOnly = manifest.audioOnly;
      if (audioOnly.isEmpty) return null;
      // Try MP4 first
      final mp4 = audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4.isNotEmpty) return mp4.withHighestBitrate();
      // WebM as absolute last resort (may not play on Windows)
      _log('WARNING: Only WebM streams available — may not play on Windows');
      return audioOnly.withHighestBitrate();
    } catch (e) {
      _log('Default client also failed: $e');
    }

    _log('ERROR: All strategies failed for $videoId');
    return null;
  }


  /// Downloads the audio stream for [videoId] to a temp file.
  /// Returns the [File] on success, null on failure.
  /// Uses a cache so the same song is only downloaded once per session.
  Future<File?> downloadToTempFile(String videoId) async {
    if (_isDisposed) return null;

    // Return cached file if still on disk
    if (_tempFileCache.containsKey(videoId)) {
      final f = _tempFileCache[videoId]!;
      if (f.existsSync() && f.lengthSync() > 0) {
        _log('Returning cached file for $videoId');
        return f;
      }
      _tempFileCache.remove(videoId);
    }

    // Deduplicate concurrent requests for same videoId
    if (_inFlightDownloads.containsKey(videoId)) {
      _log('Waiting for in-flight download for $videoId');
      return await _inFlightDownloads[videoId];
    }

    final future = _doDownload(videoId);
    _inFlightDownloads[videoId] = future;
    try {
      return await future;
    } finally {
      _inFlightDownloads.remove(videoId);
    }
  }

  Future<File?> _doDownload(String videoId) async {
    try {
      _log('Starting download for $videoId');
      final streamInfo = await _getBestStreamInfo(videoId);
      if (streamInfo == null) {
        _log('ERROR: No stream info found for $videoId');
        return null;
      }
      _log('Downloading ${streamInfo.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps '
          '${streamInfo.container.name} stream for $videoId');

      final ext = streamInfo.container.name.toLowerCase() == 'webm' ? 'webm' : 'm4a';
      final tmpDir = Directory.systemTemp;
      final tmpFile = File('${tmpDir.path}/me_vazo_$videoId.$ext');

      // Delete stale file if exists
      if (tmpFile.existsSync()) {
        tmpFile.deleteSync();
        _log('Deleted stale temp file');
      }

      final sink = tmpFile.openWrite();
      try {
        // streamsClient.get() handles all auth, signatures, and chunking internally
        _log('Piping stream to ${tmpFile.path}');
        await _yt.videos.streamsClient.get(streamInfo).pipe(sink);
        _log('Stream pipe completed');
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (!tmpFile.existsSync() || tmpFile.lengthSync() == 0) {
        _log('ERROR: Downloaded file is empty for $videoId');
        return null;
      }

      final sizeMb = (tmpFile.lengthSync() / 1024 / 1024).toStringAsFixed(1);
      _log('Download complete: ${tmpFile.path} ($sizeMb MB)');
      _tempFileCache[videoId] = tmpFile;
      return tmpFile;
    } catch (e, st) {
      _log('Download error for $videoId: $e\n$st');
      return null;
    }
  }


  /// Gets the best audio-only stream URL for [videoId] (web fallback only).

  /// Resolves the direct audio stream URL for a YouTube video:
  /// Uses official mobile API clients (iOS & Android) to prevent YouTube bot blocking/400 errors.
  Future<String?> getAudioStreamUrl(String videoId) async {
    if (_isDisposed) return null;
    if (_streamCache.containsKey(videoId)) return _streamCache[videoId];

    // Attempt 1: Standard YouTube manifest (fast, direct, and compatible without 403)
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioOnly = manifest.audioOnly;

      if (audioOnly.isNotEmpty) {
        // Universal compatibility: prioritize MP4/AAC (itag 140) natively decoded by Windows & mobile
        final mp4Streams = audioOnly.where((s) =>
            s.container.name.toLowerCase() == 'mp4' ||
            s.codec.mimeType.contains('mp4') ||
            s.codec.subtype.contains('mp4'));

        if (mp4Streams.isNotEmpty) {
          final best = mp4Streams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          final url = best.url.toString();
          _log('Using standard MP4/AAC audio stream (${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)');
          _streamCache[videoId] = url;
          return url;
        }

        // Fallback to highest bitrate audio (e.g., Opus/WebM)
        final best = audioOnly.withHighestBitrate();
        final url = best.url.toString();
        _log('Using standard audio stream (${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)');
        _streamCache[videoId] = url;
        return url;
      }

      // Muxed stream fallback
      final muxed = manifest.muxed;
      if (muxed.isNotEmpty) {
        final best = muxed.withHighestBitrate();
        final url = best.url.toString();
        _log('Fallback: using standard muxed stream (${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)');
        _streamCache[videoId] = url;
        return url;
      }
    } catch (e) {
      _log('Standard manifest failed ($e) — trying mobile fallback');
    }

    // Attempt 2: Fallback to Android client
    try {
      final manifest = await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.android],
      );
      final audioOnly = manifest.audioOnly;
      if (audioOnly.isNotEmpty) {
        final mp4Streams = audioOnly.where((s) =>
            s.container.name.toLowerCase() == 'mp4' ||
            s.codec.mimeType.contains('mp4') ||
            s.codec.subtype.contains('mp4'));

        if (mp4Streams.isNotEmpty) {
          final best = mp4Streams.reduce((a, b) =>
              a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
          final url = best.url.toString();
          _log('Fallback: using Android MP4 stream (${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)');
          _streamCache[videoId] = url;
          return url;
        }

        final best = audioOnly.withHighestBitrate();
        final url = best.url.toString();
        _streamCache[videoId] = url;
        return url;
      }
    } catch (e) {
      _log('Android manifest fallback failed: $e');
    }

    return null;
  }

  /// Gets detailed info for a specific video.
  Future<Song?> getVideoDetails(String videoId) async {
    if (_isDisposed) return null;

    try {
      final video = await _yt.videos.get(videoId);
      return Song.fromYoutubeExplode(video);
    } catch (e) {
      _log('Video details error: $e');
      return null;
    }
  }

  /// Returns popular music for the discover tab.
  Future<List<Song>> getTrendingMusic() async {
    return searchSongs('top music hits', maxResults: 10);
  }

  void _log(String message) => debugPrint('[YoutubeService] $message');

  void dispose() {
    _isDisposed = true;
    _yt.close();
    // Clean up temp files
    for (final file in _tempFileCache.values) {
      try { file.deleteSync(); } catch (_) {}
    }
    _tempFileCache.clear();
  }
}
