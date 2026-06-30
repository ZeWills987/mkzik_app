import '../config/api_config.dart';
import '../models/lyrics.dart';
import 'api_client.dart';

/// Paroles d'une track (texte complet, à la demande).
/// Deux routes selon si la track est intégrée (apiId) ou en flux direct (pageUrl) :
///   `GET api/tracks/{id}/lyrics`    → paroles depuis la BD Symfony
///   `GET {pythonUrl}lyrics?url=<u>` → paroles résolues depuis le cache stream yt-dlp
///
/// Note : la sonde `X-Has-Lyrics` via `Range: bytes=0-0` sur /stream a été
/// supprimée — elle ouvrait une connexion concurrente sur le même flux yt-dlp
/// et pouvait provoquer un saut prématuré vers la piste suivante.
/// Le bouton Paroles est affiché de façon optimiste pour tous les flux externes ;
/// l'endpoint `/lyrics?url=` retourne `found: false` si aucune parole n'existe.
class LyricsService {
  static Future<Lyrics?> fetch(int trackId) async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/tracks/$trackId/lyrics'),
      auth: false,
    );
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }

  /// Paroles d'un flux direct. [artist]/[title] sont optionnels mais recommandés :
  /// la résolution est plus rapide et fiable que via l'URL seule.
  static Future<Lyrics?> fetchByUrl(String pageUrl, {String? artist, String? title}) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}lyrics').replace(queryParameters: {
      'url': pageUrl,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
      if (title != null && title.isNotEmpty) 'title': title,
    });
    final res = await ApiClient.getUri(uri, auth: false);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }
}
