import 'package:flutter/material.dart';
import '../controllers/music_player_controller.dart';
import 'chord_diagram.dart';
import 'harmonic_info_bar.dart';

/// Fixed mobile playing reference. Only the lyrics scroll, never capo or key.
class MobileChordPanel extends StatelessWidget {
  final MusicPlayerController controller;
  const MobileChordPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF141418),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        HarmonicInfoBar(controller: controller, compact: true),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ACTUEL', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 11)),
            ChordDiagram(chord: controller.currentChord, size: 88),
          ])),
          Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('SUIVANT', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 11)),
            ChordDiagram(chord: controller.nextChord, size: 80),
          ])),
          PopupMenuButton<String>(
            tooltip: 'Voir la position de chaque accord',
            icon: const Icon(Icons.grid_view_rounded, color: Colors.amber),
            enabled: controller.uniqueSongChords.isNotEmpty,
            itemBuilder: (_) => controller.uniqueSongChords.map((name) =>
                PopupMenuItem(value: name, child: Text(name))).toList(),
            onSelected: (name) => showDialog<void>(context: context, builder: (context) => AlertDialog(
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                ChordDiagram(chord: controller.getChordDetails(name), size: 140),
              ]),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
            )),
          ),
        ]),
      ]),
    );
  }
}
