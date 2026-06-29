import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';
import '../utils/logger.dart';

/// Import d'un track externe non intégré via le service Python (équivaut au
/// hook React `useDownload`) :
///   1. POST {python}download {url, token} → { download_id }
///   2. SSE  {python}download/{id}/stream → events progress / completed / error
///   3. l'event `completed` renvoie le track désormais intégré (jouable).
class DownloadService {
  /// Lance l'import et attend la fin. Renvoie le track intégré, ou null si échec.
  /// [onStatus] suit la progression ('extracting', 'uploading'…).
  /// [onError] remonte le message d'erreur éventuel.
  static Future<Track?> importAndWait(
    Track track, {
    void Function(String status)? onStatus,
    void Function(String message)? onError,
  }) async {
    try {
      // Auth : le token passe désormais dans l'en-tête `Authorization` (standard,
      // moins exposé que dans le corps qui peut finir dans les logs serveur).
      // ⚠️ Le token reste aussi dans le body en repli le temps que le service
      // Python lise l'en-tête ; à supprimer du body une fois le backend à jour.
      final token = ApiConfig.token;
      final authHeaders = <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      // 1) Démarrage du téléchargement
      final startUri = Uri.parse('${ApiConfig.pythonUrl}download');
      mkLog('Mkzik ⬇ download start → $startUri  (url=${track.pageUrl})');
      final startRes = await http
          .post(startUri,
              headers: authHeaders,
              body: jsonEncode({'url': track.pageUrl, 'token': token}))
          .timeout(const Duration(seconds: 15));

      if (startRes.statusCode != 200) {
        mkLog('Mkzik ⬇ download refusé (${startRes.statusCode}) : ${startRes.body}');
        onError?.call('Serveur indisponible (${startRes.statusCode})');
        return null;
      }
      final downloadId = (jsonDecode(startRes.body) as Map)['download_id'];
      mkLog('Mkzik ⬇ download_id = $downloadId');
      if (downloadId == null) {
        onError?.call('Réponse invalide du serveur');
        return null;
      }

      onStatus?.call('downloading');

      // 2) Écoute du flux SSE
      final streamUri = Uri.parse('${ApiConfig.pythonUrl}download/$downloadId/stream');
      final request = http.Request('GET', streamUri)
        ..headers['Accept'] = 'text/event-stream';
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      final client = http.Client();
      final response = await client.send(request);

      String event = 'message';
      try {
        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            final raw = line.substring(5).trim();
            if (raw.isEmpty) continue;
            final data = jsonDecode(raw);

            if (event == 'completed') {
              final t = data['track'];
              mkLog('Mkzik ⬇ import terminé ✓ (track ${t is Map ? t['title'] : '?'})');
              if (t is Map<String, dynamic>) return Track.fromJson(t);
              return null;
            } else if (event == 'error') {
              mkLog('Mkzik ⬇ erreur import : $data');
              onError?.call((data['message'] ?? 'Échec de l\'import').toString());
              return null;
            } else if (event == 'progress') {
              mkLog('Mkzik ⬇ progress → ${data['status']}');
              onStatus?.call((data['status'] ?? 'downloading').toString());
            }
          }
        }
      } finally {
        client.close();
      }
      onError?.call('Délai dépassé');
      return null;
    } catch (e) {
      mkLog('Mkzik ⬇ exception import : $e');
      onError?.call('Connexion impossible');
      return null;
    }
  }
}
