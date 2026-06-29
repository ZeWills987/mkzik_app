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

/// Paroles complètes d'une track. Deux backends, deux formats tolérés :
///   • Symfony  `GET api/tracks/{id}/lyrics` → { lyrics, lyrics_synced, lyrics_lines }
///   • Python   `GET {pythonUrl}lyrics?url=` → { found, synced, source, lyrics, lines }
/// [synced] vrai → [lines] exploitable (karaoké) ; sinon on affiche [text] brut.
class Lyrics {
  final String text;
  final bool synced;
  final List<LyricLine> lines;

  const Lyrics({required this.text, required this.synced, this.lines = const []});

  bool get isEmpty => text.trim().isEmpty && lines.isEmpty;
  bool get hasSyncedLines => synced && lines.isNotEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> j) {
    // Python renvoie `found: false` quand rien n'est trouvé → paroles vides.
    if (j['found'] == false) return const Lyrics(text: '', synced: false);
    // Clés selon le backend : `lines`/`synced` (Python) ou `lyrics_lines`/`lyrics_synced` (Symfony).
    final rawLines = j['lines'] ?? j['lyrics_lines'];
    return Lyrics(
      text: (j['lyrics'] ?? '').toString(),
      synced: j['synced'] == true || j['lyrics_synced'] == true,
      lines: rawLines is List
          ? rawLines.whereType<Map<String, dynamic>>().map(LyricLine.fromJson).toList()
          : const [],
    );
  }
}
