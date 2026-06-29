import '../models/track.dart';
import '../utils/logger.dart';
import 'track_service.dart';
import 'suggestion_service.dart';

/// Logique « métier » du mode radio : choisir les titres du même mood à partir
/// d'un titre seed. Ne touche PAS au moteur audio — renvoie juste des [Track].
/// L'insertion dans la file native reste la responsabilité du player.
class RadioService {
  /// Clé de déduplication d'un titre : url de page si dispo, sinon id.
  static String dedupKey(Track t) => t.pageUrl.isNotEmpty ? t.pageUrl : t.id;

  /// Récupère les suggestions pour le titre [seed] :
  /// - externe non intégré → `related` sur sa plateforme d'origine (url connue) ;
  /// - interne / déjà intégré (pas d'url externe) → on cherche une url YT+SC par
  ///   titre+artiste, puis `related` sur chacune (mix).
  static Future<List<Track>> suggestionsFor(Track seed) async {
    if (seed.needsImport && seed.pageUrl.isNotEmpty) {
      switch (seed.extPlatform) {
        case ExtPlatform.youtubeMusic:
          return SuggestionService.youtubeRelated(seed.pageUrl);
        case ExtPlatform.soundcloud:
          return SuggestionService.soundcloudRelated(seed.pageUrl);
        case ExtPlatform.other:
          break;
      }
    }
    // Interne / intégré : recherche d'une url de référence sur chaque plateforme.
    final q = '${seed.title} ${seed.artist}'.trim();
    if (q.isEmpty) return const [];
    final seeds = await _searchSeedUrls(q);
    final out = <Track>[];
    if (seeds.yt != null) out.addAll(await SuggestionService.youtubeRelated(seeds.yt!));
    if (seeds.sc != null) out.addAll(await SuggestionService.soundcloudRelated(seeds.sc!));
    return out;
  }

  /// Cherche (recherche externe SSE) une 1ʳᵉ url YouTube et une 1ʳᵉ url SoundCloud
  /// correspondant à [query]. S'arrête dès que les deux sont trouvées ou à `done`.
  static Future<({String? yt, String? sc})> _searchSeedUrls(String query) async {
    String? yt, sc;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    try {
      await for (final ev in TrackService.searchExternalStream(query)) {
        for (final t in ev.tracks) {
          if (t.pageUrl.isEmpty) continue;
          if (yt == null && t.extPlatform == ExtPlatform.youtubeMusic) yt = t.pageUrl;
          if (sc == null && t.extPlatform == ExtPlatform.soundcloud) sc = t.pageUrl;
        }
        if ((yt != null && sc != null) || ev.done || DateTime.now().isAfter(deadline)) break;
      }
    } catch (e) {
      mkLog('Mkzik 📻 radio seed search erreur : $e');
    }
    return (yt: yt, sc: sc);
  }
}
