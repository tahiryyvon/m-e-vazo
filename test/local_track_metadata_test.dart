import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/audio_tags.dart';
import 'package:guitar_lyrics_player/services/local_track_metadata.dart';
import 'package:guitar_lyrics_player/services/lrclib_service.dart';

Map<String, dynamic> version(String artist, double duration) => {
      'trackName': 'La Vie en rose',
      'artistName': artist,
      'duration': duration,
      'syncedLyrics': '[00:01.00] Invented line by $artist',
    };

void main() {
  test('real container duration wins over the tag length', () async {
    final meta = LocalTrackMetadata(
      readTags: (_) async => const AudioTags(title: 'Tagged', artist: 'Band', durationSeconds: 999),
      probeDuration: (_) async => 187,
    );
    final info = await meta.resolve(path: 'x.mp3', title: 'file name', artist: 'Unknown Artist');
    expect(info.title, 'Tagged');
    expect(info.artist, 'Band');
    expect(info.durationSeconds, 187);
  });

  test('a failing probe falls back to known then tag duration', () async {
    final failing = LocalTrackMetadata(
      readTags: (_) async => const AudioTags(durationSeconds: 200),
      probeDuration: (_) async => throw StateError('no decoder'),
    );
    expect((await failing.resolve(path: 'x', title: 't', artist: 'a', knownDuration: 190)).durationSeconds, 190);
    expect((await failing.resolve(path: 'x', title: 't', artist: 'a')).durationSeconds, 200);
    final nothing = LocalTrackMetadata(readTags: (_) async => null, probeDuration: (_) async => null);
    final info = await nothing.resolve(path: 'x', title: 'From file', artist: 'Unknown Artist');
    expect((info.title, info.artist, info.durationSeconds), ('From file', 'Unknown Artist', null));
  });

  test('the real duration picks the right version of an ambiguous title', () {
    // Shape of the real LRCLIB answer for "La Vie en rose": the English
    // version is the majority, so without a duration it wins.
    final versions = [
      version('Louis Armstrong', 197), version('Louis Armstrong', 205),
      version('Louis Armstrong', 204), version('Cyndi Lauper', 211),
      version('Edith Piaf', 187), version('Edith Piaf', 124),
    ];
    expect(LrcLibService.pickBest(versions, trackName: 'La Vie en rose', artistName: null)!['artistName'],
        'Louis Armstrong');
    expect(LrcLibService.pickBest(versions, trackName: 'La Vie en rose', artistName: null, duration: 186)!['artistName'],
        'Edith Piaf');
  });
}
