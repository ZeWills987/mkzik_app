import '../config/api_config.dart';
import '../models/lyrics.dart';
import 'api_client.dart';

/// Paroles d'une track (texte complet, à la demande).
/// `GET api/tracks/{id}/lyrics` → { lyrics, lyrics_synced, lyrics_lines }
class LyricsService {
  static Future<Lyrics?> fetch(int trackId) async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/tracks/$trackId/lyrics'),
      auth: false,
    );
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }
}
