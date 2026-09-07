import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import 'chord_diagram.dart';
import 'harmonic_info_bar.dart';

/// Main split view: chord diagram on top, auto-scrolling synchronized lyrics below.
class SyncedLyricsChordsView extends StatefulWidget {
  final MusicPlayerController controller;
  final Duration currentPosition;
  final double lyricFontSize;
  final bool showChordsHeader;

  const SyncedLyricsChordsView({
    super.key,
    required this.controller,
    required this.currentPosition,
    this.lyricFontSize = 18,
    this.showChordsHeader = true,
  });

  @override
  State<SyncedLyricsChordsView> createState() => _SyncedLyricsChordsViewState();
}

class _SyncedLyricsChordsViewState extends State<SyncedLyricsChordsView> {
  final ScrollController _scrollController = ScrollController();
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsChordsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScrollToActive();
  }

  void _maybeScrollToActive() {
    final idx = widget.controller.currentLyricIndex;
    if (idx < 0 || idx == _lastScrolledIndex) return;
    if (!_scrollController.hasClients) return;

    _lastScrolledIndex = idx;

    // Estimate item height (each lyric line ~52px with padding/margin)
    const itemHeight = 52.0;
    final targetOffset = (idx * itemHeight) - 120.0; // Keep active near top-third

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToActive());
        final currentChord = widget.controller.currentChord;
        final nextChord = widget.controller.nextChord;
        final allLyrics = widget.controller.lyrics;
        final currentLyricIndex = widget.controller.currentLyricIndex;

        return Column(
          children: [
            // ── Chord Section (conditional for mobile / compact) ───
            if (widget.showChordsHeader)
              _buildChordSection(currentChord, nextChord),

            // ── Lyrics Section ─────────────────────────────────────
            Expanded(
              child: allLyrics != null && allLyrics.isNotEmpty
                  ? _buildLyricsList(allLyrics, currentLyricIndex)
                  : _buildLyricsPlaceholder(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChordSection(currentChord, nextChord) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.3),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Column(
        children: [
          // Key and Capo banner
          HarmonicInfoBar(controller: widget.controller),
          const SizedBox(height: 4),

          Text(
            'CURRENT CHORD',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Main chord diagram
              ChordDiagram(chord: currentChord, size: 90),

              // Next chord preview (smaller, muted)
              if (nextChord != null) ...[
                const SizedBox(width: 24),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NEXT',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withValues(alpha: 0.25),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: 0.45,
                      child: ChordDiagram(chord: nextChord, size: 60),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsList(List<dynamic> lyrics, int currentIndex) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final lyric = lyrics[index];
        final isCurrent = index == currentIndex;
        final isPast = index < currentIndex;
        final currentChord = widget.controller.currentChord;

        // Find chords that belong to this lyric line
        final lineStart = lyric.timestamp as Duration;
        final lineEnd = index + 1 < lyrics.length
            ? (lyrics[index + 1].timestamp as Duration)
            : lineStart + const Duration(seconds: 4);
        final lineChords = widget.controller.chords?.where((c) =>
          c.timestamp >= lineStart && c.timestamp < lineEnd
        ).toList() ?? [];

        return InkWell(
          onTap: () => widget.controller.seek(lyric.timestamp),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFFF8C00).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isCurrent
                  ? Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.25), width: 1)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lineChords.isNotEmpty) ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: lineChords.map((c) {
                      final isActiveChord = isCurrent && c.chordName == currentChord?.chordName;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActiveChord ? const Color(0xFFFF8C00) : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isActiveChord ? const Color(0xFFFFB03B) : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text(
                          c.chordName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isActiveChord ? Colors.black : const Color(0xFFFF8C00),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                ],
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: isCurrent
                        ? widget.lyricFontSize
                        : widget.lyricFontSize * 0.82,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent
                        ? const Color(0xFFFFAA33)
                        : isPast
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                  child: Text(
                    lyric.text.isEmpty ? '♫' : lyric.text,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsPlaceholder() {
    final isLoading = widget.controller.isLoadingMetadata;
    final hasSong = widget.controller.currentSong != null;

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: const Color(0xFFFF8C00).withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading lyrics...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lyrics_rounded, size: 48, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Text(
            hasSong ? 'No lyrics found' : 'Play a song to see lyrics',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
