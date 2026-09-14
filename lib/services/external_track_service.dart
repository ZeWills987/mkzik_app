import '../config/api_config.dart';
import 'api_client.dart';

/// Routes de like pour les tracks externes (YouTube/SoundCloud pas encore importés).
/// Appel direct app → Symfony (JWT), même sécurité que les likes catalogués.
class ExternalTrackService {
  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  /// `POST /api/external-tracks/likes` → toggle like, retourne le nouvel état.
  /// [platform] : "youtube" ou "soundcloud"
  /// [externalId] : id vidéo YT (ex. "dQw4w9WgXcQ") ou URL SC complète
  static Future<({bool ok, bool isLiked, int likes})> toggleLike({
    required String platform,
    required String externalId,
    String? title,
    String? artist,
  }) async {
    final body = <String, dynamic>{
      'platform': platform,
      'external_id': externalId,
      if (title != null && title.isNotEmpty) 'title': title,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    };
    final res = await ApiClient.postUri(_api('api/external-tracks/likes'), body: body);
    return switch (res) {
      Ok(:final data) => (
          ok: true,
          isLiked: data is Map ? data['is_liked'] == true : false,
          likes: data is Map ? (data['nb_likes'] as num?)?.toInt() ?? 0 : 0,
        ),
      Err() => (ok: false, isLiked: false, likes: 0),
    };
  }

  /// `GET /api/external-tracks/likes?platform=&external_id=` → statut du like.
  static Future<({bool isLiked, int likes})> getLikeStatus({
    required String platform,
    required String externalId,
  }) async {
    final res = await ApiClient.getUri(
      _api('api/external-tracks/likes', {'platform': platform, 'external_id': externalId}),
    );
    final data = res.orElse(null);
    return (
      isLiked: data is Map ? data['is_liked'] == true : false,
      likes: data is Map ? (data['nb_likes'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}
