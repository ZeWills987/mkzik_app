import '../config/api_config.dart';
import '../models/lyrics.dart';
import 'api_client.dart';

/// Paroles d'une track (texte complet, à la demande).
/// Deux routes selon si la track est intégrée (apiId) ou en flux direct (pageUrl) :
///   `GET api/tracks/{id}/lyrics`    → paroles depuis la BD Symfony
///   `GET {pythonUrl}lyrics?url=<u>` → paroles résolues depuis le cache stream yt-dlp
class LyricsService {
  static Future<Lyrics?> fetch(int trackId) async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/tracks/$trackId/lyrics'),
      auth: false,
    );
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }

  static Future<Lyrics?> fetchByUrl(String pageUrl) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}lyrics')
        .replace(queryParameters: {'url': pageUrl});
    final res = await ApiClient.getUri(uri, auth: false);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }
}
