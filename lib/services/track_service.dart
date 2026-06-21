import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';
import '../models/search_user.dart';
import 'api_client.dart';
import '../utils/logger.dart';

/// Événement émis par le flux SSE de recherche externe (`/search/stream`).
class ExternalSearchEvent {
  final String source; // 'ytm' | 'sc' | ''
  final List<Track> tracks;
  final bool done;
  final String? error;

  const ExternalSearchEvent({this.source = '', this.tracks = const [], this.done = false, this.error});
}

/// Accès aux routes "tracks". Le HTTP/erreurs est délégué à [ApiClient] ;
/// ici on ne fait que construire l'URL et parser le JSON en modèles.
class TrackService {
  // ── Recherche ──────────────────────────────────────────────────────────────

  /// `GET api/track/popularity?title=` → titres internes triés par popularité.
  static Future<List<Track>> searchTracks(String query) async {
    final res = await ApiClient.getUri(_api('api/track/popularity', {'title': query}));
    return _tracksFrom(res.orElse(null));
  }

  /// `GET api/user?username=` → utilisateurs.
  static Future<List<SearchUser>> searchUsers(String query) async {
    final res = await ApiClient.getUri(_api('api/user', {'username': query}), auth: false);
    return _usersFrom(res.orElse(null));
  }

