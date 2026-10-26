import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';
import 'package:guitar_lyrics_player/models/song.dart';
import 'package:guitar_lyrics_player/services/screen_awake_service.dart';

// Match just_audio's contract: play stays pending while the song is playing.
class PendingAudioPlayer implements AudioPlayer {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final started = Completer<void>();
  final finished = Completer<void>();

  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Duration get duration => const Duration(seconds: 24);
  @override
  Future<void> stop() async {}
  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async => duration;
  @override
  Future<void> play() {
    states.add(PlayerState(true, ProcessingState.ready));
    if (!started.isCompleted) started.complete();
    return finished.future;
  }
  @override
  Future<void> dispose() async {
    await positions.close();
    await states.close();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completion advances once, prepares chords, and stops at end of queue', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final player = PendingAudioPlayer();
    final controller = MusicPlayerController(audioPlayer: player);
    addTearDown(controller.dispose);
    final songs = List.generate(3, (i) => Song.demo(
      id: 'queue-$i', title: 'Demo $i', artist: 'Test', assetPath: 'demo.mp3',
    ));
    controller.setPlaybackQueue(songs);
    final playback = controller.playSong(songs.first);
    await player.started.future;
    player.states.add(PlayerState(false, ProcessingState.ready));
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentSong?.id, 'queue-0');
    player.states.add(PlayerState(true, ProcessingState.completed));
    player.states.add(PlayerState(true, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentSong?.id, 'queue-1');
    expect(controller.currentChord?.chordName, 'G');
    expect(controller.state, PlaybackState.playing);
    player.states.add(PlayerState(true, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentSong?.id, 'queue-2');
    player.states.add(PlayerState(true, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentSong?.id, 'queue-2');
    expect(controller.state, PlaybackState.completed);
    player.finished.complete();
    await playback;
  });

  test('manual choice cancels an automatic transition already scheduled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final player = PendingAudioPlayer();
    final controller = MusicPlayerController(audioPlayer: player);
    addTearDown(controller.dispose);
    final songs = List.generate(3, (i) => Song.demo(
      id: 'choice-$i', title: 'Demo $i', artist: 'Test', assetPath: 'demo.mp3',
    ));
    controller.setPlaybackQueue(songs);
    final first = controller.playSong(songs.first);
    await player.started.future;
    player.states.add(PlayerState(true, ProcessingState.completed));
    final manual = controller.playSong(songs.last);
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentSong?.id, 'choice-2');
    player.finished.complete();
    await Future.wait([first, manual]);
  });

  test('Android advances chords and lyrics while play is still pending', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final screenRequests = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenAwakeService.channel, (call) async {
      expect(call.method, 'setEnabled');
      screenRequests.add(call.arguments as bool);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenAwakeService.channel, null));
    final player = PendingAudioPlayer();
    final controller = MusicPlayerController(audioPlayer: player);
    addTearDown(controller.dispose);

    final playback = controller.playSong(Song.demo(
      id: 'sync-test', title: 'Demo', artist: 'Test', assetPath: 'demo.mp3',
    ));
    await player.started.future;
    expect(player.finished.isCompleted, isFalse);
    expect(controller.currentChord?.chordName, 'G');

    player.states.add(PlayerState(true, ProcessingState.buffering));
    player.states.add(PlayerState(true, ProcessingState.buffering));
    player.states.add(PlayerState(true, ProcessingState.ready));

    player.positions.add(const Duration(seconds: 7));
    expect(controller.currentChord?.chordName, 'Em');
    expect(controller.currentLyricIndex, 2);
    player.positions.add(const Duration(seconds: 13));
    expect(controller.currentChord?.chordName, 'C');
    expect(controller.currentLyricIndex, 4);
    // Seek backwards and resume without a new synchronization subscription.
    player.positions.add(const Duration(seconds: 1));
    expect(controller.currentChord?.chordName, 'G');
    player.states.add(PlayerState(false, ProcessingState.ready));
    expect(controller.state, PlaybackState.paused);
    player.states.add(PlayerState(true, ProcessingState.ready));
    player.positions.add(const Duration(seconds: 19));
    expect(controller.currentChord?.chordName, 'D');
    expect(controller.currentLyricIndex, 6);

    player.states.add(PlayerState(true, ProcessingState.completed));
    player.finished.complete();
    await playback;
    expect(controller.state, PlaybackState.completed);
    // Buffering must not toggle the display request; pause and completion release it.
    expect(screenRequests, [true, false, true, false]);
  });
}
