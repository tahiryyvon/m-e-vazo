import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/screens/player_screen.dart';
import 'android_playback_sync_test.dart' show PendingAudioPlayer;
import 'package:guitar_lyrics_player/models/chord_event.dart';
import 'package:guitar_lyrics_player/widgets/mobile_chord_panel.dart';
import 'package:guitar_lyrics_player/widgets/chord_diagram.dart';
import 'harmonic_info_bar_test.dart' show HarmonicController;

class PanelController extends HarmonicController {
  int? selectedCapo;
  @override
  ChordEvent get currentChord => ChordEvent(timestamp: Duration.zero, chordName: 'F', fretPositions: [1,3,3,2,1,1]);
  @override
  ChordEvent get nextChord => ChordEvent(timestamp: Duration.zero, chordName: 'C', fretPositions: [-1,3,2,0,1,0]);
  @override
  void setCapo(int? fret) { selectedCapo = fret; }
}

void main() {
  for (final size in [const Size(320, 510), const Size(375, 600), const Size(568, 280)]) {
    testWidgets('entire phone player fits $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = PendingAudioPlayer();
      final controller = MusicPlayerController(audioPlayer: player);
      unawaited(controller.playSong(Song.demo(id: 'demo', title: 'Demo', artist: 'Test', assetPath: 'demo.mp3')));
      await tester.pump();
      await tester.pumpWidget(MaterialApp(home: PlayerScreen(controller: controller)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byType(MobileChordPanel));
      expect(panel.top, greaterThanOrEqualTo(0));
      expect(panel.bottom, lessThanOrEqualTo(size.height));
      await tester.pumpWidget(const SizedBox());
      player.finished.complete();
      await tester.pump();
      controller.dispose();
    }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
  }
  for (final width in [260.0, 320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fixed mobile reference fits width $width text $scale', (tester) async {
        final controller = PanelController();
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
          alignment: Alignment.topCenter,
          child: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: SizedBox(width: width, child: MobileChordPanel(controller: controller))),
        ))));
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);
        expect(find.byType(ChordDiagram), findsNWidgets(2));
        expect(find.text('TONALITÉ ≈ D'), findsOneWidget);
        expect(tester.getSize(find.byType(PopupMenuButton<int>)).height, greaterThanOrEqualTo(48));
        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sans capo'));
        await tester.pumpAndSettle();
        expect(controller.selectedCapo, 0);
      });
    }
  }
}
