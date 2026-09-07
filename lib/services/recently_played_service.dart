import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// Service managing persistent recently played songs history
class RecentlyPlayedService {
  static const String _key = 'recently_played_songs';
  static const int _maxItems = 25;

  /// Global notifier so UI components can reactively update when history changes
  static final ValueNotifier<List<Song>> recentSongsNotifier = ValueNotifier<List<Song>>([]);

  /// Initializes and loads the initial list into recentSongsNotifier
  static Future<List<Song>> init() async {
    final list = await getRecentlyPlayed();
    recentSongsNotifier.value = list;
    return list;
  }

  /// Loads the list of recently played songs from persistent storage
  static Future<List<Song>> getRecentlyPlayed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = prefs.getStringList(_key);
      if (stringList != null && stringList.isNotEmpty) {
        final songs = <Song>[];
        for (final raw in stringList) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            songs.add(Song.fromJson(map));
          } catch (e) {
            debugPrint('[RecentlyPlayedService] Corrupted song entry: $e');
          }
        }
        recentSongsNotifier.value = songs;
        return songs;
      }
    } catch (e) {
      debugPrint('[RecentlyPlayedService] Error reading recent songs: $e');
    }
    return [];
  }

  /// Adds a song to the top of recently played songs and persists it
  static Future<List<Song>> addSong(Song song) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getRecentlyPlayed();

      // Remove any song with same id or title+artist
      currentList.removeWhere((item) =>
          item.id == song.id ||
          (item.title.toLowerCase() == song.title.toLowerCase() &&
              item.artist.toLowerCase() == song.artist.toLowerCase()));

      // Insert at front
      currentList.insert(0, song);

      // Enforce limit
      final trimmed = currentList.length > _maxItems
          ? currentList.sublist(0, _maxItems)
          : currentList;

      // Serialize
      final jsonStrings = trimmed.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_key, jsonStrings);

      recentSongsNotifier.value = List.unmodifiable(trimmed);
      return trimmed;
    } catch (e) {
      debugPrint('[RecentlyPlayedService] Error saving song: $e');
      return recentSongsNotifier.value;
    }
  }

  /// Removes a single song by its ID
  static Future<List<Song>> removeSong(String songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getRecentlyPlayed();
      currentList.removeWhere((item) => item.id == songId);

      final jsonStrings = currentList.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_key, jsonStrings);

      recentSongsNotifier.value = List.unmodifiable(currentList);
      return currentList;
    } catch (e) {
      debugPrint('[RecentlyPlayedService] Error removing song: $e');
      return recentSongsNotifier.value;
    }
  }

  /// Clears all recently played songs
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      recentSongsNotifier.value = const [];
    } catch (e) {
      debugPrint('[RecentlyPlayedService] Error clearing history: $e');
    }
  }
}
