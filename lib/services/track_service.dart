import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders, SocketException, HandshakeException, HttpException;
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';
import '../models/track_source.dart';
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

/// URL audio signée S3 + date d'expiration (null si l'API ne la fournit pas).
class SignedAudio {
  final String url;
  final DateTime? expiresAt;
  const SignedAudio(this.url, this.expiresAt);

  static SignedAudio? fromJson(dynamic data) {
    if (data is! Map) return null;
    final url = (data['audio_url'] ?? data['audioUrl'] ?? data['url'])?.toString() ?? '';
    if (url.isEmpty) return null;
    return SignedAudio(url, _parseExpiry(data['expires_at'] ?? data['expiresAt']));
  }

  // Timestamp Unix (secondes ou millisecondes) ou date ISO.
  static DateTime? _parseExpiry(dynamic v) {
    if (v is num) {
      final n = v.toInt();
      return DateTime.fromMillisecondsSinceEpoch(n > 100000000000 ? n : n * 1000);
    }
    if (v is String) return DateTime.tryParse(v) ?? _parseExpiry(int.tryParse(v));
    return null;
  }
}

/// Accès aux routes "tracks". Le HTTP/erreurs est délégué à [ApiClient] ;
/// ici on ne fait que construire l'URL et parser le JSON en modèles.
class TrackService {
  // ── Recherche ──────────────────────────────────────────────────────────────

  /// `GET api/popular/tracks?title=` → titres internes triés par popularité.
  /// Route hors du namespace `tracks` pour éviter la collision avec le wildcard
  /// `GET api/tracks/{username}`.
  static Future<List<Track>> searchTracks(String query) async {
    final res = await ApiClient.getUri(_api('api/popular/tracks', {'title': query}));
    return _tracksFrom(res.orElse(null));
  }

  /// `GET api/user?username=` → utilisateurs.
  static Future<List<SearchUser>> searchUsers(String query) async {
    final res = await ApiClient.getUri(_api('api/user', {'username': query}), auth: false);
    return _usersFrom(res.orElse(null));
  }

