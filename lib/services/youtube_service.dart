import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/yt_playlist.dart';
import 'api_client.dart';

/// Clé SharedPreferences : posée après une connexion OAuth v2 (disconnect+consent).
/// Absente = compte connecté avant la migration → bandeau de reconnexion affiché.
const _kOauthV2Key = 'yt_oauth_v2';

/// Levée quand l'API YouTube retourne 403 + needs_reconnect: true.
/// Le token YouTube a expiré → relancer [YoutubeService.connect].
class YoutubeNeedsReconnectException implements Exception {
  const YoutubeNeedsReconnectException();
}

final _googleSignIn = GoogleSignIn(
  scopes: ['https://www.googleapis.com/auth/youtube.readonly'],
  serverClientId: '209129894628-l1es9tbodhdiqq3nft1ac8kl3mjfie5l.apps.googleusercontent.com',
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
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw Exception('Connexion YouTube disponible uniquement sur mobile pour le moment.');
    }
    // disconnect() révoque l'accès → Google redemande le consentement complet
    // (prompt=consent implicite), ce qui émet un nouveau refresh_token avec
    // tous les scopes — nécessaire pour migrer les anciens comptes youtube.readonly.
    await _googleSignIn.disconnect().catchError((_) async => null);
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kOauthV2Key, true);
        return true;
      case Err(:final message):
        throw Exception(message);
    }
  }

  /// `true` si la connexion a été faite avec OAuth v2 (consent complet).
  /// `false` = ancien compte → bandeau de reconnexion à afficher.
  static Future<bool> isOauthV2() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOauthV2Key) ?? false;
  }

  /// Pose le flag OAuth v2 après une reconnexion web réussie.
  static Future<void> markOauthV2() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOauthV2Key, true);
  }

  /// Appelle `GET /api/youtube/connect` (JWT requis) → URL d'autorisation Google
  /// avec prompt=consent déjà inclus. À ouvrir dans un navigateur externe.
  static Future<String?> fetchConnectUrl() async {
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
