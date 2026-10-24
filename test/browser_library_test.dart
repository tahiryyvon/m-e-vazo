import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/services/local_library_service.dart';
import 'package:guitar_lyrics_player/services/recently_played_service.dart';
import 'package:guitar_lyrics_player/screens/library_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('browser audio stays in this session and never persists broken URLs', () async {
    SharedPreferences.setMockInitialValues({});
    final song = Song.fromLocalFile('Artist - Track.wav')
        .copyWith(localPath: 'blob:http://localhost/audio', id: 'browser-audio');
    await LocalLibraryService.addSongs([song]);
    await LocalLibraryService.init();
    expect(LocalLibraryService.librarySongsNotifier.value.single.title, 'Track');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('me_vazo_local_library_songs'), isEmpty);
    await RecentlyPlayedService.addSong(song);
    expect(prefs.getStringList('recently_played_songs'), isNull);
  });

  for (final size in [const Size(320, 568), const Size(568, 320), const Size(1440, 900)]) {
    testWidgets('library and demo fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Song? selected;
      await tester.pumpWidget(MaterialApp(home: LibraryScreen(
        onSongSelected: (song) => selected = song,
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Écouter la démonstration'));
      expect(selected?.isAsset, isTrue);
      LocalLibraryService.librarySongsNotifier.value = [];
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
