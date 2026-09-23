import '../config/api_config.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Résultat de l'identification d'un titre depuis un lien partagé (TikTok…).
sealed class ResolveResult {}

class ResolveFound extends ResolveResult {
  final List<Track> tracks; // max 3, cf. contrat Python
  final String? metaTitle; // titre détecté dans la vidéo (metadata TikTok)
  final String? metaArtist;
  ResolveFound(this.tracks, {this.metaTitle, this.metaArtist});
}

/// Aucune musique identifiable dans la vidéo (son original, métadonnées absentes).
class ResolveNotFound extends ResolveResult {}

/// Erreur réseau / vidéo introuvable / lien expiré.
class ResolveError extends ResolveResult {
  final String message;
  ResolveError(this.message);
}

/// Identifie le(s) titre(s) associé(s) à un lien externe (TikTok, etc.) via
/// Python — utilisé par le flux "Partager vers Mkzik".
class TrackResolveService {
  /// `GET {PYTHON}track/resolve?url=`
  /// → { meta: {title, artist, duration}, results: [...], sources_checked: [...] }
  /// Chaque résultat a `source`: "mkzik" (déjà dans Mkzik, `id` présent) ou
  /// "ytm"/"sc" (externe, `url` présent) — normalisé vers le format [Track]
  /// ("mkzik" → source vide, comme pour toute track interne).
  static Future<ResolveResult> resolve(String sharedUrl) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}track/resolve')
        .replace(queryParameters: {'url': sharedUrl});
    final res = await ApiClient.getUri(uri, auth: false, timeout: const Duration(seconds: 25));
    switch (res) {
      case Ok(:final data):
        if (data is! Map) return ResolveNotFound();
        final meta = data['meta'] is Map ? data['meta'] as Map : const {};
        final list = data['results'] as List? ?? const [];
        final tracks = list.whereType<Map<String, dynamic>>().map((raw) {
          final m = Map<String, dynamic>.from(raw);
          if (m['source'] == 'mkzik') m['source'] = '';
          return Track.fromJson(m);
        }).toList();
        if (tracks.isEmpty) return ResolveNotFound();
        return ResolveFound(
          tracks,
          metaTitle: meta['title']?.toString(),
          metaArtist: meta['artist']?.toString(),
        );
      case Err(:final statusCode, :final message):
        if (statusCode == 404) return ResolveNotFound();
        return ResolveError(message);
    }
  }
}
