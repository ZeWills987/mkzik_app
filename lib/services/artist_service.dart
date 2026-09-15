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
  static Future<List<Track>> artistTracks(
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
    return list.whereType<Map<String, dynamic>>().map((j) {
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
  }

  /// `GET /artist/{channelId}/preview` — aperçu rapide d'un artiste YTMusic.
  static Future<ArtistPreview?> artistPreview(String channelId) async {
    final uri = Uri.parse('${ApiConfig.pythonUrl}artist/${Uri.encodeComponent(channelId)}/preview');
    final res = await ApiClient.getUri(uri, auth: false, timeout: _timeout);
    final data = res.orElse(null);
    return data is Map<String, dynamic> ? ArtistPreview.fromJson(data) : null;
  }
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
