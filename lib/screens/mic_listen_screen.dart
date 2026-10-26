import 'package:flutter/material.dart';
import '../models/chord_event.dart';
import '../services/live_chord_detector.dart';
import '../services/mic_listener_service.dart';
import '../services/songsterr_service.dart';
import '../widgets/chord_diagram.dart';

/// "Shazam for chords": listens to music playing nearby and shows the chord
/// and the dominant note in real time.
class MicListenScreen extends StatefulWidget {
  const MicListenScreen({super.key});

  @override
  State<MicListenScreen> createState() => _MicListenScreenState();
}

class _MicListenScreenState extends State<MicListenScreen> {
  final MicListenerService _service = MicListenerService();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _service,
          builder: (context, _) {
            final d = _service.detection;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const Text('Écoute micro',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Lance l’écoute près d’une enceinte ou d’un instrument : l’accord et la note dominante s’affichent en direct.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Center(child: _buildToggle()),
                if (_service.error != null) ...[
                  const SizedBox(height: 12),
                  Text(_service.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                if (_service.listening) ...[
                  _buildLevel(d.level),
                  const SizedBox(height: 16),
                  _buildChordCard(d),
                  const SizedBox(height: 12),
                  _buildNoteCard(d),
                  if (_service.history.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildHistory(),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildToggle() {
    final on = _service.listening;
    return InkWell(
      onTap: on ? _service.stop : _service.start,
      customBorder: const CircleBorder(),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: on
                ? const [Color(0xFFFF4500), Color(0xFFB00020)]
                : const [Color(0xFFFF8C00), Color(0xFFFF4500)],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFF8C00).withValues(alpha: on ? 0.5 : 0.3), blurRadius: 24, spreadRadius: 2),
          ],
        ),
        child: Icon(on ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 44),
      ),
    );
  }

  Widget _buildLevel(double level) {
    final value = (level * 6).clamp(0.0, 1.0);
    return Row(
      children: [
        const Icon(Icons.graphic_eq_rounded, color: Color(0xFFFF8C00), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFF8C00)),
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration get _card => BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.25)),
      );

  Widget _buildChordCard(LiveDetection d) {
    final chord = d.chord;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Column(
        children: [
          const Text('ACCORD ENTENDU',
              style: TextStyle(color: Color(0xFFFF8C00), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (chord == null)
            Text(d.level < 0.003 ? 'Silence…' : 'Analyse…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 18))
          else ...[
            Text(chord,
                style: const TextStyle(color: Color(0xFFFFAA33), fontSize: 48, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ChordDiagram(
              chord: ChordEvent(
                timestamp: Duration.zero,
                chordName: chord,
                fretPositions: SongsterrService.standardChordPositions[chord],
              ),
              size: 120,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoteCard(LiveDetection d) {
    final note = d.note;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card,
      child: Column(
        children: [
          const Text('NOTE DOMINANTE',
              style: TextStyle(color: Color(0xFFFF8C00), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (note == null)
            Text('—', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 24))
          else ...[
            Text(note, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700)),
            Text(
              '${d.frequency!.toStringAsFixed(1)} Hz · ${d.cents >= 0 ? '+' : ''}${d.cents.round()} ¢',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 8),
            // Tuner-style gauge: centre = in tune.
            LayoutBuilder(builder: (context, c) {
              final x = (d.cents + 50) / 100 * c.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    Positioned(left: c.maxWidth / 2 - 1, top: 0, bottom: 0,
                        child: Container(width: 2, color: Colors.white38)),
                    Positioned(
                      left: (x - 7).clamp(0.0, c.maxWidth - 14),
                      top: 0,
                      child: Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: d.cents.abs() <= 8 ? Colors.greenAccent : const Color(0xFFFF8C00),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Derniers accords',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in _service.history)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(c, style: const TextStyle(color: Color(0xFFFFB03B), fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
    );
  }
}
