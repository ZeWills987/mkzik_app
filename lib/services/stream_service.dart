import 'dart:async';
import '../config/api_config.dart';
import 'api_client.dart';

/// Interactions non-audio avec le microservice Python (yt-dlp).
class StreamService {
  /// Pré-chauffe le cache yt-dlp pour [url] (prochaine track externe).
  /// `GET /stream/prepare?urls=<url>` → 202 immédiat, résolution en arrière-plan.
  /// Fire-and-forget : les erreurs sont silencieuses (optimisation, pas critique).
  static void prepareNext(String url) {
    if (!ApiConfig.externalStream || url.isEmpty) return;
    final uri = Uri.parse(
      '${ApiConfig.pythonUrl}stream/prepare?urls=${Uri.encodeComponent(url)}',
    );
    unawaited(ApiClient.getUri(uri, auth: false, timeout: const Duration(seconds: 5)));
  }
}
