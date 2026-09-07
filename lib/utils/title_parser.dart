/// Utility for extracting and cleaning artist and song title from raw video titles
class ParsedSongInfo {
  final String artist;
  final String title;

  const ParsedSongInfo({required this.artist, required this.title});

  @override
  String toString() => 'Artist: "$artist" | Title: "$title"';
}

class TitleParser {
  /// Extracts clean artist name and track title from raw YouTube title and channel author.
  static ParsedSongInfo extractArtistAndTitle(String rawTitle, String channelAuthor) {
    // 1. Clean author name
    String cleanAuthor = channelAuthor
        .replaceAll(RegExp(r'\s*-\s*Topic\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'VEVO\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'Official\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'Music\s*$', caseSensitive: false), '')
        .trim();

    // 2. Clean title from common YouTube brackets and tags
    String clean = rawTitle;

    // Remove [Official Music Video], (Official Video), (Lyric Video), (Audio), [4K], etc.
    final bracketPattern = RegExp(
      r'[\(\[\{][^\)\]\}]*(official|lyrics?|video|audio|hd|4k|remaster|remastered|live|visualizer|clip|performance|hq|version|edit|explicit|clean|prod\.|feat\.|ft\.)[^\)\]\}]*[\)\]\}]',
      caseSensitive: false,
    );
    clean = clean.replaceAll(bracketPattern, '');

    // Remove trailing "| Official Video" or " - Official Audio"
    clean = clean.replaceAll(
      RegExp(r'(\||//|--)\s*.*(official|lyrics?|video|audio|clip|hd).*$', caseSensitive: false),
      '',
    );

    // Remove trailing ft./feat.
    clean = clean.replaceAll(RegExp(r'\s+(ft\.|feat\.|featuring)\s+.*$', caseSensitive: false), '');

    clean = clean.trim();

    // 3. Try splitting by separator (" - ", " – ", " — ", " : ", ": ")
    final separators = [' - ', ' – ', ' — ', ' : ', ': '];
    for (final sep in separators) {
      if (clean.contains(sep)) {
        final parts = clean.split(sep);
        if (parts.length >= 2) {
          String p1 = parts[0].trim().replaceAll(RegExp(r'''^['"\s]+|['"\s]+$'''), '');
          String p2 = parts.sublist(1).join(sep).trim().replaceAll(RegExp(r'''^['"\s]+|['"\s]+$'''), '');

          if (p1.isNotEmpty && p2.isNotEmpty) {
            return ParsedSongInfo(artist: p1, title: p2);
          }
        }
      }
    }

    // 4. Fallback if no separator: use cleaned author as artist, cleaned title as track
    final finalTitle = clean.replaceAll(RegExp(r'''^['"\s]+|['"\s]+$'''), '');
    final finalArtist = cleanAuthor.isNotEmpty ? cleanAuthor : 'Unknown Artist';

    return ParsedSongInfo(
      artist: finalArtist,
      title: finalTitle.isNotEmpty ? finalTitle : rawTitle,
    );
  }
}
