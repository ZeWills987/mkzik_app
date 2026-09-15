import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/api_config.dart';
import '../models/track.dart';
import 'api_client.dart';

/// Profil et tracks d'artistes externes (YouTube Music / SoundCloud).
/// Toutes les routes sont sur le microservice Python.
class ArtistService {
  static const _timeout = Duration(seconds: 25);

  /// `GET /artist/tracks?url=&id=&max_results=`
  /// Scrape les tracks d'un artiste YouTube ou SoundCloud.
  /// [id] = ID Symfony de l'artiste — active l'exclusion des tracks déjà importées.
  static Future<ArtistTracksResult> artistTracks(
    String url, {
    int? symfonyId,
    int maxResults = 30,
  }) async {
    final params = <String, String>{
      'url': url,
      'max_results': '$maxResults',
      if (symfonyId != null) 'id': '$symfonyId',
    };
    final uri = Uri.parse('${ApiConfig.pythonUrl}artist/tracks').replace(queryParameters: params);
    final res = await ApiClient.getUri(uri, auth: false, timeout: _timeout);
    final data = res.orElse(null);
    final list = data is Map ? (data['tracks'] as List? ?? const []) : (data is List ? data : const []);
    final tracks = list.whereType<Map<String, dynamic>>().map((j) {
      try {
        final m = Map<String, dynamic>.from(j);
        if ((m['source'] ?? '').toString().isEmpty) {
          m['source'] = url.contains('soundcloud') ? 'sc' : 'ytm';
        }
        return Track.fromJson(m);
      } catch (_) {
        return null;
      }
    }).whereType<Track>().toList();

    ArtistPreview? artist;
    if (data is Map && data['artist'] is Map<String, dynamic>) {
      artist = ArtistPreview.fromJson(data['artist'] as Map<String, dynamic>);
    }

    return ArtistTracksResult(tracks: tracks, artist: artist);
  }

  /// `GET /artist/tracks/stream` — SSE : envoie les tracks une par une dès découverte.
  /// Émet des snapshots cumulatifs `ArtistTracksResult` à chaque track reçue.
  static Stream<ArtistTracksResult> artistTracksStream(
    String url, {
    int? symfonyId,
    int maxResults = 200,
  }) async* {
    final params = <String, String>{
      'url': url,
      'max_results': '$maxResults',
      if (symfonyId != null) 'id': '$symfonyId',
    };
    final uri = Uri.parse('${ApiConfig.pythonUrl}artist/tracks/stream').replace(queryParameters: params);

    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.add('Accept', 'text/event-stream');
      request.headers.add('Cache-Control', 'no-cache');
      if (ApiConfig.token != null) {
        request.headers.add('Authorization', 'Bearer ${ApiConfig.token}');
      }
      final response = await request.close();

      final accumulated = <Track>[];
      ArtistPreview? artist;
      final source = url.contains('soundcloud') ? 'sc' : 'ytm';

      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty) continue;
        final json = jsonDecode(payload) as Map<String, dynamic>;

        if (json['done'] == true) break;

        if (json.containsKey('name') && !json.containsKey('title')) {
          artist = ArtistPreview.fromJson(json);
          yield ArtistTracksResult(tracks: List.unmodifiable(accumulated), artist: artist);
          continue;
        }

        try {
          final m = Map<String, dynamic>.from(json);
          if ((m['source'] ?? '').toString().isEmpty) m['source'] = source;
          accumulated.add(Track.fromJson(m));
          yield ArtistTracksResult(tracks: List.unmodifiable(accumulated), artist: artist);
        } catch (_) {}
      }
    } finally {
      httpClient.close();
    }
  }

  /// `GET /artist/{channelId}/preview` — aperçu rapide d'un artiste YTMusic.
  static Future<ArtistPreview?> artistPreview(String channelId) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}artist/${Uri.encodeComponent(channelId)}/preview');
    final res = await ApiClient.getUri(uri, auth: false, timeout: _timeout);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? ArtistPreview.fromJson(data) : null;
  }
}

class ArtistTracksResult {
  final List<Track> tracks;
  final ArtistPreview? artist;
  const ArtistTracksResult({required this.tracks, this.artist});
}

class ArtistPreview {
  final String name;
  final String channelId;
  final String thumbnail;
  final String subscribers;

  const ArtistPreview({
    required this.name,
    required this.channelId,
    required this.thumbnail,
    required this.subscribers,
  });

  factory ArtistPreview.fromJson(Map<String, dynamic> j) => ArtistPreview(
        name: (j['name'] ?? '').toString(),
        channelId: (j['channel_id'] ?? '').toString(),
        thumbnail: (j['thumbnail'] ?? '').toString(),
        subscribers: (j['subscribers'] ?? '').toString(),
      );
}
