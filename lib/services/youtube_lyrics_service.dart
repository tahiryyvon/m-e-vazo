import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/lyric_line.dart';
import 'lyrics_text_extractor.dart';

/// Last-resort lyrics source: people often paste the words in a YouTube
/// video's description or in its comments. Not available on the Web build
/// (the browser blocks cross-origin requests to YouTube).
class YoutubeLyricsService {
  final YoutubeExplode _yt;
  YoutubeLyricsService({YoutubeExplode? client}) : _yt = client ?? YoutubeExplode();
  void dispose() => _yt.close();

  static const _timeout = Duration(seconds: 12);
  static const _maxCommentPages = 3;

  /// Reads the description then the top comments of [videoId], or of the
  /// best YouTube search hit for [title] / [artist] when the song is local.
  Future<List<LyricLine>?> search({
    String? videoId,
    required String title,
    required String artist,
    required bool Function() isCurrent,
  }) async {
    try {
      Video? video;
      if (videoId != null) {
        video = await _yt.videos.get(videoId).timeout(_timeout);
      } else {
        final hits = await _yt.search.search('$title $artist').timeout(_timeout);
        video = _bestHit(hits, title) ?? hits.firstOrNull;
      }
      if (video == null || !isCurrent()) return null;
      final watchUrl = Uri.https('www.youtube.com', '/watch', {'v': video.id.value});

      // 1. Description (lyric videos very often carry the full text).
      final fromDescription = LyricsTextExtractor.extract(video.description);
      if (fromDescription != null) {
        debugPrint('[YoutubeLyricsService] Lyrics in description of ${video.id.value}');
        return _toLines(fromDescription, watchUrl);
      }

      // 2. Top comments, a few pages at most.
      List<String>? best;
      Comment? bestComment;
      // The comments client is marked deprecated upstream but still works;
      // a failure here is caught below and simply yields no lyrics.
      // ignore: deprecated_member_use
      var page = await _yt.videos.comments.getComments(video).timeout(_timeout);
      for (var i = 0; i < _maxCommentPages && page != null; i++) {
        if (!isCurrent()) return null;
        for (final comment in page) {
          final lines = LyricsTextExtractor.extract(comment.text);
          if (lines == null) continue;
          final count = lines.where((l) => l.isNotEmpty).length;
          if (best == null || count > best.where((l) => l.isNotEmpty).length) {
            best = lines;
            bestComment = comment;
          }
        }
        if (best != null) break;
        page = await page.nextPage().timeout(_timeout);
      }
      if (best == null) return null;
      debugPrint('[YoutubeLyricsService] Lyrics in a comment by ${bestComment?.author} '
          'on ${video.id.value}');
      return _toLines(best, watchUrl);
    } catch (e) {
      debugPrint('[YoutubeLyricsService] $e');
      return null;
    }
  }

  static List<LyricLine> _toLines(List<String> lines, Uri source) => [
        for (final line in lines)
          LyricLine(timestamp: Duration.zero, text: line, isSynced: false, sourceUrl: source),
      ];

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

  /// First search hit whose title contains at least half of the song title's words.
  static Video? _bestHit(List<Video> hits, String title) {
    final words = _normalize(title).split(' ').where((w) => w.length >= 2).toList();
    if (words.isEmpty) return null;
    for (final hit in hits) {
      final haystack = _normalize(hit.title).split(' ').toSet();
      final found = words.where(haystack.contains).length;
      if (found * 2 >= words.length) return hit;
    }
    return null;
  }
}
