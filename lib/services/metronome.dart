import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Regular beats: [firstBeat], then one beat every [period]. Index 0 is the
/// first detected beat; beat indexes divisible by [beatsPerBar] are accents.
class BeatGrid {
  final double bpm;
  final Duration firstBeat;
  final int beatsPerBar;
  const BeatGrid(this.bpm, this.firstBeat, {this.beatsPerBar = 4});

  int get _periodUs => (60e6 / bpm).round();
  Duration get period => Duration(microseconds: _periodUs);

  Duration timeOf(int index) =>
      Duration(microseconds: firstBeat.inMicroseconds + index * _periodUs);

  /// Index of the first beat at or after [position].
  int nextIndex(Duration position) {
    final offset = position.inMicroseconds - firstBeat.inMicroseconds;
    return (offset / _periodUs).ceil();
  }

  bool isAccent(int index) => index % beatsPerBar == 0;
}

/// Plays one click. Swappable so tests run without audio plugins.
abstract class ClickSound {
  Future<void> click({required bool accent});
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// Low-latency clicks with audioplayers, on its own output: independent of
/// the song player's gain, so the song can be muted while the clicks remain.
class AudioplayersClickSound implements ClickSound {
  final AudioPlayer _accent = AudioPlayer();
  final AudioPlayer _normal = AudioPlayer();
  Future<void>? _ready;
  double _volume = 0.8;

  Future<void> _load() async {
    // Mix with the song: never take audio focus (that would pause it).
    try {
      await AudioPlayer.global.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (e) {
      debugPrint('[Metronome] audio context: $e');
    }
    for (final (player, asset) in [(_accent, 'audio/click_accent.wav'), (_normal, 'audio/click.wav')]) {
      try {
        await player.setPlayerMode(PlayerMode.lowLatency);
      } catch (_) {
        // Low-latency mode is Android-only; other platforms ignore it.
      }
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_volume);
      await player.setSource(AssetSource(asset));
    }
  }

  @override
  Future<void> click({required bool accent}) async {
    try {
      await (_ready ??= _load());
      final player = accent ? _accent : _normal;
      await player.stop();
      await player.resume();
    } catch (e) {
      debugPrint('[Metronome] click failed: $e');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (_ready == null) return;
    try {
      await _accent.setVolume(volume);
      await _normal.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await _accent.dispose();
    await _normal.dispose();
  }
}

/// Metronome locked to the song: it reads the playback position and clicks
/// on the song's detected beat grid, so it follows pause, seek and resume,
/// and keeps going while the song itself is muted (playback still advances,
/// lyrics keep scrolling). Disabled by default.
class Metronome extends ChangeNotifier {
  final ClickSound Function() _createSound;
  final Duration Function() _now;
  ClickSound? _sound;

  Metronome({ClickSound Function()? createSound, Duration Function()? now})
      : _createSound = createSound ?? AudioplayersClickSound.new,
        _now = now ?? _monotonicNow;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _monotonicNow() => _stopwatch.elapsed;

  static const double defaultBpm = 120;
  static const double minBpm = 30, maxBpm = 260;

  /// A click is played only if its timer fires this close to the beat.
  static const Duration _tolerance = Duration(milliseconds: 60);

  bool _enabled = false;
  bool get enabled => _enabled;

  double _volume = 0.8;
  double get volume => _volume;

  double? _detectedBpm;
  Duration _firstBeat = Duration.zero;
  double? _manualBpm;

  double? get detectedBpm => _detectedBpm;
  bool get isManual => _manualBpm != null || _detectedBpm == null;
  double get bpm => _manualBpm ?? _detectedBpm ?? defaultBpm;
  BeatGrid get grid => BeatGrid(bpm, _detectedBpm == null ? Duration.zero : _firstBeat);

  /// Index of the last beat played (for the visual pulse), -1 when idle.
  final ValueNotifier<int> beat = ValueNotifier(-1);

  // Playback clock: last known position, interpolated while playing.
  Duration _anchorPosition = Duration.zero;
  Duration _anchorTime = Duration.zero;
  bool _playing = false;
  Timer? _timer;
  int? _lastFired;

  Duration get position {
    if (!_playing) return _anchorPosition;
    var elapsed = _now() - _anchorTime;
    // Never extrapolate far past the last report from the player.
    if (elapsed > const Duration(seconds: 1)) elapsed = const Duration(seconds: 1);
    return _anchorPosition + elapsed;
  }

  // ── Inputs from the player ────────────────────────────────────────────

  /// New song: its detected tempo replaces any manual tempo.
  void setSongTempo(double? bpm, Duration? firstBeat) {
    _detectedBpm = bpm;
    _firstBeat = firstBeat ?? Duration.zero;
    _manualBpm = null;
    _lastFired = null;
    _reschedule();
    notifyListeners();
  }

  void onPosition(Duration position) {
    final jumped = (position - this.position).abs() > const Duration(milliseconds: 250);
    _anchorPosition = position;
    _anchorTime = _now();
    if (jumped) {
      _lastFired = null; // seek: the next beat may be behind the last one
      _reschedule();
    }
  }

  void onPlaying(bool playing) {
    if (_playing == playing) return;
    _anchorPosition = position;
    _anchorTime = _now();
    _playing = playing;
    _reschedule();
  }

  void onSeek(Duration position) {
    _anchorPosition = position;
    _anchorTime = _now();
    _lastFired = null;
    _reschedule();
  }

  // ── User settings ─────────────────────────────────────────────────────

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      _sound ??= _createSound();
      unawaited(_sound!.setVolume(_volume));
    } else {
      beat.value = -1;
    }
    _lastFired = null;
    _reschedule();
    notifyListeners();
  }

  void toggle() => setEnabled(!_enabled);

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    unawaited(_sound?.setVolume(_volume));
    notifyListeners();
  }

  void setManualBpm(double bpm) {
    _manualBpm = bpm.clamp(minBpm, maxBpm).toDouble();
    _lastFired = null;
    _reschedule();
    notifyListeners();
  }

  void nudge(double delta) => setManualBpm(bpm.roundToDouble() + delta);
  void halve() => setManualBpm(bpm / 2);
  void doubleTempo() => setManualBpm(bpm * 2);

  void resetToDetected() {
    _manualBpm = null;
    _lastFired = null;
    _reschedule();
    notifyListeners();
  }

  // ── Scheduling ────────────────────────────────────────────────────────

  void _reschedule() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled || !_playing) return;
    final g = grid;
    var index = g.nextIndex(position);
    if (_lastFired != null && index <= _lastFired!) index = _lastFired! + 1;
    var delay = g.timeOf(index) - position;
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, () => _fire(index));
  }

  void _fire(int index) {
    _timer = null;
    if (!_enabled || !_playing) return;
    final g = grid;
    final late = position - g.timeOf(index);
    if (late.abs() <= _tolerance) {
      _lastFired = index;
      beat.value = index;
      unawaited(_sound?.click(accent: g.isAccent(index)));
    }
    _reschedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    beat.dispose();
    unawaited(_sound?.dispose());
    super.dispose();
  }
}
