import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/widgets/player_keyboard_controls.dart';

class Controls implements MusicPlayerController {
  final calls = <String>[];
  @override
  Song? currentSong = Song(id: 'test', title: 'Test', artist: 'Test');
  @override
  double volume = 0.5;
  @override
  Future<void> togglePlayPause() async => calls.add('play');
  @override
  Future<void> toggleMute() async => calls.add('mute');
  @override
  Future<void> seekForward() async => calls.add('forward');
  @override
  Future<void> seekBackward() async => calls.add('back');
  @override
  Future<void> seek(Duration value) async => calls.add('seek:${value.inSeconds}');
  @override
  Future<void> setVolume(double value) async { volume = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Windows fullscreen can be left without loading a song', (tester) async {
    final methods = <String>[];
    const channel = MethodChannel('me_vazo/window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async { methods.add(call.method); return null; });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final controls = Controls()..currentSong = null;
    await tester.pumpWidget(MaterialApp(home: PlayerKeyboardControls(
      controller: controls, child: const Scaffold(body: SizedBox()),
    )));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(methods, ['toggleFullscreen', 'exitFullscreen']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets('keyboard controls work but leave text editing alone', (tester) async {
    final controls = Controls();
    await tester.pumpWidget(MaterialApp(home: PlayerKeyboardControls(
      controller: controls, child: const Scaffold(body: TextField()),
    )));
    await tester.pump();
    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyM, LogicalKeyboardKey.home]) {
      await tester.sendKeyEvent(key);
    }
    expect(controls.calls, ['play', 'back', 'forward', 'mute', 'seek:0']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controls.volume, closeTo(0.55, 0.001));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    expect(controls.calls.length, 5);
  });
}
