import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/models/lyric_line.dart';
import 'package:guitar_lyrics_player/services/songsterr_service.dart';

void main() {
  test('approximate accompaniment covers interlude and long instrumental outro', () {
    final chords = SongsterrService.generateHarmonicProgression(
      title: 'Test', artist: 'Test', durationSeconds: 90,
      lyrics: [
        LyricLine(timestamp: Duration.zero, text: 'First verse'),
        LyricLine(timestamp: const Duration(seconds: 40), text: 'Last verse'),
      ],
    );
    expect(chords.first.timestamp, Duration.zero);
    for (var i = 1; i < chords.length; i++) {
      final previous = chords[i - 1];
      expect(chords[i].timestamp, greaterThan(previous.timestamp));
      expect(chords[i].timestamp.inMilliseconds,
          previous.timestamp.inMilliseconds + previous.durationMs!);
    }
    expect(chords.last.timestamp.inMilliseconds + chords.last.durationMs!, 90000);
    expect(chords.where((c) => c.timestamp.inSeconds > 50).length, greaterThan(5));
  });
}
