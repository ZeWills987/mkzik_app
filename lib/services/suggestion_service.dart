import '../config/api_config.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Suggestions de titres externes (microservice Python yt-dlp).
///
/// Toutes les routes renvoient une liste JSON au même format que la recherche ;
/// chaque `url` se branche directement sur `/stream` (lecture temps réel).
///   GET /suggestions/youtube/top?country=&limit=
///   GET /suggestions/youtube/related?url=&limit=
///   GET /suggestions/soundcloud/top?genre=&limit=
///   GET /suggestions/soundcloud/related?url=&limit=
class SuggestionService {
  // yt-dlp / ytmusic peut être lent (charts, "up next") → marge plus large.
  static const _timeout = Duration(seconds: 20);

  // ── Charts (suggestions globales) ──────────────────────────────────────────

  /// Top YouTube Music (charts). [country] = code ISO (`ZZ` = monde).
  static Future<List<Track>> youtubeTop({int limit = 25, String country = 'ZZ'}) =>
      _list('suggestions/youtube/top', {'country': country, 'limit': '$limit'}, 'ytm');

  /// Top SoundCloud (charts publiques). [genre] = genre des charts SC.
  static Future<List<Track>> soundcloudTop({int limit = 25, String genre = 'all-music'}) =>
      _list('suggestions/soundcloud/top', {'genre': genre, 'limit': '$limit'}, 'sc');

  // ── Related (suggestions par track) ────────────────────────────────────────

  /// Titres similaires ("up next") à un titre YouTube. [url] = URL YouTube de réf.
  static Future<List<Track>> youtubeRelated(String url, {int limit = 25}) =>
      _list('suggestions/youtube/related', {'url': url, 'limit': '$limit'}, 'ytm');

  /// Titres similaires à un titre SoundCloud. [url] = URL SoundCloud de réf.
  static Future<List<Track>> soundcloudRelated(String url, {int limit = 25}) =>
      _list('suggestions/soundcloud/related', {'url': url, 'limit': '$limit'}, 'sc');

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<List<Track>> _list(String path, Map<String, String> query, String source) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}$path').replace(queryParameters: query);
    final res = await ApiClient.getUri(uri, auth: false, timeout: _timeout);
    return _parse(res.orElse(null), source);
  }

  /// Parse la liste en [Track] externes ; force `source` (ytm/sc) si absent, pour
  /// garantir `needsImport == true` (lecture via /stream, pas via la base).
  static List<Track> _parse(dynamic data, String source) {
    final list = data is List ? data : const [];
    return list.whereType<Map<String, dynamic>>().map((j) {
      final m = Map<String, dynamic>.from(j);
      if ((m['source'] ?? '').toString().isEmpty) m['source'] = source;
      return Track.fromJson(m);
    }).toList();
  }
}
