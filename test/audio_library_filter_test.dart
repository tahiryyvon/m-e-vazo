import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/services/audio_library_filter.dart';

void main() {
  test('folder accepts audio extensions and ignores other files', () {
    expect(isAudioFile('album/Track.MP3'), isTrue);
    expect(isAudioFile('album/song.flac'), isTrue);
    expect(isAudioFile('album/cover.jpg'), isFalse);
    expect(isAudioFile('album/song.mp3.txt'), isFalse);
  });
  test('local search combines title and artist, ignores case and whitespace', () {
    final songs = [Song.fromLocalFile('The Calling - Wherever You Will Go.mp3'),
      Song.fromLocalFile('Other - Song.wav')];
    expect(filterLocalSongs(songs, '  CALLING wherever '), [songs.first]);
    expect(filterLocalSongs(songs, 'unknown'), isEmpty);
    expect(filterLocalSongs(songs, ' '), songs);
  });
}
