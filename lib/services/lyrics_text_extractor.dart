/// Finds a block of lyrics inside free text such as a YouTube video
/// description or a comment: the longest run of consecutive short lines,
/// ignoring links, hashtags, credits and timestamps.
class LyricsTextExtractor {
  static final _url = RegExp(r'(https?://|www\.)', caseSensitive: false);
  static final _timestamp = RegExp(r'^\(?\d{1,2}:\d{2}');
  static final _hashtagOnly = RegExp(r'^[#@][\w#@ ]*$');
  static final _credit = RegExp(
    r'^(prod|mix|master|real|réal|realisation|réalisation|directed|produced|'
    r'written|composed|arrang|beat|instru|label|follow|suivez|subscribe|abonne|'
    r'stream|écoute|ecoute|listen|download|télécharg|telecharg|available|disponible|'
    r'instagram|facebook|tiktok|twitter|snapchat|spotify|deezer|apple music|itunes|'
    r'booking|contact|merch|©|℗|\(c\)|all rights|tous droits)',
    caseSensitive: false,
  );
  static final _header = RegExp(
    r'^[\[(]?\s*(paroles?|lyrics?|letra|tononkira|texte)\s*(de la chanson|du morceau)?\s*[:\-–)\]]*\s*$',
    caseSensitive: false,
  );
  static final _letters = RegExp(r'[\p{L}]', unicode: true);

  /// Returns the lyric lines (blank lines kept as stanza separators) or null
  /// when no block of at least [minLines] plausible lines exists.
  static List<String>? extract(String text, {int minLines = 8}) {
    final raw = text.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).toList();

    // Best run of lyric lines; a single blank line does not break a run,
    // anything else (link, credit, long prose, timestamp) does.
    List<String>? best;
    var bestCount = 0;
    var run = <String>[];
    var runCount = 0;
    var blankStreak = 0;
    void close() {
      if (runCount > bestCount) {
        best = List.of(run);
        bestCount = runCount;
      }
      run = [];
      runCount = 0;
      blankStreak = 0;
    }

    for (final line in raw) {
      if (line.isEmpty) {
        blankStreak++;
        if (blankStreak > 1) {
          close();
        } else if (run.isNotEmpty) {
          run.add('');
        }
        continue;
      }
      blankStreak = 0;
      if (_header.hasMatch(line)) {
        continue; // "Paroles :" above the text, keep the run going
      }
      if (isLyricLine(line)) {
        run.add(line);
        runCount++;
      } else {
        close();
      }
    }
    close();

    if (best == null || bestCount < minLines) return null;
    final lines = best!;
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  static bool isLyricLine(String line) {
    // Long sung lines exist ("Take my hand, stop, put Van the Man on the
    // jukebox…"); only real paragraphs are rejected on length.
    if (line.length < 2 || line.length > 200) return false;
    if (_url.hasMatch(line) || _timestamp.hasMatch(line)) return false;
    if (_hashtagOnly.hasMatch(line) || _credit.hasMatch(line)) return false;
    final letters = _letters.allMatches(line).length;
    return letters >= line.length * 0.5;
  }
}
