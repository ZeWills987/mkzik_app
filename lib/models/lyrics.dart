/// Une ligne de paroles synchronisée : [timeMs] = moment d'apparition (ms).
class LyricLine {
  final int timeMs;
  final String text;
  const LyricLine({required this.timeMs, required this.text});

  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(
        timeMs: (j['time'] as num?)?.toInt() ?? 0,
        text: (j['text'] ?? '').toString(),
      );
}

/// Paroles complètes d'une track (`GET /api/tracks/{id}/lyrics`).
/// [synced] vrai → [lines] exploitable (karaoké) ; sinon on affiche [text] brut.
class Lyrics {
  final String text;
  final bool synced;
  final List<LyricLine> lines;

  const Lyrics({required this.text, required this.synced, this.lines = const []});

  bool get isEmpty => text.trim().isEmpty && lines.isEmpty;
  bool get hasSyncedLines => synced && lines.isNotEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> j) {
    final rawLines = j['lyrics_lines'];
    return Lyrics(
      text: (j['lyrics'] ?? '').toString(),
      synced: j['lyrics_synced'] == true,
      lines: rawLines is List
          ? rawLines.whereType<Map<String, dynamic>>().map(LyricLine.fromJson).toList()
          : const [],
    );
  }
}
