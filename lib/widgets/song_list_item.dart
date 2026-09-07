import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';

class SongListItem extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isPlaying;

  const SongListItem({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isPlaying
              ? const Color(0xFFFF8C00).withValues(alpha: 0.1)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPlaying
                ? const Color(0xFFFF8C00).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: song.thumbnailUrl!,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 54,
                            height: 54,
                            color: const Color(0xFF252525),
                          ),
                          errorWidget: (_, __, ___) => _buildThumbnailPlaceholder(),
                        )
                      : _buildThumbnailPlaceholder(),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: const Icon(
                          Icons.equalizer_rounded,
                          color: Color(0xFFFF8C00),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isPlaying ? const Color(0xFFFFAA33) : Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Duration + play icon
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (song.durationSeconds != null)
                  Text(
                    _formatDuration(song.durationSeconds!),
                    style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
                  ),
                const SizedBox(height: 4),
                Icon(
                  isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: isPlaying ? const Color(0xFFFF8C00) : const Color(0xFF444444),
                  size: 24,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_rounded, color: Color(0xFF444444), size: 24),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
