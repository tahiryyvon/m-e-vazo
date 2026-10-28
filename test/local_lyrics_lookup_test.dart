import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/services/audio_tags.dart';
import 'package:guitar_lyrics_player/services/lrclib_service.dart';

Map<String, dynamic> entry(String title, String artist, double duration, {bool synced = true}) => {
      'trackName': title,
      'artistName': artist,
      'duration': duration,
      'syncedLyrics': synced ? '[00:01.00] Invented line by $artist' : null,
      'plainLyrics': 'Invented line by $artist',
    };

Uint8List id3v23({required String title, required String artist, int? lengthMs}) {
  List<int> frame(String id, String text) {
    final body = [0, ...latin1.encode(text)]; // encoding 0 = ISO-8859-1
    final size = body.length;
    return [...ascii.encode(id), size >> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff, 0, 0, ...body];
  }

  final frames = [
    ...frame('TIT2', title),
    ...frame('TPE1', artist),
    if (lengthMs != null) ...frame('TLEN', '$lengthMs'),
    ...List.filled(16, 0), // padding
  ];
  final n = frames.length;
  return Uint8List.fromList([
    ...ascii.encode('ID3'), 3, 0, 0,
    (n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f,
    ...frames,
  ]);
}

void main() {
  group('LRCLIB without a known artist (local files)', () {
    test('majority artist wins over a cover', () {
      final best = LrcLibService.pickBest([
        entry('Invented Song', 'Cover Singer', 200),
        entry('Invented Song', 'Original Band', 200),
        entry('Invented Song [Album, 2017]', 'Original Band', 200),
        entry('Invented Song', 'Original Band', 260),
      ], trackName: 'Invented Song', artistName: null);
      expect(best!['artistName'], 'Original Band');
    });

    test('a known duration filters and ranks the candidates', () {
      final best = LrcLibService.pickBest([
        entry('Invented Song', 'Original Band', 260),
        entry('Invented Song', 'Original Band', 201),
      ], trackName: 'Invented Song', artistName: null, duration: 200);
      expect(best!['duration'], 201);
      expect(LrcLibService.pickBest([entry('Invented Song', 'Original Band', 260)],
          trackName: 'Invented Song', artistName: null, duration: 200), isNull);
    });

    test('placeholder artists are treated as unknown', () {
      for (final a in ['Unknown Artist', 'unknown', '', '  ', 'Artiste inconnu']) {
        expect(LrcLibService.isKnownArtist(a), isFalse, reason: a);
      }
      expect(LrcLibService.isKnownArtist('Rossy'), isTrue);
    });

    test('lookup goes straight to a title search and returns its lyrics', () async {
      final requests = <Uri>[];
      final service = LrcLibService(client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/api/search') {
          return http.Response(jsonEncode([entry('Invented Song', 'Original Band', 200)]), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('not found', 404);
      }));
      final lines = await service.fetchSyncedLyrics(trackName: 'Invented Song', artistName: 'Unknown Artist');
      expect(lines, isNotNull);
      expect(lines!.first.isSynced, isTrue);
      // No exact-match call with a fake artist; first call is the title search.
      expect(requests.first.path, '/api/search');
      expect(requests.first.queryParameters, {'track_name': 'Invented Song'});
    });
  });

  group('local file metadata', () {
    test('ID3v2.3 title, artist and length are read', () {
      final tags = AudioTagReader.parseId3v2(id3v23(title: 'Invented Song', artist: 'Original Band', lengthMs: 200400))!;
      expect(tags.title, 'Invented Song');
      expect(tags.artist, 'Original Band');
      expect(tags.durationSeconds, 200);
      expect(AudioTagReader.parseId3v2(Uint8List.fromList(List.filled(32, 0))), isNull);
    });

    test('ID3v1 block at the end of the file is read', () {
      final block = Uint8List(128);
      block.setAll(0, ascii.encode('TAG'));
      block.setAll(3, latin1.encode('Invented Song'));
      block.setAll(33, latin1.encode('Original Band'));
      final tags = AudioTagReader.parseId3v1(block)!;
      expect(tags.title, 'Invented Song');
      expect(tags.artist, 'Original Band');
    });

    test('file names lose track numbers and underscores, not real numbers', () {
      expect(Song.cleanFileName('01 Shape of You'), 'Shape of You');
      expect(Song.cleanFileName('03 - Ed_Sheeran_-_Shape_of_You'), 'Ed Sheeran - Shape of You');
      expect(Song.cleanFileName('1. Hello'), 'Hello');
      expect(Song.cleanFileName('7 Years'), '7 Years');
      expect(Song.cleanFileName('22'), '22');
      final song = Song.fromLocalFile(r'C:\Music\02 - Ed_Sheeran_–_Shape_of_You.mp3');
      expect(song.artist, 'Ed Sheeran');
      expect(song.title, 'Shape of You');
    });
  });
}
