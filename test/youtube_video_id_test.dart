import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/youtube_service.dart';

void main() {
  test('only real YouTube video IDs are accepted for paths and URLs', () {
    expect(YoutubeService.isValidVideoId('dQw4w9WgXcQ'), isTrue);
    expect(YoutubeService.isValidVideoId('JGwWNGJdvx8'), isTrue);
    for (final bad in ['', '../../etc/x', 'dQw4w9WgXc', 'dQw4w9WgXcQQ', 'a/b c?d=e#f', 'local_C:/x.mp3']) {
      expect(YoutubeService.isValidVideoId(bad), isFalse, reason: bad);
    }
  });
}
