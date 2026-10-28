import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_lyrics_player/services/metronome.dart';

class FakeClicks implements ClickSound {
  final clicks = <(Duration, bool)>[];
  Duration Function() now;
  FakeClicks(this.now);
  double volume = -1;
  @override
  Future<void> click({required bool accent}) async => clicks.add((now(), accent));
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> dispose() async {}
}

void main() {
  test('beat grid: next beat, accents every bar', () {
    const grid = BeatGrid(120, Duration(milliseconds: 250)); // 500 ms period
    expect(grid.nextIndex(Duration.zero), 0);
    expect(grid.nextIndex(const Duration(milliseconds: 251)), 1);
    expect(grid.timeOf(3), const Duration(milliseconds: 1750));
    expect([for (var i = 0; i < 9; i++) grid.isAccent(i)],
        [true, false, false, false, true, false, false, false, true]);
  });

  testWidgets('clicks on the song beats, follows pause and seek, off by default', (tester) async {
    var clock = Duration.zero;
    late FakeClicks sound;
    final metronome = Metronome(
      createSound: () => sound = FakeClicks(() => clock),
      now: () => clock,
    );
    addTearDown(metronome.dispose);
    var songPosition = Duration.zero;
    var playing = false;
    var sinceReport = Duration.zero;
    Future<void> advance(Duration d) async {
      // The player reports its position every 100 ms, like a real player.
      const step = Duration(milliseconds: 10);
      for (var t = Duration.zero; t < d; t += step) {
        clock += step;
        if (playing) songPosition += step;
        sinceReport += step;
        if (sinceReport >= const Duration(milliseconds: 100)) {
          sinceReport = Duration.zero;
          metronome.onPosition(songPosition);
        }
        await tester.pump(step);
      }
    }
    void setPlaying(bool value) {
      playing = value;
      metronome.onPlaying(value);
    }

    metronome.setSongTempo(120, const Duration(milliseconds: 250));
    metronome.onPosition(Duration.zero);
    setPlaying(true);
    expect(metronome.enabled, isFalse);
    await advance(const Duration(seconds: 1));
    expect(metronome.beat.value, -1); // disabled by default: silent

    metronome.setEnabled(true);
    final start = clock; // song position 1.0 s
    await advance(const Duration(seconds: 2)); // beats at 1.25, 1.75, 2.25, 2.75
    final times = sound.clicks.map((c) => (c.$1 - start).inMilliseconds).toList();
    expect(times.length, 4);
    for (final (i, t) in times.indexed) {
      expect(t, closeTo(250 + i * 500, 25));
    }
    // Beat index 4 (2.25 s) is the first beat of bar 2: accented.
    expect(sound.clicks.map((c) => c.$2).toList(), [false, false, true, false]);

    // Pause: no clicks.
    setPlaying(false);
    await advance(const Duration(seconds: 2));
    expect(sound.clicks.length, 4);

    // Seek back to 0 and play: grid restarts on beat 0 (accent at 0.25 s).
    songPosition = Duration.zero;
    metronome.onSeek(Duration.zero);
    setPlaying(true);
    final restart = clock;
    await advance(const Duration(milliseconds: 600)); // one beat: 0.25 s
    expect(sound.clicks.length, 5);
    expect((sound.clicks[4].$1 - restart).inMilliseconds, closeTo(250, 25));
    expect(sound.clicks[4].$2, isTrue);

    // Independent volume, then off.
    metronome.setVolume(0.3);
    expect(sound.volume, 0.3);
    metronome.setEnabled(false);
    await advance(const Duration(seconds: 1));
    expect(sound.clicks.length, 5);
  });

  test('manual tempo, halve/double and reset to the detected tempo', () {
    final metronome = Metronome(createSound: () => FakeClicks(() => Duration.zero));
    addTearDown(metronome.dispose);
    expect(metronome.bpm, Metronome.defaultBpm);
    expect(metronome.isManual, isTrue); // nothing detected (e.g. web)
    metronome.setSongTempo(96.4, Duration.zero);
    expect(metronome.isManual, isFalse);
    metronome.doubleTempo();
    expect(metronome.bpm, closeTo(192.8, 0.01));
    metronome.nudge(-1);
    expect(metronome.bpm, 192);
    metronome.resetToDetected();
    expect(metronome.bpm, 96.4);
    metronome.setSongTempo(140, Duration.zero); // new song drops the override
    metronome.halve();
    metronome.setSongTempo(100, Duration.zero);
    expect(metronome.bpm, 100);
  });
}
