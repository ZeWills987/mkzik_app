import '../config/api_config.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Suggestions de titres externes (microservice Python yt-dlp).
///
/// Toutes les routes renvoient une liste JSON au même format que la recherche ;
/// chaque `url` se branche directement sur `/stream` (lecture temps réel).
///   GET /suggestions/youtube/personal      JWT requis  (YTMusic perso si Google lié)
///   GET /suggestions/youtube/related?url=  JWT optionnel (perso si Google lié)
///   GET /suggestions/soundcloud/top?genre=&limit=
///   GET /suggestions/soundcloud/related?url=&limit=
class SuggestionService {
  // yt-dlp / ytmusic peut être lent (charts, "up next") → marge plus large.
  static const _timeout = Duration(seconds: 20);

  // ── Feed home ──────────────────────────────────────────────────────────────

  /// Feed YTMusic personnalisé — Google lié requis (JWT).
  static Future<List<Track>> youtubePersonal({int limit = 16}) =>
      _list('suggestions/youtube/personal', {'limit': '$limit'}, 'ytm', auth: true);

  /// Feed YTMusic générique — anonyme, aucun JWT.
  static Future<List<Track>> youtubeHome({int limit = 16}) =>
      _list('suggestions/youtube/home', {'limit': '$limit'}, 'ytm');

  /// Top SoundCloud (charts publiques). [genre] = genre des charts SC.
  static Future<List<Track>> soundcloudTop({int limit = 25, String genre = 'all-music'}) =>
      _list('suggestions/soundcloud/top', {'genre': genre, 'limit': '$limit'}, 'sc');

  // ── Related (suggestions par track) ────────────────────────────────────────

  /// Titres similaires ("up next") à un titre YouTube.
  /// Personnalisés si Google lié, anonymes sinon (JWT optionnel côté API).
  static Future<List<Track>> youtubeRelated(String url, {int limit = 25}) =>
      _list('suggestions/youtube/related', {'url': url, 'limit': '$limit'}, 'ytm', auth: true);

  /// Titres similaires à un titre SoundCloud. [url] = URL SoundCloud de réf.
  static Future<List<Track>> soundcloudRelated(String url, {int limit = 25}) =>
      _list('suggestions/soundcloud/related', {'url': url, 'limit': '$limit'}, 'sc');

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<List<Track>> _list(
    String path,
    Map<String, String> query,
    String source, {
    bool auth = false,
  }) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}$path').replace(queryParameters: query);
    final res = await ApiClient.getUri(uri, auth: auth, timeout: _timeout);
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
