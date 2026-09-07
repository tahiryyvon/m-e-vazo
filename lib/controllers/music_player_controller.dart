import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song.dart';
import '../models/lyric_line.dart';
import '../models/chord_event.dart';
import '../services/youtube_service.dart';
import '../services/windows_audio_player.dart';
import '../services/local_audio_proxy.dart';
import '../services/lrclib_service.dart';
import '../services/songsterr_service.dart';
import '../services/recently_played_service.dart';
import '../utils/title_parser.dart';

/// All possible playback states
enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  error,
}

/// Returns true when running natively on Windows
bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Central controller for audio playback, lyrics sync, and chord sync
/// Uses media_kit (libmpv) on Windows, just_audio elsewhere.
class MusicPlayerController extends ChangeNotifier {
  // Platform-specific players
  WindowsAudioPlayer? _windowsPlayer;
  AudioPlayer? _audioPlayer;

  final YoutubeService _youtubeService = YoutubeService();
  final LrcLibService _lyricsService = LrcLibService();
  final SongsterrService _chordsService = SongsterrService();

  // Playback state
  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  // Active song data
  Song? _currentSong;
  Song? get currentSong => _currentSong;

  // Lyrics
  List<LyricLine>? _lyrics;
  List<LyricLine>? get lyrics => _lyrics;

  int _currentLyricIndex = -1;
  int get currentLyricIndex => _currentLyricIndex;

  // Chords
  List<ChordEvent>? _chords;
  List<ChordEvent>? get chords => _chords;

  int _currentChordIndex = -1;
  int get currentChordIndex => _currentChordIndex;

  ChordEvent? get currentChord {
    if (_chords == null || _chords!.isEmpty) return null;
    if (_currentChordIndex >= 0 && _currentChordIndex < _chords!.length) {
      return _chords![_currentChordIndex];
    }
    return _chords!.first;
  }

  ChordEvent? get nextChord {
    if (_chords == null || _chords!.isEmpty) return null;
    final targetIdx = _currentChordIndex < 0 ? 1 : _currentChordIndex + 1;
    if (targetIdx < _chords!.length) {
      return _chords![targetIdx];
    }
    return null;
  }

  /// Returns the chord associated with a specific lyric line
  ChordEvent? getChordForLyric(LyricLine lyric) {
    if (_chords == null || _chords!.isEmpty) return null;
    for (int i = _chords!.length - 1; i >= 0; i--) {
      if (_chords![i].timestamp <= lyric.timestamp) {
        return _chords![i];
      }
    }
    return _chords!.first;
  }

  /// Returns all unique chord names used in the song in chronological order
  List<String> get uniqueSongChords {
    if (_chords == null || _chords!.isEmpty) return const [];
    final seen = <String>{};
    final list = <String>[];
    for (final c in _chords!) {
      if (seen.add(c.chordName)) {
        list.add(c.chordName);
      }
    }
    return list;
  }

  /// Returns the first ChordEvent matching chordName for diagram inspection
  ChordEvent? getChordDetails(String chordName) {
    if (_chords == null) return null;
    for (final c in _chords!) {
      if (c.chordName == chordName) return c;
    }
    return null;
  }

  // Harmonic information (Key, Capo, Tuning)
  String? _musicalKey;
  String? get musicalKey => _musicalKey;

  int? _capo;
  int? get capo => _capo;

  String? _tuning;
  String? get tuning => _tuning;

  // Chord synchronization latency calibration (default: 0ms for exact on-beat changes)
  int _chordOffsetMs = 0;
  int get chordOffsetMs => _chordOffsetMs;

  void setChordOffset(int offsetMs) {
    _chordOffsetMs = offsetMs.clamp(-2000, 2000);
    if (_isWindows) {
      _syncChords(_windowsPlayer?.position ?? Duration.zero);
    } else {
      _syncChords(_audioPlayer?.position ?? Duration.zero);
    }
    notifyListeners();
  }

  void adjustChordOffset(int deltaMs) {
    setChordOffset(_chordOffsetMs + deltaMs);
  }

  // Error message
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Metadata loading flag
  bool _isLoadingMetadata = false;
  bool get isLoadingMetadata => _isLoadingMetadata;

