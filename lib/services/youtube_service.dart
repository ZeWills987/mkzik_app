import '../config/api_config.dart';
import '../models/yt_playlist.dart';
import 'api_client.dart';

/// Levée quand l'API YouTube retourne 403 + needs_reconnect: true.
/// Le token YouTube a expiré → relancer le flow GET /api/youtube/connect.
class YoutubeNeedsReconnectException implements Exception {
  const YoutubeNeedsReconnectException();
}

class YoutubeService {
  /// Vérifie si l'utilisateur a un token Google stocké côté serveur.
  /// GET /api/user/google-token → {google_access_token: "ya29.xxx"}
  static Future<bool> isConnected() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/user/google-token'),
    );
    final data = res.orElse(null);
    if (data is! Map) return false;
    final token = data['google_access_token'];
    return token != null && token.toString().isNotEmpty;
  }

  /// GET /api/youtube/connect → {url: "https://accounts.google.com/..."}
  static Future<String?> connectUrl() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/youtube/connect'),
    );
    final data = res.orElse(null);
    if (data is Map) return data['url']?.toString();
    return null;
  }

  /// GET /api/youtube/playlists → {playlists: [{id, title, item_count, thumbnail}]}
  /// Lève [YoutubeNeedsReconnectException] sur 403 (token YouTube expiré).
  static Future<List<YtPlaylist>> playlists() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/youtube/playlists'),
      timeout: const Duration(seconds: 30),
    );
    switch (res) {
      case Ok(:final data):
        if (data is! Map) return const [];
        final list = data['playlists'];
        if (list is! List) return const [];
        return list.whereType<Map<String, dynamic>>().map(YtPlaylist.fromJson).toList();
      case Err(:final statusCode):
        if (statusCode == 403) throw const YoutubeNeedsReconnectException();
        return const [];
    }
  }

  /// POST /api/youtube/import/playlist/{id}
  /// → {playlist, total, matched, not_found:[]}
  static Future<ApiResult<dynamic>> importPlaylist(String playlistId) =>
      ApiClient.postUri(
        Uri.parse('${ApiConfig.baseUrl}api/youtube/import/playlist/$playlistId'),
      );

  /// POST /api/youtube/import/likes
  /// → {total, matched, not_found:[]}
  static Future<ApiResult<dynamic>> importLikes() =>
      ApiClient.postUri(
        Uri.parse('${ApiConfig.baseUrl}api/youtube/import/likes'),
      );
}
