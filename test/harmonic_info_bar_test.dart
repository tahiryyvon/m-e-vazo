import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/widgets/harmonic_info_bar.dart';

class HarmonicController implements MusicPlayerController {
  @override
  String get musicalKey => 'D';
  @override
  int? get capo => 2;
  @override
  String get chordStatus => 'Accords estimés';
  @override
  List<String> get uniqueSongChords => ['C', 'Am', 'F', 'G'];
  @override
  ChordEvent? get currentChord => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('key stays visible in chord gaps and capo has a larger touch target', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 300, child: HarmonicInfoBar(controller: HarmonicController())),
    ))));
    expect(find.text('TONALITÉ ≈ D'), findsOneWidget);
    expect(find.textContaining('SYNC:'), findsNothing);
    expect(tester.getSize(find.byType(PopupMenuButton<int>)).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    expect(find.text('Sans capo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
