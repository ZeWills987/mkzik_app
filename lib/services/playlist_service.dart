import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Accès aux routes playlist (`/api/playlist`). POST est en form-urlencoded et
/// PATCH n'est pas couvert par [ApiClient] → appels http directs pour ces deux.
class PlaylistService {
  static const _timeout = Duration(seconds: 12);

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  static Map<String, String> _auth([Map<String, String>? extra]) => {
        if (ApiConfig.token?.isNotEmpty ?? false) 'Authorization': 'Bearer ${ApiConfig.token}',
        ...?extra,
      };

  /// `GET /api/playlist?username=` → playlists de l'utilisateur.
  static Future<List<Playlist>> getPlaylists(String username) async {
    final res = await ApiClient.getUri(_api('api/playlist', {'username': username}));
    final data = res.orElse(null);
    final list = data is List ? data : const [];
    return list.whereType<Map<String, dynamic>>().map(Playlist.fromJson).toList();
  }

  /// `POST /api/playlist` (form-urlencoded `title=`) → playlist créée.
  static Future<Playlist?> create(String title) async {
    try {
      final res = await http
          .post(
            _api('api/playlist'),
            headers: _auth({'Content-Type': 'application/x-www-form-urlencoded'}),
            body: {'title': title},
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) return Playlist.fromJson(d);
      }
    } catch (_) {}
    return null;
  }

  /// `PATCH /api/playlist?id=&title=` → renomme.
  static Future<bool> rename(int id, String title) async {
    try {
      final res = await http
          .patch(_api('api/playlist', {'id': '$id', 'title': title}), headers: _auth())
          .timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// `DELETE /api/playlist?id=` → supprime.
  static Future<bool> remove(int id) async {
    final res = await ApiClient.deleteUri(_api('api/playlist', {'id': '$id'}));
    return res.isOk;
  }

  /// `GET /api/playlist/{id}/tracks` → titres de la playlist.
  static Future<List<Track>> getTracks(int playlistId) async {
    final res = await ApiClient.getUri(_api('api/playlist/$playlistId/tracks'));
    final data = res.orElse(null);
    final list = data is List ? data : (data is Map ? (data['tracks'] as List? ?? const []) : const []);
    return list.whereType<Map<String, dynamic>>().map(Track.fromJson).toList();
  }

  /// `POST /api/playlist/{id}/tracks` body {track_id} → ajoute un titre.
  static Future<bool> addTrack(int playlistId, int trackId) async {
    final res = await ApiClient.postUri(_api('api/playlist/$playlistId/tracks'), body: {'track_id': trackId});
    return res.isOk;
  }

  /// `DELETE /api/playlist/{id}/tracks/{trackId}` → retire un titre.
  static Future<bool> removeTrack(int playlistId, int trackId) async {
    final res = await ApiClient.deleteUri(_api('api/playlist/$playlistId/tracks/$trackId'));
    return res.isOk;
  }
}
