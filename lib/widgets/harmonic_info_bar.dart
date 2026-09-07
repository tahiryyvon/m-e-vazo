import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import '../models/chord_event.dart';
import '../services/songsterr_service.dart';
import 'chord_diagram.dart';

/// Clean, high-contrast banner displaying:
/// 1. Key, Capo, and Sync Offset
/// 2. Complete list of all chords in the song with active chord highlighting & diagram preview
class HarmonicInfoBar extends StatelessWidget {
  final MusicPlayerController controller;

  const HarmonicInfoBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final key = controller.musicalKey;
    final capo = controller.capo;
    final hasCapo = capo != null && capo > 0;
    final offsetSec = controller.chordOffsetMs / 1000.0;
    final allChords = controller.uniqueSongChords;
    final currentChordName = controller.currentChord?.chordName;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top Row: Key, Capo, Sync ──────────────────────
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Key Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note_rounded, size: 14, color: Color(0xFFFF8C00)),
                    const SizedBox(width: 4),
                    Text(
                      'KEY: ${key != null && key.isNotEmpty ? key : 'Standard'}',
                      style: const TextStyle(
                        color: Color(0xFFFFB347),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              // Capo Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: hasCapo
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasCapo
                        ? const Color(0xFF00E676).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: hasCapo ? const Color(0xFF00E676) : Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasCapo ? 'CAPO: Fret $capo' : 'CAPO: None',
                      style: TextStyle(
                        color: hasCapo ? const Color(0xFF69F0AE) : Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              // Sync Offset Calibration
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => controller.adjustChordOffset(-100),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                        child: Icon(Icons.remove_rounded, size: 14, color: Colors.white70),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        'SYNC: ${offsetSec >= 0 ? '+' : ''}${offsetSec.toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => controller.adjustChordOffset(100),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                        child: Icon(Icons.add_rounded, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Bottom Row: All Chords in the Song ─────────────
          if (allChords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CHORDS:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.4),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 5,
                      runSpacing: 4,
                      children: allChords.map((chord) {
                        final isActive = chord == currentChordName;
                        return InkWell(
                          onTap: () => _showChordPreview(context, chord),
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFFF8C00)
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isActive
                                    ? Colors.amberAccent
                                    : Colors.white.withValues(alpha: 0.15),
                                width: isActive ? 1.5 : 1.0,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              chord,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                                color: isActive ? Colors.black : Colors.white.withValues(alpha: 0.9),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showChordPreview(BuildContext context, String chordName) {
    final chordEvent = controller.getChordDetails(chordName) ??
        ChordEvent(
          timestamp: Duration.zero,
          chordName: chordName,
          fretPositions: SongsterrService.standardChordPositions[chordName],
        );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chordName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF8C00),
                ),
              ),
              const SizedBox(height: 16),
              ChordDiagram(chord: chordEvent, size: 140),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('FERMER', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
