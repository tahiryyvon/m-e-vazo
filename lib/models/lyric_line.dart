
/// Represente une ligne de paroles synchronisee au format LRC
/// Format: [mm:ss.xx] Texte de la ligne
class LyricLine {
  final Duration timestamp;
  final String text;
  final bool isEmpty;

  LyricLine({
    required this.timestamp,
    required this.text,
    this.isEmpty = false,
  });

  /// Parse une ligne au format LRC: [mm:ss.xx] ou [mm:ss.xxx]
  factory LyricLine.fromLrc(String line) {
    line = line.trim();
    if (line.isEmpty) {
      return LyricLine(
        timestamp: Duration.zero,
        text: '',
        isEmpty: true,
      );
    }

    // Supporte [mm:ss.xx] et [mm:ss.xxx]
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)');
    final match = regex.firstMatch(line);

    if (match != null) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fractionStr = match.group(3)!;
      final fraction = fractionStr.length == 2 
          ? int.parse(fractionStr) * 10  // centisecondes -> millisecondes
          : int.parse(fractionStr);       // millisecondes directes
      final text = match.group(4) ?? '';

      return LyricLine(
        timestamp: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: fraction,
        ),
        text: text.trim(),
      );
    }

    // Si le format n'est pas reconnu, retourner une ligne vide
    return LyricLine(
      timestamp: Duration.zero,
      text: line,
      isEmpty: true,
    );
  }

  /// Parse tout le contenu LRC en liste de LyricLine
  static List<LyricLine> parseLrcContent(String content) {
    return content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => LyricLine.fromLrc(line))
        .where((line) => !line.isEmpty)
        .toList();
  }

  @override
  String toString() => 'LyricLine[${timestamp.inMinutes}:${(timestamp.inSeconds % 60).toString().padLeft(2, '0')}] $text';
}
