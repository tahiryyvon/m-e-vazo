import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

/// Synchronized lyrics service via LRCLIB
/// 100% free, no authentication required
/// https://lrclib.net/docs
class LrcLibService {
  static const String _baseUrl = 'https://lrclib.net/api';
  static const Duration _timeout = Duration(seconds: 10);

  /// Fetches synchronized lyrics for a song.
  ///
  /// Falls back to plain lyrics if synced are unavailable.
  /// Falls back to search endpoint if exact match fails.
  Future<List<LyricLine>?> fetchSyncedLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? duration,
  }) async {
    // Attempt 1: Exact match GET endpoint
    final result = await _fetchExact(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      duration: duration,
    );
    if (result != null) return result;

    // Attempt 2: Search endpoint with "$artistName $trackName"
    final searchResult = await _fetchBySearch(
      query: '$artistName $trackName',
      trackName: trackName,
      artistName: artistName,
    );
    if (searchResult != null) return searchResult;

    // Attempt 3: Search endpoint with trackName alone
    return await _fetchBySearch(
      query: trackName,
      trackName: trackName,
      artistName: artistName,
    );
  }

  Future<List<LyricLine>?> _fetchExact({
    required String trackName,
    required String artistName,
    String? albumName,
    int? duration,
  }) async {
    try {
      final queryParams = <String, String>{
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        if (duration != null && duration > 0) 'duration': duration.toString(),
      };

      final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: queryParams);
      final response = await http
          .get(uri, headers: {'User-Agent': 'GuitarLyricsPlayer/1.0 (https://github.com)'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseResponse(data);
      }
    } catch (e) {
      debugPrint('[LrcLibService] Exact fetch error: $e');
    }
    return null;
  }

  Future<List<LyricLine>?> _fetchBySearch({
    required String query,
    required String trackName,
    required String artistName,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/search')
          .replace(queryParameters: {'q': query});

      final response = await http
          .get(uri, headers: {'User-Agent': 'GuitarLyricsPlayer/1.0'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final results = jsonDecode(response.body) as List<dynamic>;
        if (results.isEmpty) return null;

        // Find best match by title similarity
        Map<String, dynamic>? best;
        double bestScore = 0;

        for (final item in results.cast<Map<String, dynamic>>()) {
          final itemTitle = (item['trackName'] as String? ?? '').toLowerCase();
          final itemArtist = (item['artistName'] as String? ?? '').toLowerCase();
          final score = _similarity(itemTitle, trackName.toLowerCase()) +
              _similarity(itemArtist, artistName.toLowerCase());
          if (score > bestScore) {
            bestScore = score;
            best = item;
          }
        }

        if (best != null) {
          return _parseResponse(best);
        }
      }
    } catch (e) {
      debugPrint('[LrcLibService] Search fetch error: $e');
    }
    return null;
  }

  List<LyricLine>? _parseResponse(Map<String, dynamic> data) {
    // Prefer synced lyrics
    final syncedLyrics = data['syncedLyrics'] as String?;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final lines = LyricLine.parseLrcContent(syncedLyrics);
      if (lines.isNotEmpty) return lines;
    }

    // Fallback: plain lyrics (all at timestamp 0)
    final plainLyrics = data['plainLyrics'] as String?;
    if (plainLyrics != null && plainLyrics.isNotEmpty) {
      return plainLyrics
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => LyricLine(timestamp: Duration.zero, text: line.trim()))
          .toList();
    }

    return null;
  }

  /// Simple string similarity (0..2 range, higher = better)
  double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.8;
    final aWords = a.split(' ').toSet();
    final bWords = b.split(' ').toSet();
    final intersection = aWords.intersection(bWords).length;
    final union = aWords.union(bWords).length;
    return union == 0 ? 0 : intersection / union;
  }
}
