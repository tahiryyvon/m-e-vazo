import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:guitar_lyrics_player/controllers/music_player_controller.dart';

class VolumeRecordingPlayer implements AudioPlayer {
  final volumes = <double>[];
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('muting the song zeroes its gain only; the metronome stays on', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux; // desktop path
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final player = VolumeRecordingPlayer();
    final controller = MusicPlayerController(audioPlayer: player);
    addTearDown(controller.dispose);

    controller.metronome.setEnabled(false); // default is off
    expect(controller.metronome.enabled, isFalse);

    await controller.setVolume(0.6);
    expect(player.volumes.last, 0.6);

    controller.metronome.toggle();
    await controller.toggleMute();
    expect(controller.songMuted, isTrue);
    expect(player.volumes.last, 0.0);
    expect(controller.volume, 0.6); // master volume untouched
    expect(controller.metronome.enabled, isTrue);

    await controller.toggleMute();
    expect(controller.songMuted, isFalse);
    expect(player.volumes.last, 0.6);
  });
}