  // Streams for reactive UI
  final _stateController = BehaviorSubject<PlaybackState>.seeded(PlaybackState.idle);
  Stream<PlaybackState> get stateStream => _stateController.stream;

  final _currentLyricController = BehaviorSubject<LyricLine?>();
  Stream<LyricLine?> get currentLyricStream => _currentLyricController.stream;

  final _currentChordController = BehaviorSubject<ChordEvent?>();
  Stream<ChordEvent?> get currentChordStream => _currentChordController.stream;

  final _progressController = BehaviorSubject<double>.seeded(0.0);
  Stream<double> get progressStream => _progressController.stream;

  StreamSubscription? _positionSubscription;
  final List<StreamSubscription> _windowsSubscriptions = [];

  // Expose the underlying just_audio player for widgets that need it directly
  AudioPlayer? get player => _audioPlayer;

  /// Unified position stream (works on both Windows media_kit and just_audio)
  Stream<Duration> get positionStream {
    if (_isWindows) {
      return _windowsPlayer!.positionStream;
    }
    return _audioPlayer!.positionStream;
  }

  /// Unified duration getter (works on both Windows media_kit and just_audio)
  Duration? get currentDuration {
    if (_isWindows) {
      return _windowsPlayer!.duration;
    }
    return _audioPlayer!.duration;
  }

  MusicPlayerController() {
    if (_isWindows) {
      _windowsPlayer = WindowsAudioPlayer();
      _initWindowsListeners();
    } else {
      _audioPlayer = AudioPlayer();
      _initJustAudioListeners();
    }
  }

