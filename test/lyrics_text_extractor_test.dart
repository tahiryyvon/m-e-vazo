import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/lyrics_text_extractor.dart';

void main() {
  const description = '''
Invented Song - Test Band (Official Lyric Video)
Stream it everywhere: https://example.org/listen
Follow Test Band on Instagram: @testband
#invented #song

Paroles :
Invented line one walks in the rain
Invented line two under the plane
Invented line three, nothing to explain

Invented chorus line, sing it again
Invented chorus line, feel the refrain
Invented line six before the end
Invented line seven, my only friend
Invented line eight, we start again

Prod by Someone
© 2026 Test Label
''';

  test('finds the lyrics block in a video description and skips credits', () {
    final lines = LyricsTextExtractor.extract(description)!;
    expect(lines.first, 'Invented line one walks in the rain');
    expect(lines.last, 'Invented line eight, we start again');
    expect(lines.where((l) => l.isNotEmpty).length, 8);
    expect(lines.contains(''), isTrue); // stanza separator kept
    expect(lines.any((l) => l.contains('Prod') || l.contains('http') || l.startsWith('#')), isFalse);
  });

  test('rejects comments without enough lyric lines', () {
    expect(LyricsTextExtractor.extract('Great song!\nLove it so much\n0:45 best part'), isNull);
    expect(LyricsTextExtractor.extract('a\n' * 20), isNull); // too short to be lines
  });

  test('line classification', () {
    expect(LyricsTextExtractor.isLyricLine('Une ligne de paroles inventée'), isTrue);
    expect(LyricsTextExtractor.isLyricLine('https://example.org'), isFalse);
    expect(LyricsTextExtractor.isLyricLine('1:23 intro'), isFalse);
    expect(LyricsTextExtractor.isLyricLine('#tag #other'), isFalse);
    expect(LyricsTextExtractor.isLyricLine('Suivez-nous sur Facebook'), isFalse);
    expect(LyricsTextExtractor.isLyricLine('!!! ??? ... 123'), isFalse);
  });
}
