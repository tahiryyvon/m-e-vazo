import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class LocalLibraryService {
  static const _storageKey = 'me_vazo_local_library_songs';
  static final ValueNotifier<List<Song>> librarySongsNotifier = ValueNotifier<List<Song>>([]);

  /// Built-in demo song
  static final Song acousticDemoSong = Song.demo(
    id: 'demo_acoustic_guitar',
    title: 'Acoustic Guitar Demonstration',
    artist: "M' e-Vazo Studio",
    assetPath: 'assets/audio/acoustic_demo.wav',
    durationSeconds: 24,
  );

  /// Initializes and loads saved songs from SharedPreferences
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];
      final List<Song> loaded = [];

      for (final jsonStr in rawList) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          loaded.add(Song.fromJson(map));
        } catch (e) {
          debugPrint('[LocalLibraryService] Corrupted song: $e');
        }
      }

      librarySongsNotifier.value = loaded;
      debugPrint('[LocalLibraryService] Loaded ${loaded.length} local songs from disk');
    } catch (e) {
      debugPrint('[LocalLibraryService] Error loading local library: $e');
    }
  }

  /// Adds a list of songs to the library and persists them
  static Future<void> addSongs(List<Song> songs) async {
    try {
      final current = List<Song>.from(librarySongsNotifier.value);
      for (final s in songs) {
        if (!current.any((existing) => existing.localPath == s.localPath)) {
          current.insert(0, s);
        }
      }

      librarySongsNotifier.value = current;
      await _persist(current);
    } catch (e) {
      debugPrint('[LocalLibraryService] Error adding songs: $e');
    }
  }

  /// Removes a song from the library
  static Future<void> removeSong(String songId) async {
    try {
      final current = List<Song>.from(librarySongsNotifier.value);
      current.removeWhere((s) => s.id == songId);
      librarySongsNotifier.value = current;
      await _persist(current);
    } catch (e) {
      debugPrint('[LocalLibraryService] Error removing song: $e');
    }
  }

  static Future<void> _persist(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = songs.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }
}
