import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../controllers/music_player_controller.dart';

/// Floating mini player shown at the bottom of tabs or in sidebar when a song is playing.
class MiniPlayer extends StatelessWidget {
  final MusicPlayerController controller;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (controller.currentSong == null) return const SizedBox.shrink();

        return AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset: controller.currentSong == null ? const Offset(0, 1) : Offset.zero,
          child: _buildContent(context),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final song = controller.currentSong!;
    final isPlaying = controller.state == PlaybackState.playing;
    final isLoading = controller.state == PlaybackState.loading ||
        controller.state == PlaybackState.buffering;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 300;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: EdgeInsets.fromLTRB(isNarrow ? 0 : 10, 0, isNarrow ? 0 : 10, 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.06),
                  blurRadius: 16,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main row
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          bottomLeft: Radius.circular(14),
                        ),
                        child: song.thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: song.thumbnailUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _buildThumbnailPlaceholder(),
                              )
                            : _buildThumbnailPlaceholder(),
                      ),

                      // Title + artist
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Controls
                      if (!isNarrow) ...[
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: Color(0xFF888888), size: 20),
                          onPressed: controller.seekBackward,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                        const SizedBox(width: 4),
                      ],

                      // Play/Pause button
                      Padding(
                        padding: EdgeInsets.only(right: isNarrow ? 10 : 6),
                        child: GestureDetector(
                          onTap: controller.togglePlayPause,
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: isLoading
                                ? Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: const Color(0xFFFF8C00).withValues(alpha: 0.8),
                                    ),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF8C00), Color(0xFFFF5500)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      if (!isNarrow) ...[
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: Color(0xFF888888), size: 20),
                          onPressed: controller.seekForward,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),

                // Progress bar
                StreamBuilder<double>(
                  stream: controller.progressStream,
                  builder: (context, snapshot) {
                    final progress = snapshot.data ?? 0.0;
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF8C00)),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      color: const Color(0xFF222222),
      child: const Icon(Icons.music_note_rounded, color: Colors.white24, size: 22),
    );
  }
}
