import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/logger.dart';

class TrackUploadException implements Exception {
  final String message;
  TrackUploadException(this.message);
  @override
  String toString() => message;
}

class TrackUploadService {
  static String slugify(String text) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'ì': 'i', 'í': 'i',
      'ô': 'o', 'ö': 'o', 'ò': 'o', 'ó': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    var s = text.toLowerCase().trim();
    for (final e in accents.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static Future<void> upload({
    required String title,
    required String audioPath,
    String? description,
    String? thumbnailPath,
    List<String> genres = const [],
    String status = 'PUBLIC',
    int? albumId,
  }) async {
    final token = ApiConfig.token;
    if (token == null || token.isEmpty) throw TrackUploadException('Non authentifié');

    final uri = Uri.parse('${ApiConfig.baseUrl}api/tracks');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['title'] = title
      ..fields['url'] = slugify(title)
      ..fields['status'] = status;

    if (albumId != null) req.fields['album_id'] = '$albumId';

    if (description != null && description.isNotEmpty) {
      req.fields['description'] = description;
    }

    // genres[] : champ répété → on envoie chaque valeur comme part texte distincte
    for (final genre in genres) {
      req.files.add(http.MultipartFile.fromString('genres[]', genre));
    }

    req.files.add(await http.MultipartFile.fromPath('audio', audioPath));
    if (thumbnailPath != null) {
      req.files.add(await http.MultipartFile.fromPath('thumbnails', thumbnailPath));
    }

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 201) return;

      String message = 'Erreur ${res.statusCode}';
      if (res.body.isNotEmpty) {
        try {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final e = data['message'] ?? data['error'] ?? data['detail'];
            if (e is String && e.isNotEmpty) message = e;
            if (e is List) message = (e as List).join(', ');
          }
        } catch (_) {}
      }
      mkLog('TrackUpload ✕ POST api/tracks : HTTP ${res.statusCode} → $message | body: ${res.body}');
      throw TrackUploadException(message);
    } on TrackUploadException {
      rethrow;
    } catch (e) {
      mkLog('TrackUpload ✕ : $e');
      throw TrackUploadException('Connexion au serveur impossible');
    }
  }
}
