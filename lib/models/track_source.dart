import 'track.dart';

/// Une source (original) d'un track dérivé — issue de `GET /api/tracks/{id}/sources`.
class TrackSource {
  final double coverage; // part du dérivé venant de cette source (0..1)
  final double origCoverage; // part de la source réutilisée (0..1)
  final double? melodySim; // similarité mélodique (mashup)
  final String? subtype; // classification de cette relation (remix/edit…)
  final Track track; // l'original (pour lien + affichage)

  const TrackSource({
    required this.coverage,
    required this.origCoverage,
    this.melodySim,
    this.subtype,
    required this.track,
  });

  factory TrackSource.fromJson(Map<String, dynamic> j) => TrackSource(
        coverage: (j['coverage'] as num?)?.toDouble() ?? 0,
        origCoverage: (j['orig_coverage'] as num?)?.toDouble() ?? 0,
        melodySim: (j['melody_sim'] as num?)?.toDouble(),
        subtype: j['subtype']?.toString(),
        track: Track.fromJson(j['track'] is Map<String, dynamic>
            ? j['track'] as Map<String, dynamic>
            : <String, dynamic>{}),
      );

  /// Pourcentage de reprise affichable (max des deux couvertures), ex. "95 %".
  String get coverageLabel {
    final pct = (coverage > origCoverage ? coverage : origCoverage) * 100;
    return '${pct.round()} %';
  }
}