  void _initWindowsListeners() {
    final wp = _windowsPlayer!;

    // playing=true → playing state; playing=false → paused (unless loading)
    _windowsSubscriptions.add(wp.playingStream.listen((playing) {
      debugPrint('[MusicPlayerController] Windows playing=$playing');
      if (playing) {
        _updateState(PlaybackState.playing);
      } else if (_state == PlaybackState.playing) {
        _updateState(PlaybackState.paused);
      }
    }));

    // Position updates → sync lyrics/chords/progress
    _windowsSubscriptions.add(wp.positionStream.listen((position) {
      if (position > Duration.zero && _state != PlaybackState.playing && _state != PlaybackState.paused) {
        _updateState(PlaybackState.playing);
      }
      final dur = wp.duration;
      if (dur != null && dur.inMilliseconds > 0) {
        final progress = position.inMilliseconds / dur.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
      _syncLyrics(position);
      _syncChords(position);
    }));

    // Buffering → show buffering state
    _windowsSubscriptions.add(wp.bufferingStream.listen((buffering) {
      if (buffering && _state != PlaybackState.playing) {
        _updateState(PlaybackState.buffering);
      } else if (!buffering && _state == PlaybackState.buffering) {
        _updateState(wp.playing ? PlaybackState.playing : PlaybackState.paused);
      }
    }));

    // Completed
    _windowsSubscriptions.add(wp.completedStream.listen((completed) {
      if (completed) {
        _updateState(PlaybackState.completed);
        _currentLyricIndex = -1;
        _currentChordIndex = -1;
        _currentLyricController.add(null);
        _currentChordController.add(null);
      }
    }));

    // Errors
    _windowsSubscriptions.add(wp.errorStream.listen((error) {
      if (error != null && error.isNotEmpty) {
        debugPrint('[MusicPlayerController] Windows player error: $error');
        _errorMessage = 'Audio error: $error';
        _updateState(PlaybackState.error);
      }
    }));
  }

  void _initJustAudioListeners() {
    final ap = _audioPlayer!;

    // Player state changes
    ap.playerStateStream.listen((playerState) {
      final processingState = playerState.processingState;
      final playing = playerState.playing;

      if (playing) {
        _updateState(PlaybackState.playing);
      } else if (processingState == ProcessingState.loading) {
        _updateState(PlaybackState.loading);
      } else if (processingState == ProcessingState.buffering) {
        _updateState(PlaybackState.buffering);
      } else if (processingState == ProcessingState.ready) {
        _updateState(ap.playing ? PlaybackState.playing : PlaybackState.paused);
      } else if (processingState == ProcessingState.completed) {
        _updateState(PlaybackState.completed);
        _currentLyricIndex = -1;
        _currentChordIndex = -1;
        _currentLyricController.add(null);
        _currentChordController.add(null);
      }
    });

    // Progress updates for slider
    ap.positionStream.listen((position) {
      final duration = ap.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final progress = position.inMilliseconds / duration.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
    });

    // Error handling
    ap.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint('[MusicPlayerController] Playback event error: $e');
        _errorMessage = 'Audio error: ${e.toString().split('\n').first}';
        _updateState(PlaybackState.error);
      },
    );
  }

  void _updateState(PlaybackState newState) {
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  /// Plays a song (YouTube or local file)
  Future<void> playSong(Song song) async {
    try {
      _updateState(PlaybackState.loading);
      _errorMessage = null;
      _currentSong = song;
      _lyrics = null;
      _chords = null;
      _musicalKey = null;
      _capo = null;
      _tuning = null;
      _currentLyricIndex = -1;
      _currentChordIndex = -1;
      _progressController.add(0.0);
      _currentLyricController.add(null);
      _currentChordController.add(null);
      notifyListeners();

      // Automatically persist to recently played songs history
      unawaited(RecentlyPlayedService.addSong(song));

      // Cancel existing sync loop (non-Windows)
      _positionSubscription?.cancel();
      _positionSubscription = null;

      // 1. Check if song is an embedded asset track (e.g. acoustic guitar demo)
      if (song.isAsset) {
        _musicalKey = 'G';
        _tuning = 'Standard (E A D G B E)';
        _capo = null;
        _lyrics = [
          LyricLine(timestamp: const Duration(seconds: 0), text: "Morceau de démonstration - Guitare Acoustique"),
          LyricLine(timestamp: const Duration(seconds: 3), text: "Les cordes résonnent avec clarté [Sol Majeur]"),
          LyricLine(timestamp: const Duration(seconds: 6), text: "Douce vibration d'un accord en bois [Mi Mineur]"),
          LyricLine(timestamp: const Duration(seconds: 9), text: "Le rythme de la guitare acoustique [Do Majeur]"),
          LyricLine(timestamp: const Duration(seconds: 12), text: "Une mélodie pure et harmonieuse [Ré Majeur]"),
          LyricLine(timestamp: const Duration(seconds: 15), text: "Arpège joué note après note [Sol Majeur]"),
          LyricLine(timestamp: const Duration(seconds: 18), text: "Les accords s'enchaînent parfaitement [Mi Mineur]"),
          LyricLine(timestamp: const Duration(seconds: 21), text: "Écoutez chaque nuance acoustique [Do Majeur]"),
          LyricLine(timestamp: const Duration(seconds: 24), text: "Fin de la démonstration musicale [Ré Majeur]"),
        ];
        _chords = [
          ChordEvent(timestamp: const Duration(seconds: 0), chordName: 'G', fretPositions: [3, 2, 0, 0, 0, 3]),
          ChordEvent(timestamp: const Duration(seconds: 6), chordName: 'Em', fretPositions: [0, 2, 2, 0, 0, 0]),
          ChordEvent(timestamp: const Duration(seconds: 12), chordName: 'C', fretPositions: [-1, 3, 2, 0, 1, 0]),
          ChordEvent(timestamp: const Duration(seconds: 18), chordName: 'D', fretPositions: [-1, -1, 0, 2, 3, 2]),
        ];
        _isLoadingMetadata = false;
        notifyListeners();

        await _playAssetSong(song);
        return;
      }

      // 2. Fetch lyrics & chords for external / local tracks
      _isLoadingMetadata = true;
      notifyListeners();

      final parsed = TitleParser.extractArtistAndTitle(song.title, song.artist);
      debugPrint('[MusicPlayerController] Starting metadata load for: "${parsed.artist}" - "${parsed.title}"');

      unawaited(() async {
        await _loadLyrics(parsed.title, parsed.artist, song.durationSeconds);
        // Synchronize chords with lyric timestamps
        await _loadChords(
          parsed.title,
          parsed.artist,
          lyrics: _lyrics,
          durationSeconds: song.durationSeconds,
        );
        _isLoadingMetadata = false;
        notifyListeners();
      }());

      // 3. Audio playback
      if (song.isLocal) {
        await _playLocalFile(song);
      } else {
        await _playYouTubeSong(song);
      }
    } catch (e) {
      if (e.toString().contains('Loading interrupted') || e.toString().contains('interrupted')) {
        debugPrint('[MusicPlayerController] Ignored loading interrupted during transition');
        return;
      }
      _errorMessage = 'Error: ${e.toString().split('\n').first}';
      _updateState(PlaybackState.error);
      debugPrint('[MusicPlayerController] playSong error: $e');
    }
  }

  Future<void> _playAssetSong(Song song) async {
    final assetPath = song.assetPath!;
    debugPrint('[MusicPlayerController] Playing asset track: $assetPath');

    try {
      if (_isWindows) {
        // Resolve asset path for Windows and play via media_kit
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidate1 = '$exeDir/data/flutter_assets/$assetPath';
        final candidate2 = 'data/flutter_assets/$assetPath';
        final candidate3 = assetPath;
        String? resolvedPath;
        if (File(candidate1).existsSync()) {
          resolvedPath = candidate1;
        } else if (File(candidate2).existsSync()) {
          resolvedPath = candidate2;
        } else if (File(candidate3).existsSync()) {
          resolvedPath = File(candidate3).absolute.path;
        }

        if (resolvedPath != null) {
          debugPrint('[MusicPlayerController] Playing Windows asset via media_kit: $resolvedPath');
          await _windowsPlayer!.playFile(resolvedPath);
          _updateState(PlaybackState.playing);
        } else {
          try {
            await _windowsPlayer!.playUrl('asset:///$assetPath');
            _updateState(PlaybackState.playing);
          } catch (_) {
            _errorMessage = 'Asset audio file not found: $assetPath';
            _updateState(PlaybackState.error);
            return;
          }
        }
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        await _audioPlayer!.setAudioSource(
          AudioSource.asset(
            assetPath,
            tag: MediaItem(
              id: song.id,
              title: song.title,
              artist: song.artist,
            ),
          ),
        );
        await _audioPlayer!.play();
      } else {
        await _audioPlayer!.setAsset(assetPath);
        await _audioPlayer!.play();
      }

      debugPrint('[MusicPlayerController] Asset playback started');
      if (!_isWindows) {
        _updateState(PlaybackState.playing);
        _startSyncLoop();
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] Asset playback error: $e');
      _errorMessage = 'Erreur audio : ${e.toString().split('\n').first}';
      _updateState(PlaybackState.error);
    }
  }

  Future<void> _playYouTubeSong(Song song) async {
    debugPrint('[MusicPlayerController] Extracting audio for: ${song.title}');

    try {
      if (_isWindows) {
        // On Windows: use the loopback proxy to handle YouTube auth/signing,
        // then media_kit (libmpv) reads from http://127.0.0.1 — no WMF restriction.
        final proxyUrl = await LocalAudioProxy.instance.getProxyStreamUrl(song.id);
        debugPrint('[MusicPlayerController] Streaming via proxy+media_kit: $proxyUrl');
        await _windowsPlayer!.playUrl(proxyUrl);
        _updateState(PlaybackState.playing);
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        // Mobile playback: use local proxy streaming for instant start,
        // and seamlessly fall back to chunked file download if upstream streaming fails.
        bool playbackStarted = false;
        try {
          final proxyUrl = await LocalAudioProxy.instance.getProxyStreamUrl(song.id);
          debugPrint('[MusicPlayerController] Streaming via proxy+just_audio: $proxyUrl');
          await _audioPlayer!.stop();
          await _audioPlayer!.setAudioSource(
            AudioSource.uri(
              Uri.parse(proxyUrl),
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
                artUri: song.thumbnailUrl != null ? Uri.parse(song.thumbnailUrl!) : null,
              ),
            ),
          );
          await _audioPlayer!.play();
          playbackStarted = true;
          _updateState(PlaybackState.playing);
          _startSyncLoop();
        } catch (proxyError) {
          debugPrint('[MusicPlayerController] Mobile proxy streaming failed: $proxyError. Trying download fallback...');
        }

        if (!playbackStarted) {
          final tmpFile = await _youtubeService.downloadToTempFile(song.id);
          if (tmpFile == null || !tmpFile.existsSync()) {
            _errorMessage = "Impossible de charger l'audio pour cette chanson.";
            _updateState(PlaybackState.error);
            return;
          }
          debugPrint('[MusicPlayerController] Playing downloaded temp file: ${tmpFile.path}');
          await _audioPlayer!.stop();
          await _audioPlayer!.setAudioSource(
            AudioSource.file(
              tmpFile.path,
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
                artUri: song.thumbnailUrl != null ? Uri.parse(song.thumbnailUrl!) : null,
              ),
            ),
          );
          await _audioPlayer!.play();
          _updateState(PlaybackState.playing);
          _startSyncLoop();
        }
      } else {
        // Web / fallback
        final streamUrl = await _youtubeService.getAudioStreamUrl(song.id);
        if (streamUrl == null) {
          _errorMessage = "Impossible d'extraire le flux audio pour cette chanson.";
          _updateState(PlaybackState.error);
          return;
        }
        await _audioPlayer!.stop();
        await _audioPlayer!.setUrl(streamUrl);
        await _audioPlayer!.play();
        _updateState(PlaybackState.playing);
        _startSyncLoop();
      }
    } catch (e) {
      if (e.toString().contains('Loading interrupted') || e.toString().contains('interrupted')) {
        debugPrint('[MusicPlayerController] Ignored loading interrupted during transition');
        return;
      }
      debugPrint('[MusicPlayerController] Playback setup error: $e');
      _errorMessage = "Erreur audio : ${e.toString().split('\n').first}";
      _updateState(PlaybackState.error);
    }
  }

  Future<void> _playLocalFile(Song song) async {
    final path = song.localPath!;
    debugPrint('[MusicPlayerController] Playing local file: $path');

    try {
      final file = File(path);
      if (!path.startsWith('content://') && !file.existsSync()) {
        _errorMessage = 'Fichier audio introuvable : $path';
        _updateState(PlaybackState.error);
        return;
      }

      if (_isWindows) {
        // media_kit can play local files directly on Windows
        await _windowsPlayer!.playFile(path);
        _updateState(PlaybackState.playing);
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        if (path.startsWith('content://')) {
          await _audioPlayer!.setAudioSource(
            AudioSource.uri(
              Uri.parse(path),
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
              ),
            ),
          );
        } else {
          await _audioPlayer!.setAudioSource(
            AudioSource.file(
              path,
              tag: MediaItem(
                id: song.id,
                title: song.title,
                artist: song.artist,
              ),
            ),
          );
        }
        await _audioPlayer!.play();
        _updateState(PlaybackState.playing);
        _startSyncLoop();
      } else {
        await _audioPlayer!.setFilePath(path);
        await _audioPlayer!.play();
        _updateState(PlaybackState.playing);
        _startSyncLoop();
      }
    } catch (e) {
      if (e.toString().contains('Loading interrupted') || e.toString().contains('interrupted')) {
        debugPrint('[MusicPlayerController] Ignored loading interrupted');
        return;
      }
      debugPrint('[MusicPlayerController] Local playback error: $e');
      _errorMessage = 'Local file error: ${e.toString().split('\n').first}';
      _updateState(PlaybackState.error);
    }
  }

  Future<void> _loadLyrics(String title, String artist, int? durationSeconds) async {
    try {
      _lyrics = await _lyricsService.fetchSyncedLyrics(
        trackName: title,
        artistName: artist,
        duration: durationSeconds,
      );

      if (_lyrics != null) {
        debugPrint('[MusicPlayerController] Loaded ${_lyrics!.length} lyric lines');
      } else {
        debugPrint('[MusicPlayerController] No lyrics found');
      }
    } catch (e) {
      debugPrint('[MusicPlayerController] Lyrics load error: $e');
      _lyrics = null;
    }
    notifyListeners();
  }

  Future<void> _loadChords(
    String title,
    String artist, {
    List<LyricLine>? lyrics,
    int? durationSeconds,
  }) async {
    try {
      final result = await _chordsService.fetchChords(
        title: title,
        artist: artist,
        lyrics: lyrics,
        durationSeconds: durationSeconds,
      );

      _chords = result.chords;
      _musicalKey = result.musicalKey;
      _capo = result.capo;
      _tuning = result.tuning;

      debugPrint('[MusicPlayerController] Loaded ${_chords?.length ?? 0} chords (Key: $_musicalKey, Capo: $_capo)');
    } catch (e) {
      debugPrint('[MusicPlayerController] Chords load error: $e');
      _chords = null;
      _musicalKey = null;
      _capo = null;
      _tuning = null;
    }
    notifyListeners();
  }

  /// Main synchronization loop (non-Windows, handled via stream listener on Windows)
  void _startSyncLoop() {
    _positionSubscription?.cancel();
    _positionSubscription = _audioPlayer!.positionStream.listen((position) {
      _syncLyrics(position);
      _syncChords(position);
    });
  }

  void _syncLyrics(Duration position) {
    if (_lyrics == null || _lyrics!.isEmpty) return;

    int newIndex = -1;
    for (int i = _lyrics!.length - 1; i >= 0; i--) {
      if (_lyrics![i].timestamp <= position) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      _currentLyricController.add(newIndex >= 0 ? _lyrics![newIndex] : null);
      notifyListeners();
    }
  }

  void _syncChords(Duration position) {
    if (_chords == null || _chords!.isEmpty) return;

    // Compensate for premature lyric timing so chords trigger exactly on the beat
    final effectivePosition = position - Duration(milliseconds: _chordOffsetMs);
    if (effectivePosition < Duration.zero) {
      if (_currentChordIndex != 0) {
        _currentChordIndex = 0;
        _currentChordController.add(_chords!.first);
        notifyListeners();
      }
      return;
    }

    int newIndex = -1;
    for (int i = _chords!.length - 1; i >= 0; i--) {
      if (_chords![i].timestamp <= effectivePosition) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentChordIndex) {
      _currentChordIndex = newIndex;
      _currentChordController.add(newIndex >= 0 ? _chords![newIndex] : null);
      notifyListeners();
    }
  }

  // Transport controls
  Future<void> togglePlayPause() async {
    if (_state == PlaybackState.playing) {
      await pause();
    } else if (_state == PlaybackState.paused) {
      await resume();
    } else if (_currentSong != null) {
      // If in error, loading timeout, or stopped, tapping play retries the current song
      await playSong(_currentSong!);
    }
  }

  Future<void> pause() async {
    if (_isWindows) {
      await _windowsPlayer!.pause();
    } else {
      await _audioPlayer!.pause();
    }
  }

  Future<void> resume() async {
    if (_isWindows) {
      if (_windowsPlayer!.duration == null) {
        await playSong(_currentSong!);
        return;
      }
      await _windowsPlayer!.play();
    } else {
      if (_currentSong != null && _audioPlayer!.duration == null) {
        await playSong(_currentSong!);
        return;
      }
      await _audioPlayer!.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (_isWindows) {
      await _windowsPlayer!.seek(position);
    } else {
      await _audioPlayer!.seek(position);
    }
    _syncLyrics(position);
    _syncChords(position);
  }

  Future<void> seekForward() async {
    final current = _isWindows ? _windowsPlayer!.position : _audioPlayer!.position;
    await seek(current + const Duration(seconds: 10));
  }

  Future<void> seekBackward() async {
    final current = _isWindows ? _windowsPlayer!.position : _audioPlayer!.position;
    final target = current - const Duration(seconds: 10);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> setVolume(double volume) async {
    if (_isWindows) {
      await _windowsPlayer!.setVolume(volume);
    } else {
      await _audioPlayer!.setVolume(volume.clamp(0.0, 1.0));
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    for (final sub in _windowsSubscriptions) {
      sub.cancel();
    }
    _windowsPlayer?.dispose();
    _audioPlayer?.dispose();
    _youtubeService.dispose();
    _stateController.close();
    _currentLyricController.close();
    _currentChordController.close();
    _progressController.close();
    super.dispose();
  }
}
