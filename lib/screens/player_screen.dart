import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../controllers/music_player_controller.dart';
import '../widgets/synced_lyrics_chords_view.dart';
import '../widgets/chord_diagram.dart';
import '../widgets/harmonic_info_bar.dart';

class PlayerScreen extends StatefulWidget {
  final MusicPlayerController controller;

  const PlayerScreen({super.key, required this.controller});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Duration _position = Duration.zero;
  String? _lastSongId;

  @override
  void initState() {
    super.initState();
    _lastSongId = widget.controller.currentSong?.id;
    widget.controller.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final song = widget.controller.currentSong;

        if (song != null && song.id != _lastSongId) {
          _lastSongId = song.id;
          _position = Duration.zero;
        }

        if (song == null) {
          return _buildEmptyState();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Blurred thumbnail background
              _buildBlurredBackground(song.thumbnailUrl),

              // Dark overlay
              Container(color: Colors.black.withValues(alpha: 0.78)),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = constraints.maxWidth > constraints.maxHeight;
                    return isLandscape
                        ? _buildLandscapePlayer(song, constraints)
                        : _buildMobilePlayer(song);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Landscape layout (Mobile landscape, Tablet & Desktop):
  /// Left column: Scrollable info, Key/Capo, Chords palette, diagrams & controls
  /// Right column: Full-height Synchronized Lyrics
  Widget _buildLandscapePlayer(song, BoxConstraints constraints) {
    final currentChord = widget.controller.currentChord;
    final nextChord = widget.controller.nextChord;
    final isShort = constraints.maxHeight < 480;

    return Column(
      children: [
        _buildAppBar(song),
        if (widget.controller.errorMessage != null) _buildErrorBanner(song),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(isShort ? 12 : 24, 4, isShort ? 12 : 24, isShort ? 8 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Panel: Scrollable Artwork / Chords + Controls
                Container(
                  width: (constraints.maxWidth * 0.45).clamp(320.0, 520.0),
                  padding: EdgeInsets.symmetric(
                    horizontal: isShort ? 14 : 20,
                    vertical: isShort ? 8 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Song info
                        Text(
                          song.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isShort ? 15 : 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artist,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: isShort ? 11 : 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: isShort ? 4 : 8),

                        // Key, Capo, and Chords palette bar
                        HarmonicInfoBar(controller: widget.controller),

                        SizedBox(height: isShort ? 4 : 8),

                        // Enlarged Chords Visualizer Section
                        Container(
                          margin: EdgeInsets.symmetric(vertical: isShort ? 4 : 8),
                          padding: EdgeInsets.symmetric(
                            horizontal: isShort ? 10 : 16,
                            vertical: isShort ? 8 : 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFFF8C00).withValues(alpha: 0.22),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'ACCORD ACTUEL',
                                style: TextStyle(
                                  fontSize: isShort ? 9 : 11,
                                  color: const Color(0xFFFF8C00),
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: isShort ? 6 : 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ChordDiagram(chord: currentChord, size: isShort ? 105 : 140),
                                  if (nextChord != null) ...[
                                    SizedBox(width: isShort ? 16 : 24),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'SUIVANT',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.white.withValues(alpha: 0.4),
                                            letterSpacing: 1.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Opacity(
                                          opacity: 0.55,
                                          child: ChordDiagram(chord: nextChord, size: isShort ? 68 : 88),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: isShort ? 6 : 12),

                        // Error message banner if any
                        if (widget.controller.errorMessage != null)
                          _buildErrorBanner(song),

                        // Player Controls
                        _buildPlayerControls(),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: isShort ? 10 : 16),

                // Right Panel: Synchronized Lyrics
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: SyncedLyricsChordsView(
                      controller: widget.controller,
                      currentPosition: _position,
                      showChordsHeader: false, // Chords are in the left panel on wide screens
                      lyricFontSize: isShort ? 18 : 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact portrait mobile layout: Top Chords + Lyrics + Bottom Controls
  Widget _buildMobilePlayer(song) {
    return Column(
      children: [
        _buildAppBar(song),
        if (widget.controller.errorMessage != null) _buildErrorBanner(song),
        Expanded(
          child: SyncedLyricsChordsView(
            controller: widget.controller,
            currentPosition: _position,
            showChordsHeader: true,
          ),
        ),
        _buildPlayerControls(),
      ],
    );
  }

  Widget _buildErrorBanner(song) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.controller.errorMessage!,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            onPressed: () => widget.controller.playSong(song),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFF8C00).withValues(alpha: 0.15),
                  Colors.transparent,
                ]),
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 64,
                color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No song playing',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for a song or pick a local file to get started',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurredBackground(String? thumbnailUrl) {
    if (thumbnailUrl == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0A00), Color(0xFF0D0D0D)],
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: thumbnailUrl,
      fit: BoxFit.cover,
      colorBlendMode: BlendMode.darken,
      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A0A00)),
    );
  }

  Widget _buildAppBar(song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: song.thumbnailUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: const Color(0xFF222222),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: const Color(0xFF222222),
                    child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.controller.isLoadingMetadata)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress slider
          StreamBuilder<double>(
            stream: widget.controller.progressStream,
            builder: (context, snapshot) {
              final progress = snapshot.data ?? 0.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (value) {
                        final duration = widget.controller.currentDuration;
                        if (duration != null) {
                          final newPos = Duration(
                            milliseconds: (duration.inMilliseconds * value).toInt(),
                          );
                          widget.controller.seek(newPos);
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position), style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
                        Text(
                          _formatDuration(widget.controller.currentDuration ?? Duration.zero),
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 6),

          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // -10s
              _ControlButton(
                icon: Icons.replay_10_rounded,
                size: 26,
                onPressed: widget.controller.seekBackward,
              ),
              const SizedBox(width: 20),

              // Play/Pause main button
              _buildPlayPauseButton(),

              const SizedBox(width: 20),

              // +10s
              _ControlButton(
                icon: Icons.forward_10_rounded,
                size: 26,
                onPressed: widget.controller.seekForward,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    final isPlaying = widget.controller.state == PlaybackState.playing;
    final isLoading = widget.controller.state == PlaybackState.loading;

    return GestureDetector(
      onTap: widget.controller.togglePlayPause,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 32,
                color: Colors.white,
              ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  const _ControlButton({required this.icon, required this.size, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white.withValues(alpha: 0.75), size: size),
      splashRadius: 22,
    );
  }
}
