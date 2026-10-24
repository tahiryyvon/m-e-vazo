import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';
import 'package:guitar_lyrics_player/models/lyric_line.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/widgets/synced_lyrics_chords_view.dart';

class PlainController extends ChangeNotifier implements MusicPlayerController {
  @override
  List<LyricLine> get lyrics => List.generate(40, (i) => LyricLine(
    timestamp: Duration.zero, text: 'Invented line $i', isSynced: false,
    sourceUrl: Uri.parse('https://genius.com/test-lyrics'),
  ));
  @override
  int get currentLyricIndex => -1;
  @override
  ChordEvent? get currentChord => null;
  @override
  ChordEvent? get nextChord => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('plain lyrics scroll manually and cannot seek the song', (tester) async {
    final controller = PlainController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SyncedLyricsChordsView(
      controller: controller, currentPosition: Duration.zero, showChordsHeader: false,
    ))));
    expect(find.textContaining('Paroles non synchronisées'), findsOneWidget);
    expect(find.text('Source : genius.com'), findsOneWidget);
    final line = find.ancestor(of: find.text('Invented line 0'), matching: find.byType(InkWell));
    expect(tester.widget<InkWell>(line).onTap, isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    final offset = scroll.position.pixels;
    expect(offset, greaterThan(0));
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, offset);
    expect(tester.takeException(), isNull);
  });
}
