import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

/// Synchronized lyrics service via LRCLIB
/// 100% free, no authentication required
/// https://lrclib.net/docs
///
/// Always the first lyrics source, for online and local songs alike. Local
/// files often have no reliable artist (name taken from the file name) and
/// no known duration, so the lookup degrades gracefully:
/// - artist known: exact match, then search by artist + title;
/// - always: search by title alone; without an artist, the artist most
///   LRCLIB entries agree on wins (covers are outvoted);
/// - when the duration is known it filters and ranks candidates.
class LrcLibService {
  static const String _baseUrl = 'https://lrclib.net/api';
  static const Duration _timeout = Duration(seconds: 10);
  static const Map<String, String> _headers = {
    'User-Agent': "M'e-Vazo/1.0 (guitar lyrics player)",
  };

  final http.Client? _client;
  LrcLibService({http.Client? client}) : _client = client;

  Future<http.Response> _get(Uri uri) =>
      (_client?.get(uri, headers: _headers) ?? http.get(uri, headers: _headers))
          .timeout(_timeout);

  /// True when [artist] is a real name and not a placeholder.
  static bool isKnownArtist(String artist) {
    final a = artist.trim().toLowerCase();
    return a.isNotEmpty &&
        !const {'unknown artist', 'unknown', 'artiste inconnu', 'inconnu', '<unknown>', 'various artists'}
            .contains(a);
  }

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
    if (trackName.trim().isEmpty) return null;
    final knownArtist = isKnownArtist(artistName);
    debugPrint('[LrcLibService] Lookup "$trackName" / '
        '${knownArtist ? '"$artistName"' : 'artist unknown'}'
        '${duration != null ? ' / ${duration}s' : ''}');

    if (knownArtist) {
      // Attempt 1: Exact match GET endpoint
      final result = await _fetchExact(
        trackName: trackName,
        artistName: artistName,
        albumName: albumName,
        duration: duration,
      );
      if (result != null) return result;

      // Attempt 2: Search with artist and title as separate fields
      final searchResult = await _fetchBySearch(
        params: {'track_name': trackName, 'artist_name': artistName},
        trackName: trackName,
        artistName: artistName,
        duration: duration,
      );
      if (searchResult != null) return searchResult;
    }

    // Attempt 3: Search by title alone (the only option for an unknown artist)
    final byTitle = await _fetchBySearch(
      params: {'track_name': trackName},
      trackName: trackName,
      artistName: knownArtist ? artistName : null,
      duration: duration,
    );
    if (byTitle != null) return byTitle;

    // Attempt 4: free-text query, catches titles stored with extra words
    return _fetchBySearch(
      params: {'q': knownArtist ? '$artistName $trackName' : trackName},
      trackName: trackName,
      artistName: knownArtist ? artistName : null,
      duration: duration,
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
      final response = await _get(uri);

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
    required Map<String, String> params,
    required String trackName,
    required String? artistName,
    int? duration,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);
      final response = await _get(uri);
      if (response.statusCode != 200) return null;
      final results = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final best = pickBest(results,
          trackName: trackName, artistName: artistName, duration: duration);
      return best == null ? null : _parseResponse(best);
    } catch (e) {
      debugPrint('[LrcLibService] Search fetch error: $e');
    }
    return null;
  }

  /// Chooses the LRCLIB entry for [trackName]. With an [artistName] the
  /// artist must match; without one, candidates are grouped by artist and
  /// the most represented artist wins. A known [duration] (seconds) rejects
  /// entries more than 5 s away and favours the closest ones.
  @visibleForTesting
  static Map<String, dynamic>? pickBest(
    List<Map<String, dynamic>> results, {
    required String trackName,
    required String? artistName,
    int? duration,
  }) {
    final wantedTitle = _normalize(trackName);
    final wantedArtist = artistName == null ? null : _normalize(artistName);
    final candidates = <(Map<String, dynamic>, double)>[];
    for (final item in results) {
      final title = _normalize(item['trackName'] as String? ?? '');
      final titleScore = _similarity(title, wantedTitle);
      // Without an artist to confirm the match, the title must be close.
      if (titleScore < (wantedArtist == null ? 0.8 : 0.6)) continue;
      var score = titleScore;
      if (wantedArtist != null) {
        final artistScore = _similarity(_normalize(item['artistName'] as String? ?? ''), wantedArtist);
        if (artistScore < 0.5) continue;
        score += artistScore;
      }
      final itemDuration = (item['duration'] as num?)?.toDouble();
      if (duration != null && duration > 0 && itemDuration != null) {
        final gap = (itemDuration - duration).abs();
        if (gap > 5) continue;
        score += 0.3 * (1 - gap / 5);
      }
      final synced = (item['syncedLyrics'] as String?)?.isNotEmpty ?? false;
      final plain = (item['plainLyrics'] as String?)?.isNotEmpty ?? false;
      if (!synced && !plain) continue;
      if (synced) score += 0.2;
      candidates.add((item, score));
    }
    if (candidates.isEmpty) return null;

    if (wantedArtist == null) {
      // Majority vote on the artist: the original outnumbers covers.
      final votes = <String, int>{};
      for (final c in candidates) {
        final a = _normalize(c.$1['artistName'] as String? ?? '');
        votes[a] = (votes[a] ?? 0) + 1;
      }
      final top = votes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      candidates.removeWhere((c) => _normalize(c.$1['artistName'] as String? ?? '') != top);
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    return candidates.first.$1;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

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
          .map((line) => LyricLine(timestamp: Duration.zero, text: line.trim(),
              isSynced: false, sourceUrl: Uri.parse('https://lrclib.net')))
          .toList();
    }

    return null;
  }

  /// Simple string similarity (0..1 range, higher = better)
  static double _similarity(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return 0;
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.8;
    final aWords = a.split(' ').toSet();
    final bWords = b.split(' ').toSet();
    final intersection = aWords.intersection(bWords).length;
    final union = aWords.union(bWords).length;
    return union == 0 ? 0 : intersection / union;
  }
}
