import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/album.dart';

class AlbumUploadException implements Exception {
  final String message;
  AlbumUploadException(this.message);
  @override
  String toString() => message;
}

class AlbumService {
  /// `POST api/albums` multipart → Album `{id, title, ...}`
  static Future<int> create({
    required String title,
    required String releaseDate,
    String? description,
    String? coverPath,
    List<String> genres = const [],
    String status = 'PUBLIC',
  }) async {
    final token = ApiConfig.token;
    if (token == null || token.isEmpty) throw AlbumUploadException('Non authentifié');

    final uri = Uri.parse('${ApiConfig.baseUrl}api/albums');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['title'] = title
      ..fields['release_date'] = releaseDate
      ..fields['status'] = status;

    if (description != null && description.isNotEmpty) {
      req.fields['description'] = description;
    }
    for (final g in genres) {
      req.files.add(http.MultipartFile.fromString('genres[]', g));
    }
    if (coverPath != null) {
      req.files.add(await http.MultipartFile.fromPath('cover', coverPath));
    }

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Erreur ${res.statusCode}';
      try {
        final d = jsonDecode(res.body);
        if (d is Map) msg = (d['message'] ?? d['error'] ?? msg).toString();
      } catch (_) {}
      throw AlbumUploadException(msg);
    }
    final data = jsonDecode(res.body);
    final id = data is Map ? (data['id'] as num?)?.toInt() : null;
    if (id == null) throw AlbumUploadException('Réponse invalide du serveur');
    return id;
  }

  /// `GET api/albums?username=` → liste des albums d'un artiste.
  static Future<List<Album>> getByUsername(String username) async {
    final token = ApiConfig.token;
    final uri = Uri.parse('${ApiConfig.baseUrl}api/albums?username=${Uri.encodeQueryComponent(username)}');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    return body.whereType<Map<String, dynamic>>().map(Album.fromJson).toList();
  }

  /// `GET api/albums/{id}` → album détail avec ses tracks.
  static Future<Album?> getById(int id) async {
    final token = ApiConfig.token;
    final uri = Uri.parse('${ApiConfig.baseUrl}api/albums/$id');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';

    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    return Album.fromJson(body);
  }
}
