import 'package:google_sign_in/google_sign_in.dart';
import '../config/api_config.dart';
import '../models/yt_playlist.dart';
import 'api_client.dart';

/// Levée quand l'API YouTube retourne 403 + needs_reconnect: true.
/// Le token YouTube a expiré → relancer [YoutubeService.connect].
class YoutubeNeedsReconnectException implements Exception {
  const YoutubeNeedsReconnectException();
}

final _googleSignIn = GoogleSignIn(
  scopes: ['https://www.googleapis.com/auth/youtube.readonly'],
);

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

  /// Connecte YouTube via SDK Google Sign-In :
  /// 1. `googleSignIn.signIn()` → accessToken + serverAuthCode
  /// 2. `POST /api/youtube/token` {access_token, refresh_token, expires_in}
  /// → {status: "connected"}
  ///
  /// Retourne `false` si l'utilisateur annule le sélecteur de compte.
  static Future<bool> connect() async {
    await _googleSignIn.signOut(); // force la sélection de compte
    final account = await _googleSignIn.signIn();
    if (account == null) return false;

    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) throw Exception('Token Google introuvable');

    final body = <String, dynamic>{
      'access_token': accessToken,
      'expires_in': 3600,
      if (account.serverAuthCode != null) 'refresh_token': account.serverAuthCode,
    };

    final res = await ApiClient.postUri(
      Uri.parse('${ApiConfig.baseUrl}api/youtube/token'),
      body: body,
    );

    switch (res) {
      case Ok():
        return true;
      case Err(:final message):
        throw Exception(message);
    }
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
