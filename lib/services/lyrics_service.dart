import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/lyrics.dart';
import '../utils/logger.dart';
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

  /// Paroles d'un flux direct. [artist]/[title] sont optionnels mais recommandés :
  /// la résolution est plus rapide et fiable que via l'URL seule.
  static Future<Lyrics?> fetchByUrl(String pageUrl, {String? artist, String? title}) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}lyrics').replace(queryParameters: {
      'url': pageUrl,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
      if (title != null && title.isNotEmpty) 'title': title,
    });
    final res = await ApiClient.getUri(uri, auth: false);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? Lyrics.fromJson(data) : null;
  }

  /// Sonde le header `X-Has-Lyrics` du flux pour décider d'afficher le bouton
  /// Paroles, sans télécharger l'audio (requête `Range: bytes=0-0`).
  /// Renvoie `null` si indéterminé (réseau/timeout) → l'appelant reste optimiste.
  static Future<bool?> streamHasLyrics(String pageUrl) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(ApiConfig.streamUrl(pageUrl)))
        ..headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      final v = resp.headers['x-has-lyrics'];
      // On vide le flux pour libérer la connexion sans lire l'audio.
      unawaited(resp.stream.drain<void>().catchError((_) {}));
      if (v == null) return null;
      return v == '1';
    } catch (e) {
      mkLog('Mkzik ♪ sonde X-Has-Lyrics échouée : $e');
      return null;
    } finally {
      client.close();
    }
  }
}
