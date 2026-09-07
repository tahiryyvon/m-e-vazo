/// Represente un accord de guitare synchronise dans le temps
class ChordEvent {
  final Duration timestamp;
  final String chordName;      // Ex: "C", "G7", "Am", "F#m7"
  final int? durationMs;       // Duree de l'accord en millisecondes
  final List<int>? fretPositions;  // Positions des doigts: [corde6, corde5, corde4, corde3, corde2, corde1]
  final int? barreFret;        // Case de barre si applicable
  final List<int>? barreStrings;  // Cordes couvertes par le barre
  final int? lyricLineIndex;   // Indice de la ligne de paroles correspondante

  ChordEvent({
    required this.timestamp,
    required this.chordName,
    this.durationMs,
    this.fretPositions,
    this.barreFret,
    this.barreStrings,
    this.lyricLineIndex,
  });

  /// Verifie si l'accord est valide (a des positions de frettes)
  bool get hasDiagram => fretPositions != null && fretPositions!.length == 6;

  /// Retourne le nom de l'accord formate
  String get displayName => chordName;

  @override
  String toString() => 'ChordEvent[${timestamp.inSeconds}s] $chordName';
}

/// Contient la liste des accords ainsi que les metadonnees harmoniques (Capo, Tonality, Tuning)
class SongChordsResult {
  final List<ChordEvent> chords;
  final String? musicalKey;
  final int? capo;
  final String? tuning;

  SongChordsResult({
    required this.chords,
    this.musicalKey,
    this.capo,
    this.tuning,
  });
}
