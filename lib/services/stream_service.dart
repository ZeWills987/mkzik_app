import '../config/api_config.dart';
import 'api_client.dart';

/// Gestion du flux audio temps réel (Python / yt-dlp).
class StreamService {
  /// Pré-chauffe [pageUrls] en arrière-plan : Python lance yt-dlp en avance de
  /// phase pour que le prochain `/stream?url=` soit un cache hit (~0 ms).
  ///
  /// Appel fire-and-forget : les erreurs sont silencieuses pour ne jamais
  /// bloquer ou retarder la lecture en cours.
  static Future<void> prepare(List<String> pageUrls) async {
    if (pageUrls.isEmpty) return;
    final params = pageUrls
        .map((u) => 'urls=${Uri.encodeQueryComponent(u)}')
        .join('&');
    final uri = Uri.parse('${ApiConfig.pythonUrl}stream/prepare?$params');
    try {
      await ApiClient.getUri(uri, auth: false);
    } catch (_) {}
  }
}
