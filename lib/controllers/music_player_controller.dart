import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song.dart';
import '../models/lyric_line.dart';
import '../models/chord_event.dart';
import '../models/chord_timeline.dart';
import '../services/youtube_service.dart';
import '../services/windows_audio_player.dart';
import '../services/local_audio_proxy.dart';
import '../services/lrclib_service.dart';
import '../services/stream_chord_analyzer.dart';
import '../services/audio_chord_detector_service.dart';
import '../services/capo_chords.dart';
import '../services/recently_played_service.dart';
import '../utils/title_parser.dart';
import '../services/screen_awake_service.dart';
import '../services/song_key_estimator.dart';
import '../services/web_lyrics_service.dart';

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
  final WebLyricsService _webLyrics = WebLyricsService();
  final StreamChordAnalyzer _streamChordAnalyzer = StreamChordAnalyzer();
  final ScreenAwakeService _screenAwake = ScreenAwakeService();

  // Playback state
  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  double _volume = 1.0;
  double _volumeBeforeMute = 1.0;
  double get volume => _volume;

  Future<void> toggleMute() =>
      setVolume(_volume == 0 ? _volumeBeforeMute : 0);

  // Active song data
  Song? _currentSong;
  int _metadataGeneration = 0;
  bool _isPreparingPlayback = false;
  Song? get currentSong => _currentSong;

  // Lyrics
  List<LyricLine>? _lyrics;
  List<LyricLine>? get lyrics => _lyrics;

  int _currentLyricIndex = -1;
  int get currentLyricIndex => _currentLyricIndex;

  // Chords
  List<ChordEvent>? _chords;
  List<ChordEvent>? _concertChords;
  final Map<String, int> _selectedCapos = {};
  List<ChordEvent>? get chords => _chords;
  String _chordStatus = 'Accords indisponibles';
  String get chordStatus => _chordStatus;

  int _currentChordIndex = -1;
  Duration _chordPosition = Duration.zero;
  int get currentChordIndex => _currentChordIndex;

  ChordEvent? get currentChord {
    if (_chords == null || _chords!.isEmpty) return null;
    if (_currentChordIndex >= 0 && _currentChordIndex < _chords!.length) {
      return _chords![_currentChordIndex];
    }
    return null;
  }

  ChordEvent? get nextChord {
    if (_chords == null || _chords!.isEmpty) return null;
    final targetIdx = ChordTimeline.nextIndex(_chords!, _chordPosition);
    if (targetIdx < _chords!.length) {
      return _chords![targetIdx];
    }
    return null;
  }

  /// Returns the chord associated with a specific lyric line
  ChordEvent? getChordForLyric(LyricLine lyric) {
    if (_chords == null || _chords!.isEmpty) return null;
    final index = ChordTimeline.activeIndex(_chords!, lyric.timestamp);
    return index < 0 ? null : _chords![index];
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

  /// null displays concert pitch; an explicit fret displays playable shapes.
  void setCapo(int? fret) {
    if (fret != null) RangeError.checkValueInInterval(fret, 0, 12, 'fret');
    final id = _currentSong?.id;
    if (id != null) {
      if (fret == null) {
        _selectedCapos.remove(id);
      } else {
        _selectedCapos[id] = fret;
      }
    }
    _capo = fret;
    _chords = _concertChords?.map((c) => CapoChords.shape(c, fret ?? 0)).toList();
    _currentChordController.add(currentChord);
    notifyListeners();
  }

  String? _tuning;
  String? get tuning => _tuning;

  // Error message
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Metadata loading flags (chords block playback start, lyrics do not)
  bool _isLoadingMetadata = false;
  bool _isLoadingLyrics = false;
  bool get isLoadingMetadata => _isLoadingMetadata || _isLoadingLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;

  Duration get _playbackPosition {
    if (_isPreparingPlayback) return Duration.zero;
    if (_isWindows) return _windowsPlayer?.position ?? Duration.zero;
    return _audioPlayer?.position ?? Duration.zero;
  }

  // Streams for reactive UI
  final _stateController = BehaviorSubject<PlaybackState>.seeded(PlaybackState.idle);
  Stream<PlaybackState> get stateStream => _stateController.stream;

  final _currentLyricController = BehaviorSubject<LyricLine?>();
  Stream<LyricLine?> get currentLyricStream => _currentLyricController.stream;

  final _currentChordController = BehaviorSubject<ChordEvent?>();
  Stream<ChordEvent?> get currentChordStream => _currentChordController.stream;

  final _progressController = BehaviorSubject<double>.seeded(0.0);
  Stream<double> get progressStream => _progressController.stream;

  final List<StreamSubscription> _playerSubscriptions = [];

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

  MusicPlayerController({AudioPlayer? audioPlayer}) {
    if (_isWindows) {
      _windowsPlayer = WindowsAudioPlayer();
      _initWindowsListeners();
    } else {
      _audioPlayer = audioPlayer ?? AudioPlayer();
      _initJustAudioListeners();
    }
  }

  void _initWindowsListeners() {
    final wp = _windowsPlayer!;

    // playing=true → playing state; playing=false → paused (unless loading)
    _playerSubscriptions.add(wp.playingStream.listen((playing) {
      if (_isPreparingPlayback) return;
      debugPrint('[MusicPlayerController] Windows playing=$playing');
      if (playing) {
        _updateState(PlaybackState.playing);
      } else if (_state == PlaybackState.playing) {
        _updateState(PlaybackState.paused);
      }
    }));

    // Position updates → sync lyrics/chords/progress
    _playerSubscriptions.add(wp.positionStream.listen((position) {
      if (_isPreparingPlayback) return;
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
    _playerSubscriptions.add(wp.bufferingStream.listen((buffering) {
      if (_isPreparingPlayback) return;
      if (buffering && _state != PlaybackState.playing) {
        _updateState(PlaybackState.buffering);
      } else if (!buffering && _state == PlaybackState.buffering) {
        _updateState(wp.playing ? PlaybackState.playing : PlaybackState.paused);
      }
    }));

    // Completed
    _playerSubscriptions.add(wp.completedStream.listen((completed) {
      if (_isPreparingPlayback) return;
      if (completed) {
        _updateState(PlaybackState.completed);
        _currentLyricIndex = -1;
        _currentChordIndex = -1;
        _currentLyricController.add(null);
        _currentChordController.add(null);
      }
    }));

    // Errors
    _playerSubscriptions.add(wp.errorStream.listen((error) {
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
    _playerSubscriptions.add(ap.playerStateStream.listen((playerState) {
      if (_isPreparingPlayback) return;
      final processingState = playerState.processingState;
      final playing = playerState.playing;

      if (processingState == ProcessingState.loading) {
        _updateState(PlaybackState.loading);
      } else if (processingState == ProcessingState.buffering) {
        _updateState(PlaybackState.buffering);
      } else if (processingState == ProcessingState.ready) {
        _updateState(playing ? PlaybackState.playing : PlaybackState.paused);
      } else if (processingState == ProcessingState.completed) {
        _updateState(PlaybackState.completed);
        _currentLyricIndex = -1;
        _currentChordIndex = -1;
        _currentLyricController.add(null);
        _currentChordController.add(null);
      }
    }));

    // Subscribe before playback: play() completes only when playback stops.
    _playerSubscriptions.add(ap.positionStream.listen((position) {
      if (_isPreparingPlayback) return;
      final duration = ap.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        final progress = position.inMilliseconds / duration.inMilliseconds;
        _progressController.add(progress.clamp(0.0, 1.0));
      }
      _syncLyrics(position);
      _syncChords(position);
    }));

    // Error handling
    _playerSubscriptions.add(ap.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint('[MusicPlayerController] Playback event error: $e');
        _errorMessage = 'Audio error: ${e.toString().split('\n').first}';
        _updateState(PlaybackState.error);
      },
    ));
  }

  void _updateState(PlaybackState newState) {
    unawaited(_screenAwake.setEnabled(
      newState == PlaybackState.playing ||
          (newState == PlaybackState.buffering && _screenAwake.enabled),
    ));
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  /// Plays a song (YouTube or local file)
  Future<void> playSong(Song song) async {
    final generation = ++_metadataGeneration;
    _isPreparingPlayback = true;
    try {
      _updateState(PlaybackState.loading);
      _errorMessage = null;
      _currentSong = song;
      _lyrics = null;
      _isLoadingLyrics = false;
      _chords = null;
      _concertChords = null;
      _chordStatus = 'Préparation des accords avant lecture…';
      _musicalKey = null;
      _capo = _selectedCapos[song.id];
      _tuning = null;
      _currentLyricIndex = -1;
      _currentChordIndex = -1;
      _chordPosition = Duration.zero;
      _progressController.add(0.0);
      _currentLyricController.add(null);
      _currentChordController.add(null);
      notifyListeners();

      // Automatically persist to recently played songs history
      unawaited(RecentlyPlayedService.addSong(song));

      // Stop the previous track while the next track's chords are prepared.
      if (_isWindows) {
        await _windowsPlayer!.stop();
      } else {
        await _audioPlayer!.stop();
      }
      if (generation != _metadataGeneration) return;

      // 1. Check if song is an embedded asset track (e.g. acoustic guitar demo)
      if (song.isAsset) {
        _chordStatus = 'Accords de démonstration';
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
        _concertChords = _chords;
        _syncLyrics(Duration.zero);
        _syncChords(Duration.zero);
        _isPreparingPlayback = false;
        notifyListeners();

        await _playAssetSong(song);
        return;
      }

      // 2. Fetch lyrics & chords for external / local tracks
      _isLoadingMetadata = true;
      notifyListeners();

      final parsed = TitleParser.extractArtistAndTitle(song.title, song.artist);
      debugPrint('[MusicPlayerController] Starting metadata load for: "${parsed.artist}" - "${parsed.title}"');

      // Lyrics never delay playback: LRCLIB is quick, but the web-search
      // fallback can take a while, so they are applied whenever they arrive.
      _isLoadingLyrics = true;
      unawaited(_loadLyrics(parsed.title, parsed.artist, song.durationSeconds, generation));
      // Chords are prepared before playback so they are in sync from 0:00.
      await _loadChords(song, generation: generation);
      if (generation != _metadataGeneration) return;
      _isLoadingMetadata = false;
      if (_chords == null || _chords!.isEmpty) {
        // Missing chords (web build, analysis failure…) must not block
        // listening: the status text already explains the situation.
        debugPrint('[MusicPlayerController] No chords available, playing anyway');
      }
      _syncLyrics(Duration.zero);
      _syncChords(Duration.zero);
      _isPreparingPlayback = false;
      notifyListeners();

      // 3. Audio playback
      if (song.isLocal) {
        await _playLocalFile(song);
      } else {
        await _playYouTubeSong(song);
      }
    } catch (e) {
      if (generation != _metadataGeneration) return;
      _isPreparingPlayback = false;
      _isLoadingMetadata = false;
      _isLoadingLyrics = false;
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
      } else {
        await _audioPlayer!.setFilePath(path);
        await _audioPlayer!.play();
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

  Future<void> _loadLyrics(String title, String artist, int? durationSeconds, int generation) async {
    try {
      var lyrics = await _lyricsService.fetchSyncedLyrics(
        trackName: title,
        artistName: artist,
        duration: durationSeconds,
      );
      if (generation != _metadataGeneration) return;
      if (lyrics == null || lyrics.isEmpty) {
        // Not on LRCLIB: take the first web search result, even unsynced.
        debugPrint('[MusicPlayerController] LRCLIB has no lyrics, searching the web…');
        lyrics = await _webLyrics.search(title, artist,
            isCurrent: () => generation == _metadataGeneration);
      }
      if (generation != _metadataGeneration) return;
      if (lyrics != null && lyrics.isNotEmpty && lyrics.first.isSynced) {
        lyrics = _sortedByTimestamp(lyrics);
      }
      _lyrics = lyrics;
      _currentLyricIndex = -1;
      _currentLyricController.add(null);
      _syncLyrics(_playbackPosition);

      if (_lyrics != null) {
        debugPrint('[MusicPlayerController] Loaded ${_lyrics!.length} lyric lines'
            '${_lyrics!.first.isSynced ? '' : ' (unsynced, ${_lyrics!.first.sourceUrl?.host})'}');
      } else {
        debugPrint('[MusicPlayerController] No lyrics found');
      }
    } catch (e) {
      if (generation != _metadataGeneration) return;
      debugPrint('[MusicPlayerController] Lyrics load error: $e');
      _lyrics = null;
    } finally {
      if (generation == _metadataGeneration) _isLoadingLyrics = false;
    }
    notifyListeners();
  }

  /// Stable sort so binary search in [_syncLyrics] is valid even for LRC
  /// files whose lines are not strictly chronological.
  static List<LyricLine> _sortedByTimestamp(List<LyricLine> lines) {
    final indexed = List.generate(lines.length, (i) => i);
    indexed.sort((a, b) {
      final byTime = lines[a].timestamp.compareTo(lines[b].timestamp);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
    return [for (final i in indexed) lines[i]];
  }

  Future<void> _loadChords(
    Song song, {
    required int generation,
  }) async {
    try {
      // Both local files and YouTube use audio time, independent of lyrics.
      SongChordsResult? result;
      final localPath = song.localPath;
      if (localPath != null) {
        result = await AudioChordDetectorService.analyzeAudioFile(localPath);
      } else if (!kIsWeb) {
        final url = await LocalAudioProxy.instance.getProxyStreamUrl(song.id);
        if (generation != _metadataGeneration) return;
        result = await _streamChordAnalyzer.analyze(Uri.parse(url),
            isCurrent: () => generation == _metadataGeneration);
      }

      if (generation != _metadataGeneration) return;
      _concertChords = result?.chords;
      _chords = _concertChords?.map((c) => CapoChords.shape(c, _capo ?? 0)).toList();
      _musicalKey = SongKeyEstimator.estimate(_concertChords ?? []);
      _tuning = result?.tuning;
      _chordStatus = result != null && result.chords.isNotEmpty
          ? result.analysisMethod ?? 'Accords estimés · moteur expérimental'
          : 'Accords indisponibles · analyse audio non concluante';
      _currentChordIndex = -1;
      _syncChords(_playbackPosition);

      debugPrint('[MusicPlayerController] Loaded ${_chords?.length ?? 0} chords (Key: $_musicalKey, Capo: $_capo)');
    } catch (e) {
      if (generation != _metadataGeneration) return;
      debugPrint('[MusicPlayerController] Chords load error: $e');
      _chords = null;
      _concertChords = null;
      _musicalKey = null;
      _tuning = null;
      _chordStatus = 'Analyse audio impossible · aucun accord généré';
    }
    notifyListeners();
  }

  void _syncLyrics(Duration position) {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) return;
    if (!lyrics.first.isSynced) return;

    // Fast path (runs on every position tick): still inside the active line.
    final current = _currentLyricIndex;
    if (current >= 0 &&
        current < lyrics.length &&
        lyrics[current].timestamp <= position &&
        (current + 1 >= lyrics.length || position < lyrics[current + 1].timestamp)) {
      return;
    }

    // Binary search for the last line starting at or before [position].
    var lo = 0;
    var hi = lyrics.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lyrics[mid].timestamp <= position) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final newIndex = lo - 1;

    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      _currentLyricController.add(newIndex >= 0 ? lyrics[newIndex] : null);
      notifyListeners();
    }
  }

  void _syncChords(Duration position) {
    if (_chords == null || _chords!.isEmpty) return;

    // Use audio timestamps, respecting gaps rather than holding an old chord.
    final effectivePosition = position;
    _chordPosition = effectivePosition;
    final newIndex = ChordTimeline.activeIndex(_chords!, effectivePosition);

    if (newIndex != _currentChordIndex) {
      _currentChordIndex = newIndex;
      _currentChordController.add(newIndex >= 0 ? _chords![newIndex] : null);
      notifyListeners();
    }
  }

  // Transport controls
  Future<void> togglePlayPause() async {
    if (_isPreparingPlayback) return;
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
    if (_isPreparingPlayback) return;
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
    if (_isPreparingPlayback) return;
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
    if (!volume.isFinite) return;
    final level = volume.clamp(0.0, 1.0);
    if (level > 0) _volumeBeforeMute = level;
    _volume = level;
    notifyListeners();
    if (_isWindows) {
      await _windowsPlayer!.setVolume(level);
    } else {
      await _audioPlayer!.setVolume(level);
    }
  }

  @override
  void dispose() {
    unawaited(_screenAwake.setEnabled(false));
    _metadataGeneration++;
    for (final sub in _playerSubscriptions) {
      sub.cancel();
    }
    _windowsPlayer?.dispose();
    _audioPlayer?.dispose();
    _youtubeService.dispose();
    _webLyrics.dispose();
    _stateController.close();
    _currentLyricController.close();
    _currentChordController.close();
    _progressController.close();
    super.dispose();
  }
}
