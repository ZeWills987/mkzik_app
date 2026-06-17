import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/profile.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Accès aux routes profil (cf. React ProfileService).
class ProfileService {
  /// `GET api/profile?username=` → profil utilisateur.
  static Future<Profile?> getProfile(String username) async {
    final res = await ApiClient.getUri(_api('api/profile', {'username': username}));
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Profile.fromJson(data) : null;
  }

  /// `GET api/tracks/{username}` → Ziks de l'utilisateur.
  static Future<List<Track>> getUserTracks(String username) async {
    final res = await ApiClient.getUri(_api('api/tracks/${Uri.encodeComponent(username)}'));
    final data = res.orElse(null);
    final list = data is List ? data : (data is Map ? (data['tracks'] as List? ?? const []) : const []);
    return list.whereType<Map<String, dynamic>>().map(Track.fromJson).toList();
  }

  /// `POST api/follow` body {username} → bascule le suivi.
  static Future<bool> toggleFollow(String username) async {
    final res = await ApiClient.postUri(_api('api/follow'), body: {'username': username});
    return res.isOk;
  }

  /// `PUT api/update` (JSON) — met à jour les champs fournis (non vides).
  /// Renvoie un `newToken` si l'username a changé (nouveau JWT côté backend).
  static Future<({bool ok, String message, String? newToken})> updateProfile(Map<String, String> fields) async {
    final body = <String, dynamic>{};
    fields.forEach((k, v) {
      if (v.trim().isNotEmpty) body[k] = v.trim();
    });
    if (body.isEmpty) return (ok: false, message: 'Aucune modification', newToken: null);

    final res = await ApiClient.putUri(_api('api/update'), body: body);
    return switch (res) {
      Ok(:final data) => (
          ok: true,
          message: _msg(data) ?? 'Profil mis à jour',
          newToken: data is Map ? data['token']?.toString() : null,
        ),
      Err(:final message) => (ok: false, message: message, newToken: null),
    };
  }

  /// `PUT api/update_avatar` (multipart) — avatar ET background requis.
  /// Reste hors [ApiClient] car ce n'est pas du JSON.
  static Future<({bool ok, String message})> updateAvatar({
    required File avatar,
    required File background,
  }) async {
    final uri = _api('api/update_avatar');
    try {
      final request = http.MultipartRequest('PUT', uri);
      if (ApiConfig.token?.isNotEmpty ?? false) {
        request.headers['Authorization'] = 'Bearer ${ApiConfig.token}';
      }
      request.files.add(await http.MultipartFile.fromPath('avatar', avatar.path));
      request.files.add(await http.MultipartFile.fromPath('background', background.path));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return (ok: true, message: 'Photos mises à jour');
      }
      String errMsg = 'Erreur ${res.statusCode} lors de l\'envoi des photos';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final m = decoded['message'] ?? decoded['error'] ?? decoded['detail'];
          if (m != null) errMsg = m.toString();
        }
      } catch (_) {}
      return (ok: false, message: errMsg);
    } catch (_) {
      return (ok: false, message: 'Connexion au serveur impossible');
    }
  }

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  static String? _msg(dynamic data) => data is Map ? data['message']?.toString() : null;
}
