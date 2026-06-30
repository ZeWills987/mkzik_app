import '../config/api_config.dart';
import '../models/yt_playlist.dart';
import 'api_client.dart';

class YoutubeService {
  /// Vérifie si l'utilisateur a un token Google stocké côté serveur.
  /// Route corrigée : GET /api/user/google-token (pas /api/api/…)
  static Future<bool> isConnected() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/user/google-token'),
    );
    final data = res.orElse(null);
    if (data is! Map) return false;
    return data['connected'] == true || data['token'] != null;
  }

  /// GET /api/youtube/connect → URL de consentement Google (scope youtube.readonly).
  static Future<String?> connectUrl() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/youtube/connect'),
    );
    final data = res.orElse(null);
    if (data is Map) return data['url']?.toString();
    return null;
  }

  /// GET /api/youtube/playlists → playlists YT de l'utilisateur.
  static Future<List<YtPlaylist>> playlists() async {
    final res = await ApiClient.getUri(
      Uri.parse('${ApiConfig.baseUrl}api/youtube/playlists'),
      timeout: const Duration(seconds: 30),
    );
    final data = res.orElse(null);
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(YtPlaylist.fromJson).toList();
  }

  /// POST /api/youtube/import/playlist/{id} → importe une playlist YT dans Mkzik.
  static Future<ApiResult<dynamic>> importPlaylist(String playlistId) =>
      ApiClient.postUri(
        Uri.parse('${ApiConfig.baseUrl}api/youtube/import/playlist/$playlistId'),
      );

  /// POST /api/youtube/import/likes → importe les likes YT comme favoris Mkzik.
  static Future<ApiResult<dynamic>> importLikes() =>
      ApiClient.postUri(
        Uri.parse('${ApiConfig.baseUrl}api/youtube/import/likes'),
      );
}
