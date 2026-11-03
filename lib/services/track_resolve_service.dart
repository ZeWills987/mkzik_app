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

/// Le lien pointe vers une playlist (`kind: "playlist"`), pas vers un titre.
class ResolvePlaylist extends ResolveResult {
  final String platform; // 'soundcloud' | 'youtube'
  final String title;
  final String artist;
  final String thumbnail;
  final String sourceUrl; // forme unique du lien = identifiant fiable de l'import
  final String playlistId;
  final int trackCount;
  final bool truncated; // SoundCloud : plus de 500 titres, la liste est coupée
  /// SoundCloud uniquement (YouTube : vide, Symfony lit la playlist via le compte Google).
  /// Seule l'url de chaque titre est fiable : titre/artiste/cover sont vides.
  final List<Track> tracks;
  ResolvePlaylist({
    required this.platform,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.sourceUrl,
    required this.playlistId,
    required this.trackCount,
    required this.truncated,
    required this.tracks,
  });

  bool get isSoundcloud => platform == 'soundcloud';
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
    final res = await ApiClient.getUri(uri, auth: true, timeout: const Duration(seconds: 25));
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
        // Ancienne API : pas de `kind` → traité comme un titre.
        if (data['kind'] == 'playlist') {
          final url = (meta['source_url'] ?? meta['url'] ?? '').toString();
          final platform = data['platform']?.toString() ?? '';
          if (url.isNotEmpty && (platform == 'youtube' || tracks.isNotEmpty)) {
            return ResolvePlaylist(
              platform: platform,
              title: (meta['title'] ?? '').toString(),
              artist: (meta['artist'] ?? '').toString(),
              thumbnail: (meta['thumbnail'] ?? '').toString(),
              sourceUrl: url,
              playlistId: (meta['playlist_id'] ?? '').toString(),
              trackCount: (meta['track_count'] as num?)?.toInt() ?? tracks.length,
              truncated: meta['truncated'] == true,
              tracks: tracks,
            );
          }
        }
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
