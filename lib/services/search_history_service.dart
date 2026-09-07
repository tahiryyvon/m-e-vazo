import 'package:shared_preferences/shared_preferences.dart';

/// Service managing persistent search history queries
class SearchHistoryService {
  static const String _key = 'recent_search_queries';
  static const int _maxItems = 20;

  static const List<String> defaultSuggestions = [
    'Wonderwall Oasis',
    'Zombie The Cranberries',
    'Hotel California Eagles',
    'Bohemian Rhapsody Queen',
    'Creep Radiohead',
    'Stairway to Heaven Led Zeppelin',
    'Smells Like Teen Spirit Nirvana',
  ];

  /// Loads the list of recent searches from persistent storage
  static Future<List<String>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key);
      if (list != null && list.isNotEmpty) {
        return list;
      }
    } catch (_) {}
    return defaultSuggestions;
  }

  /// Adds a query to the top of recent searches and persists it
  static Future<List<String>> addSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return await getRecentSearches();

    try {
      final prefs = await SharedPreferences.getInstance();
      var list = prefs.getStringList(_key) ?? List<String>.from(defaultSuggestions);
      // Remove any existing occurrence to avoid duplicates
      list.removeWhere((item) => item.toLowerCase() == clean.toLowerCase());
      // Insert at top
      list.insert(0, clean);
      if (list.length > _maxItems) {
        list = list.sublist(0, _maxItems);
      }
      await prefs.setStringList(_key, list);
      return list;
    } catch (_) {
      return [clean, ...defaultSuggestions];
    }
  }

  /// Removes a single query from recent searches
  static Future<List<String>> removeSearch(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = prefs.getStringList(_key) ?? List<String>.from(defaultSuggestions);
      list.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
      await prefs.setStringList(_key, list);
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Clears the entire search history
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
