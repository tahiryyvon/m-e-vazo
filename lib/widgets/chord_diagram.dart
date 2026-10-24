import 'package:flutter/material.dart';
import '../models/chord_event.dart';
import '../models/chord_barre.dart';
import '../services/songsterr_service.dart';

/// Widget displaying a guitar chord diagram with 6 strings and fret markers.
/// Changes immediately at the audio timestamp, without overlapping diagrams.
class ChordDiagram extends StatelessWidget {
  final ChordEvent? chord;
  final double size;

  const ChordDiagram({
    super.key,
    this.chord,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return chord == null
          ? _buildPlaceholder(key: const ValueKey('placeholder'))
          : _buildDiagram(chord!, key: ValueKey(chord!.chordName));
  }

  Widget _buildPlaceholder({Key? key}) {
    return SizedBox(
      key: key,
      width: size,
      height: size * 1.4,
      child: Center(
        child: Text(
          '—',
          style: TextStyle(fontSize: size * 0.2, color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildDiagram(ChordEvent chord, {Key? key}) {
    final positions = chord.fretPositions ??
        SongsterrService.getStandardChordPositions()[chord.chordName];
    final barre = ChordBarre.resolve(chord, positions);

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chord name
        Text(
          chord.chordName,
          style: TextStyle(
            fontSize: size * 0.22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFFF8C00),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        if (barre != null)
          Text('Barré · case ${barre.fret}',
              style: TextStyle(fontSize: size * 0.09, color: Colors.amberAccent)),

        // Fretboard diagram
        Container(
          width: size,
          height: size * 1.1,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.08),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: CustomPaint(
            size: Size(size - 16, size * 1.1 - 18),
            painter: _ChordDiagramPainter(positions: positions, barre: barre),
          ),
        ),
      ],
    );
  }
}

class _ChordDiagramPainter extends CustomPainter {
  final List<int>? positions;
  final ChordBarre? barre;

  static const int _fretCount = 5;
  static const int _stringCount = 6;

  _ChordDiagramPainter({this.positions, this.barre});

  @override
  void paint(Canvas canvas, Size size) {
    if (positions == null || positions!.length != _stringCount) {
      _drawEmptyGrid(canvas, size);
      return;
    }

    final stringSpacing = size.width / (_stringCount - 1);
    final fretSpacing = (size.height - 20) / _fretCount;

    // Determine starting fret
    final frettedPositions = positions!.where((p) => p > 0);
    int minFret = frettedPositions.isEmpty ? 1 : frettedPositions.reduce((a, b) => a < b ? a : b);
    final startFret = minFret > 1 ? minFret - 1 : 1;
    final showFretNumber = startFret > 1;

    const topOffset = 16.0; // Space for X/O markers

    if (barre != null) {
      final row = barre!.fret - startFret;
      if (row >= 0 && row < _fretCount) {
        final left = barre!.firstString * stringSpacing;
        final right = barre!.lastString * stringSpacing;
        final top = topOffset + row * fretSpacing;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(left - 3, top, right + 3, top + fretSpacing),
              const Radius.circular(4)),
          Paint()..color = Colors.amber.withValues(alpha: 0.25),
        );
        canvas.drawLine(Offset(left, top + fretSpacing / 2),
            Offset(right, top + fretSpacing / 2),
            Paint()..color = Colors.amberAccent
              ..strokeWidth = (fretSpacing * 0.5).clamp(4.0, 10.0)
              ..strokeCap = StrokeCap.round);
      }
    }

    // Draw strings (vertical)
    for (int i = 0; i < _stringCount; i++) {
      final x = i * stringSpacing;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25 + i * 0.04)
        ..strokeWidth = i < 2 ? 1.8 : 1.2;
      canvas.drawLine(
        Offset(x, topOffset),
        Offset(x, topOffset + _fretCount * fretSpacing),
        paint,
      );
    }

    // Draw nut / frets (horizontal)
    for (int f = 0; f <= _fretCount; f++) {
      final y = topOffset + f * fretSpacing;
      final isNut = f == 0 && !showFretNumber;
      final paint = Paint()
        ..color = isNut ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = isNut ? 3.0 : 1.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw fret number if needed
    if (showFretNumber) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$startFret',
          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width - 4, topOffset + fretSpacing * 0.3));
    }

    // Draw finger markers, mutes, and open strings
    for (int s = 0; s < _stringCount; s++) {
      final fret = positions![s];
      final x = s * stringSpacing;

      if (fret == -1) {
        // Muted string — X
        _drawX(canvas, Offset(x, topOffset * 0.5), 5);
      } else if (fret == 0) {
        // Open string — O
        _drawO(canvas, Offset(x, topOffset * 0.5), 5);
      } else {
        // Finger position
        final relativeFret = fret - startFret + 1;
        if (relativeFret >= 1 && relativeFret <= _fretCount) {
          final y = topOffset + (relativeFret - 0.5) * fretSpacing;
          _drawFinger(canvas, Offset(x, y), 8);
        }
      }
    }
  }

  void _drawFinger(Canvas canvas, Offset center, double radius) {
    // Outer glow
    canvas.drawCircle(
      center,
      radius + 2,
      Paint()..color = const Color(0xFFFF8C00).withValues(alpha: 0.2),
    );
    // Filled dot
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFFF8C00),
    );
  }

  void _drawX(Canvas canvas, Offset center, double halfSize) {
    final paint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - halfSize, center.dy - halfSize),
        Offset(center.dx + halfSize, center.dy + halfSize), paint);
    canvas.drawLine(Offset(center.dx + halfSize, center.dy - halfSize),
        Offset(center.dx - halfSize, center.dy + halfSize), paint);
  }

  void _drawO(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.7)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawEmptyGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(4, 4, size.width - 8, size.height - 8), paint);
  }

  @override
  bool shouldRepaint(covariant _ChordDiagramPainter old) =>
      old.positions != positions || old.barre != barre;
}
