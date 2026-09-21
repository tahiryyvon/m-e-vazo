import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import '../models/chord_event.dart';
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
  // One GlobalKey per lyric line — allows Scrollable.ensureVisible to find
  // the exact render position and scroll it precisely to the centre.
  final List<GlobalKey> _lyricKeys = [];

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
    if (idx >= _lyricKeys.length) return;

    _lastScrolledIndex = idx;

    final key = _lyricKeys[idx];
    final ctx = key.currentContext;
    if (ctx == null) return;

    // alignment: 0.5 places the active line at the vertical centre of the viewport
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 420),
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
            // ── Lyrics Section ─────────────────────────────────────
            Expanded(
              child: allLyrics != null && allLyrics.isNotEmpty
                  ? _buildLyricsList(allLyrics, currentLyricIndex)
                  : _buildLyricsPlaceholder(),
            ),

            // ── Bottom Chords Viewer (Only when showChordsHeader is enabled, e.g. mobile) ────
            if (widget.showChordsHeader)
              _buildBottomChordsViewer(currentChord, nextChord, allLyrics, currentLyricIndex),
          ],
        );
      },
    );
  }

  Widget _buildBottomChordsViewer(
    ChordEvent? currentChord,
    ChordEvent? nextChord,
    List<dynamic>? allLyrics,
    int currentLyricIndex,
  ) {
    // Find chords for the active lyric line
    List<ChordEvent> displayChords = [];
    if (allLyrics != null &&
        currentLyricIndex >= 0 &&
        currentLyricIndex < allLyrics.length) {
      final lineStart = allLyrics[currentLyricIndex].timestamp as Duration;
      final lineEnd = currentLyricIndex + 1 < allLyrics.length
          ? (allLyrics[currentLyricIndex + 1].timestamp as Duration)
          : lineStart + const Duration(seconds: 4);
      displayChords = widget.controller.chords?.where((c) =>
        c.timestamp >= lineStart && c.timestamp < lineEnd
      ).toList() ?? [];
    }

    // Fallback: if current line has no specific chords, show currentChord & nextChord
    if (displayChords.isEmpty) {
      if (currentChord != null) displayChords.add(currentChord);
      if (nextChord != null && nextChord.chordName != currentChord?.chordName) {
        displayChords.add(nextChord);
      }
    }

    final hasChords = displayChords.isNotEmpty || currentChord != null;
    if (!hasChords && !widget.showChordsHeader) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF141418).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: widget.showChordsHeader ? 8 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row with Line Chords / Active chords
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note_rounded, size: 14, color: Color(0xFFFF8C00)),
                    const SizedBox(width: 4),
                    Text(
                      'ACCORDS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: displayChords.map((c) {
                      final isActive = c.chordName == currentChord?.chordName;
                      return _buildChordPill(c, isActive);
                    }).toList(),
                  ),
                ),
              ),
              if (!widget.showChordsHeader && widget.controller.musicalKey != null) ...[
                const SizedBox(width: 6),
                HarmonicInfoBar(controller: widget.controller),
              ],
            ],
          ),

          // In mobile mode with diagrams enabled: display compact diagrams below the chips
          if (widget.showChordsHeader && currentChord != null) ...[
            const SizedBox(height: 6),
            HarmonicInfoBar(controller: widget.controller),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ChordDiagram(chord: currentChord, size: 75),
                if (nextChord != null) ...[
                  const SizedBox(width: 20),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SUIVANT',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.white.withValues(alpha: 0.3),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Opacity(
                        opacity: 0.45,
                        child: ChordDiagram(chord: nextChord, size: 52),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChordPill(ChordEvent chord, bool isActive) {
    return GestureDetector(
      onTap: () => widget.controller.seek(chord.timestamp),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFF8C00)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFFB03B)
                : Colors.white.withValues(alpha: 0.15),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          chord.chordName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: isActive ? Colors.black : const Color(0xFFFFB03B),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsList(List<dynamic> lyrics, int currentIndex) {
    // Rebuild key list when lyrics change size
    if (_lyricKeys.length != lyrics.length) {
      _lyricKeys.clear();
      for (int i = 0; i < lyrics.length; i++) {
        _lyricKeys.add(GlobalKey());
      }
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final lyric = lyrics[index];
        final isCurrent = index == currentIndex;
        final isPast = index < currentIndex;

        return InkWell(
          key: _lyricKeys[index],
          onTap: () => widget.controller.seek(lyric.timestamp),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFFF8C00).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isCurrent
                  ? Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.25), width: 1)
                  : null,
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: isCurrent
                      ? widget.lyricFontSize
                      : widget.lyricFontSize * 0.84,
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
