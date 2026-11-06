import '../models/track.dart';
import '../services/radio_service.dart';
import 'core/track_resolver.dart';

/// Choisit les titres de la radio : demande des suggestions pour un titre,
/// écarte les doublons et prépare ce qui peut l'être pour la file.
/// Ne touche ni à la file ni au lecteur : il renvoie juste la liste à ajouter.
class RadioPicker {
  RadioPicker({required Future<List<Track>> Function(Track seed) suggestions, required TrackResolver resolver})
      : _suggestions = suggestions,
        _resolver = resolver;

  final Future<List<Track>> Function(Track seed) _suggestions;
  final TrackResolver _resolver;

  /// Suggestions à ajouter À LA SUITE de la liste [existing] (autoplay en fin de
  /// file) : au plus [limit] titres, sans doublon avec ce qui y est déjà.
  Future<List<Track>> toAppend(
    Track seed, {
    required Iterable<Track> existing,
    required bool Function() isStale,
    int limit = 10,
  }) =>
      _pick(seed, seen: {for (final t in existing) RadioService.dedupKey(t)}, limit: limit, isStale: isStale);

  /// Suggestions qui REMPLACENT la suite de [seed] (mode radio à la demande) :
  /// au plus [limit] titres, sans doublon avec [seed] lui-même.
  Future<List<Track>> toReplaceUpcoming(Track seed, {required bool Function() isStale, int limit = 20}) =>
      _pick(seed, seen: {RadioService.dedupKey(seed)}, limit: limit, isStale: isStale);

  Future<List<Track>> _pick(
    Track seed, {
    required Set<String> seen,
    required int limit,
    required bool Function() isStale,
  }) async {
    final suggestions = await _suggestions(seed);
    if (isStale()) return const [];
    final fresh = <Track>[for (final t in suggestions) if (seen.add(RadioService.dedupKey(t))) t];
    if (fresh.isEmpty) return const [];
    return _prepare(fresh.take(limit), isStale);
  }

  /// Les titres externes (`needsStream`, quasi toutes les suggestions) n'ont pas
  /// d'URL : ils restent dans la file tels quels et sont résolus via `/stream`
  /// quand ils deviennent le titre courant. Les autres sont signés ; ceux qui
  /// échouent sont écartés.
  Future<List<Track>> _prepare(Iterable<Track> tracks, bool Function() isStale) async {
    final out = <Track>[];
    for (final t in tracks) {
      final r = await _resolver.resolveForQueue(t);
      if (isStale()) return const [];
      if (r != null && r.audioUrl.isNotEmpty) {
        out.add(r);
      } else if (t.needsStream && t.pageUrl.isNotEmpty) {
        out.add(t);
      }
    }
    return out;
  }
}