  /// Recherche externe en **streaming SSE** (YouTube Music + SoundCloud).
  /// `GET {PYTHON}search/stream?query=` → events `ytm` / `sc` / `error` / `done`.
  static Stream<ExternalSearchEvent> searchExternalStream(String query) async* {
    final uri = Uri.parse('${ApiConfig.pythonUrl}search/stream?query=${Uri.encodeQueryComponent(query)}');
    mkLog('Mkzik 🔎 SSE connect → $uri');
    final request = http.Request('GET', uri)..headers['Accept'] = 'text/event-stream';
    final client = http.Client();
    try {
      final response = await client.send(request);
      mkLog('Mkzik 🔎 SSE status ${response.statusCode}');
      if (response.statusCode != 200) {
        yield ExternalSearchEvent(error: 'HTTP ${response.statusCode}', done: true);
        return;
      }
      var event = 'message';
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final raw = line.substring(5).trim();
          if (raw.isEmpty) continue;
          final data = jsonDecode(raw);
          if (event == 'ytm' || event == 'sc') {
            final tracks = _tracksFrom(data, forceSource: event);
            mkLog('Mkzik 🔎 SSE $event → ${tracks.length} titres');
            yield ExternalSearchEvent(source: event, tracks: tracks);
          } else if (event == 'error') {
            mkLog('Mkzik 🔎 SSE error → $data');
            yield ExternalSearchEvent(
              source: (data['source'] ?? '').toString(),
              error: (data['message'] ?? 'Erreur').toString(),
            );
          } else if (event == 'done') {
            mkLog('Mkzik 🔎 SSE done');
            yield const ExternalSearchEvent(done: true);
            return;
          }
        }
      }
    } catch (e) {
      mkLog('Mkzik 🔎 SSE exception → $e');
      yield ExternalSearchEvent(error: '$e', done: true);
    } finally {
      client.close();
    }
  }

  // ── Home ─────────────────────────────────────────────────────────────────

  /// `GET api/news?limit=&offset=` → feed d'actualité.
  static Future<List<Track>> getNewsFeed({int limit = 10, int offset = 0}) async {
    final res = await ApiClient.getUri(_api('api/news', {'limit': '$limit', 'offset': '$offset'}));
    return _tracksFrom(res.orElse(null));
  }

  /// `GET api/history_played?limit=&offset=` → historique d'écoute.
  static Future<List<Track>> getHistoryPlay({int limit = 10, int offset = 0}) async {
    final res = await ApiClient.getUri(_api('api/history_played', {'limit': '$limit', 'offset': '$offset'}));
    return _tracksFrom(res.orElse(null));
  }

  /// `GET api/trending?limit=` → utilisateurs tendance.
  static Future<List<SearchUser>> getTrendingUsers({int limit = 10}) async {
    final res = await ApiClient.getUri(_api('api/trending', {'limit': '$limit'}), auth: false);
    return _usersFrom(res.orElse(null));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// `POST api/track/like` body {track_id} → like / unlike.
  /// Renvoie l'état après bascule (`isLiked`) et le nouveau total de likes.
  static Future<({bool ok, bool isLiked, int likes})> toggleLike(int trackId) async {
    final res = await ApiClient.postUri(_api('api/track/like'), body: {'track_id': trackId});
    return switch (res) {
      Ok(:final data) => (
          ok: true,
          isLiked: data is Map ? data['is_liked'] == true : false,
          likes: data is Map ? (data['nb_likes'] as num?)?.toInt() ?? 0 : 0,
        ),
      Err() => (ok: false, isLiked: false, likes: 0),
    };
  }

  /// `GET api/{username}/favourites` → Ziks likés par l'utilisateur.
  static Future<List<Track>> getFavourites(String username) async {
    final res = await ApiClient.getUri(_api('api/${Uri.encodeComponent(username)}/favourites'));
    return _tracksFrom(res.orElse(null));
  }

  /// `GET api/tracks/{id}/play` → enregistre une écoute (historique). Fire-and-forget.
  static Future<void> recordPlay(int trackId) async {
    if (!(ApiConfig.token?.isNotEmpty ?? false)) return;
    await ApiClient.getUri(_api('api/tracks/$trackId/play'));
  }

  /// `POST api/plays` body {trackId} → 201 {playId}. Début d'une écoute (tracking
  /// détaillé). Renvoie le playId à fournir à [completePlay], ou null si échec.
  static Future<int?> startPlay(int trackId) async {
    if (!(ApiConfig.token?.isNotEmpty ?? false)) return null;
    final res = await ApiClient.postUri(_api('api/plays'), body: {'trackId': trackId});
    final data = res.orElse(null);
    return data is Map ? (data['playId'] as num?)?.toInt() : null;
  }

  /// `PATCH api/plays/{id}/complete` body {listenedSeconds, completed} → 204.
  /// Fin d'une écoute (secondes écoutées + lecture terminée ou non).
  static Future<void> completePlay(int playId,
      {required double listenedSeconds, required bool completed}) async {
    if (!(ApiConfig.token?.isNotEmpty ?? false)) return;
    await ApiClient.patchUri(
      _api('api/plays/$playId/complete'),
      body: {'listenedSeconds': listenedSeconds, 'completed': completed},
    );
  }

  /// `GET api/tracks/{id}/audio` → { audio_url, expires_at }.
  static Future<String?> getSignedAudioUrl(int trackId) async {
    final res = await ApiClient.getUri(_api('api/tracks/$trackId/audio'));
    final data = res.orElse(null);
    if (data is! Map) return null;
    return (data['audio_url'] ?? data['audioUrl'] ?? data['url'])?.toString();
  }

  /// `POST api/external-track/download` body {track_url} → import d'un externe.
  static Future<Map<String, dynamic>?> importExternalTrack(String trackUrl) async {
    final res = await ApiClient.postUri(_api('api/external-track/download'), body: {'track_url': trackUrl});
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? data : null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  static List<Track> _tracksFrom(dynamic data, {String? forceSource}) {
    final list = data is List ? data : (data is Map ? (data['tracks'] as List? ?? const []) : const []);
    return list.whereType<Map<String, dynamic>>().map((j) {
      if (forceSource == null) return Track.fromJson(j);
      final m = Map<String, dynamic>.from(j);
      if (m['source'] == null || '${m['source']}'.isEmpty) m['source'] = forceSource;
      return Track.fromJson(m);
    }).toList();
  }

  static List<SearchUser> _usersFrom(dynamic data) {
    final list = data is List ? data : (data is Map ? (data['users'] as List? ?? const []) : const []);
    return list.whereType<Map<String, dynamic>>().map(SearchUser.fromJson).toList();
  }
}