  /// Recherche externe en **streaming SSE** (YouTube Music + SoundCloud), paginée.
  /// `GET {PYTHON}search/stream?query=&max_results=&page=` → events `track` / `error` / `done`.
  ///
  /// Un échec de connexion AVANT tout résultat (timeout, coupure TLS, 502/503…)
  /// est retenté une fois, en silence : la 1ʳᵉ connexion vers le service Python
  /// échoue parfois alors que la suivante passe. L'utilisateur ne voit une
  /// erreur que si le 2ᵉ essai échoue aussi.
  static Stream<ExternalSearchEvent> searchExternalStream(
    String query, {
    int maxResults = 30,
    int page = 1,
  }) async* {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var receivedTracks = false;
      var failed = false;
      await for (final ev in _searchExternalOnce(query, maxResults: maxResults, page: page)) {
        if (ev.tracks.isNotEmpty) receivedTracks = true;
        // Échec de connexion sans aucun résultat → on retente au lieu de l'afficher.
        if (ev.error != null && ev.done && !receivedTracks && attempt < maxAttempts) {
          failed = true;
          break;
        }
        yield ev;
      }
      if (!failed) return;
      mkLog('Mkzik 🔎 SSE nouvel essai ($attempt/$maxAttempts) → "$query"');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  /// Message affichable (français, sans détail technique) pour une erreur
  /// réseau — le détail brut reste dans les logs.
  static String _friendlyNetworkError(Object e) {
    if (e is TimeoutException) return 'Le serveur met trop de temps à répondre.';
    if (e is SocketException || e is HandshakeException || e is HttpException || e is http.ClientException) {
      return 'Connexion au serveur impossible. Vérifie ta connexion.';
    }
    return 'La recherche externe est momentanément indisponible.';
  }

  static String _friendlyHttpError(int status) {
    if (status == 429) return 'Trop de recherches à la suite, réessaie dans quelques secondes.';
    if (status >= 500) return 'Le service de recherche est momentanément indisponible.';
    return 'La recherche externe est momentanément indisponible.';
  }

  static Stream<ExternalSearchEvent> _searchExternalOnce(
    String query, {
    required int maxResults,
    required int page,
  }) async* {
    final uri = Uri.parse('${ApiConfig.pythonUrl}search/stream').replace(queryParameters: {
      'query': query,
      'max_results': '$maxResults',
      'page': '$page',
    });
    mkLog('Mkzik 🔎 SSE connect → $uri');
    // `dart:io HttpClient` directement (comme le flux des artistes, qui livre
    // bien les événements au fil de l'eau) plutôt que `package:http`. Pas de
    // compression : un intermédiaire qui compresse un flux SSE le retient
    // jusqu'à la fin.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final started = DateTime.now();
    String elapsed() => '${DateTime.now().difference(started).inMilliseconds} ms';
    try {
      // Timeout de connexion : sans ça, un serveur Python injoignable laisse
      // le spinner de recherche externe tourner indéfiniment.
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/event-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..set(HttpHeaders.acceptEncodingHeader, 'identity');
      // Toutes les routes Python exigent désormais le JWT, y compris les flux SSE.
      final jwt = ApiConfig.token;
      if (jwt != null && jwt.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $jwt');
      }
      final response = await request.close().timeout(const Duration(seconds: 20));
      mkLog('Mkzik 🔎 SSE status ${response.statusCode} (${elapsed()})');
      if (response.statusCode != 200) {
        mkLog('Mkzik 🔎 SSE refusé → HTTP ${response.statusCode}');
        yield ExternalSearchEvent(error: _friendlyHttpError(response.statusCode), done: true);
        return;
      }
      var event = 'message';
      var receivedAny = false;
      var lineCount = 0;
      // Timeout d'inactivité : si le flux reste muet 30 s (yt-dlp bloqué),
      // on ferme proprement au lieu d'attendre un event `done` qui ne vient pas.
      final lines = response
          .timeout(const Duration(seconds: 30), onTimeout: (sink) => sink.close())
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (++lineCount == 1) mkLog('Mkzik 🔎 SSE 1re ligne reçue (${elapsed()})');
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final raw = line.substring(5).trim();
          if (raw.isEmpty) continue;
          final data = jsonDecode(raw);
          if (event == 'track') {
            // Nouveau format : un event par track
            final src = (data['source'] ?? '').toString();
            final tracks = _tracksFrom(data is List ? data : [data], forceSource: src.isEmpty ? null : src);
            if (tracks.isNotEmpty) {
              receivedAny = true;
              mkLog('Mkzik 🔎 SSE track → ${tracks.first.title}');
              yield ExternalSearchEvent(source: src, tracks: tracks);
            }
          } else if (event == 'ytm' || event == 'sc') {
            // Ancien format — rétrocompatibilité
            final tracks = _tracksFrom(data, forceSource: event);
            if (tracks.isNotEmpty) receivedAny = true;
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
      // Flux fermé sans event `done` (coupure réseau, inactivité 30 s). Si rien
      // n'est arrivé, c'est un échec (et non « aucun résultat ») → retenté /
      // signalé plutôt que de laisser croire que la recherche est vide.
      if (!receivedAny) {
        mkLog('Mkzik 🔎 SSE fermé sans résultat ni done ($lineCount lignes, ${elapsed()})');
        yield ExternalSearchEvent(error: _friendlyNetworkError(TimeoutException('flux fermé')), done: true);
      }
    } catch (e) {
      mkLog('Mkzik 🔎 SSE exception → ${e.runtimeType}: $e');
      yield ExternalSearchEvent(error: _friendlyNetworkError(e), done: true);
    } finally {
      // force : coupe réellement la connexion si la recherche est annulée en
      // cours de flux (nouvelle requête, changement d'écran).
      client.close(force: true);
    }
  }

  // ── Home ─────────────────────────────────────────────────────────────────

  /// `GET api/news?limit=&offset=` → feed d'actualité.
  static Future<List<Track>> getNewsFeed({int limit = 10, int offset = 0}) async {
    final res = await ApiClient.getUri(_api('api/news', {'limit': '$limit', 'offset': '$offset'}));
    return _tracksFrom(res.getOrThrow());
  }

  /// `GET api/history/tracks?limit=&offset=` → historique d'écoute.
  /// Route volontairement hors du namespace `tracks` pour éviter la collision
  /// avec le wildcard `GET api/tracks/{username}`.
  static Future<List<Track>> getHistoryPlay({int limit = 10, int offset = 0}) async {
    final res = await ApiClient.getUri(_api('api/history/tracks', {
      'limit': '$limit',
      'offset': '$offset',
      'include_external': '1',
    }));
    return _tracksFrom(res.getOrThrow());
  }

  /// `GET api/feed?limit=&cursor=` → fil « Banger » (scroll infini).
  /// Réponse : { items: [Track], next_cursor: string | null }. Le curseur est
  /// opaque (à renvoyer tel quel) ; `null` = fin du fil. Sans curseur = 1re page.
  static Future<({List<Track> items, String? nextCursor})> getFeed({int limit = 20, String? cursor}) async {
    final res = await ApiClient.getUri(_api('api/feed', {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }));
    final data = res.getOrThrow();
    final next = data is Map ? data['next_cursor']?.toString() : null;
    return (
      items: _tracksFrom(data is Map ? data['items'] : data),
      nextCursor: (next == null || next.isEmpty) ? null : next,
    );
  }

  /// `GET api/trending?limit=` → utilisateurs tendance.
  static Future<List<SearchUser>> getTrendingUsers({int limit = 10}) async {
    final res = await ApiClient.getUri(_api('api/trending', {'limit': '$limit'}), auth: false);
    return _usersFrom(res.orElse(null));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// `POST api/tracks/{id}/likes` → like / unlike (toggle).
  /// Renvoie l'état après bascule (`isLiked`) et le nouveau total de likes.
  static Future<({bool ok, bool isLiked, int likes})> toggleLike(int trackId) async {
    final res = await ApiClient.postUri(_api('api/tracks/$trackId/likes'));
    return switch (res) {
      Ok(:final data) => (
          ok: true,
          isLiked: data is Map ? data['is_liked'] == true : false,
          likes: data is Map ? (data['nb_likes'] as num?)?.toInt() ?? 0 : 0,
        ),
      Err() => (ok: false, isLiked: false, likes: 0),
    };
  }

  /// `GET api/{username}/favourites?limit=&offset=` → Ziks likés par l'utilisateur.
  /// Sans limit (ou 0) le backend renvoie tout (rétrocompatible).
  static Future<List<Track>> getFavourites(String username, {int limit = 0, int offset = 0}) async {
    final res = await ApiClient.getUri(_api(
      'api/${Uri.encodeComponent(username)}/favourites',
      limit > 0 ? {'limit': '$limit', 'offset': '$offset'} : null,
    ));
    return _tracksFrom(res.orElse(null));
  }

  /// `POST api/tracks/{id}/plays` → enregistre une écoute (historique). Fire-and-forget.
  static Future<void> recordPlay(int trackId) async {
    await ApiClient.postUri(_api('api/tracks/$trackId/plays'));
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

  /// `GET api/tracks/{id}/sources` → sources (originaux) d'un dérivé.
  /// Liste vide = c'est un original (pas de section "Sources" à afficher).
  static Future<List<TrackSource>> getSources(int trackId) async {
    final res = await ApiClient.getUri(_api('api/tracks/$trackId/sources'));
    final data = res.orElse(null);
    if (data is! Map) return const [];
    final list = data['sources'];
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(TrackSource.fromJson).toList();
  }

  /// `GET api/tracks/{id}/audio` → { audio_url, expires_at }.
  static Future<SignedAudio?> getSignedAudio(int trackId) async {
    final res = await ApiClient.getUri(_api('api/tracks/$trackId/audio'));
    return SignedAudio.fromJson(res.orElse(null));
  }

  /// `POST api/tracks/sign-batch` body {ids} → `{ "<id>": {audio_url, expires_at} }`.
  /// Signe plusieurs titres en UNE requête (remplace la rafale de GET .../audio
  /// au chargement d'une file). Renvoie une map id → URL signée (ids absents
  /// de la réponse = non signables).
  static Future<Map<int, SignedAudio>> getSignedAudioBatch(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final res = await ApiClient.postUri(_api('api/tracks/sign-batch'), body: {'ids': ids});
    final data = res.orElse(null);
    if (data is! Map) return const {};
    final out = <int, SignedAudio>{};
    data.forEach((key, value) {
      final id = int.tryParse('$key');
      final signed = SignedAudio.fromJson(value);
      if (id != null && signed != null) out[id] = signed;
    });
    return out;
  }

  /// `GET api/me/imports?limit=&offset=` → Ziks importés de l'utilisateur.
  /// Réponse : { imports: [{imported_at, source_url, track}], total }.
  static Future<List<Track>> getImports({int limit = 20, int offset = 0}) async {
    final res = await ApiClient.getUri(_api('api/me/imports', {'limit': '$limit', 'offset': '$offset'}));
    final data = res.orElse(null);
    if (data is! Map) return const [];
    final list = data['imports'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((j) => j['track'])
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList();
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
