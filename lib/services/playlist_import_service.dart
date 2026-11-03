import '../config/api_config.dart';
import 'api_client.dart';
import 'track_resolve_service.dart';
import 'youtube_service.dart';

/// Bilan d'un import de playlist.
class PlaylistImportSummary {
  final int total;
  final int matched; // déjà au catalogue → ajoutés tout de suite
  final int queued; // téléchargés en arrière-plan (notification à la fin)
  final int rejected;
  const PlaylistImportSummary({
    required this.total,
    required this.matched,
    required this.queued,
    required this.rejected,
  });

  String get label {
    final parts = ['$matched/$total ajoutés'];
    if (queued > 0) parts.add('$queued en cours de téléchargement');
    if (rejected > 0) parts.add('$rejected ignorés');
    return parts.join(' · ');
  }
}

sealed class PlaylistImportOutcome {
  const PlaylistImportOutcome();
}

class PlaylistImportDone extends PlaylistImportOutcome {
  final PlaylistImportSummary summary;
  const PlaylistImportDone(this.summary);
}

/// Compte Google à (re)lier : import YouTube refusé (403).
class PlaylistImportNeedsReconnect extends PlaylistImportOutcome {
  const PlaylistImportNeedsReconnect();
}

class PlaylistImportFailed extends PlaylistImportOutcome {
  final String message;
  const PlaylistImportFailed(this.message);
}

/// Import d'une playlist depuis un lien collé ou partagé.
class PlaylistImportService {
  /// `POST api/import/playlist` (SoundCloud) body
  /// `{platform, track_urls, playlist_name, source_url}` → 202
  /// `{playlist_id, playlist, total, matched, queued, rejected[]}`.
  /// On envoie toutes les url (`in_mkzik` ou non) : Symfony ajoute lui-même
  /// les titres déjà au catalogue. `source_url` est ignoré tant que Symfony
  /// ne le gère pas (réimport du même set → même playlist).
  static Future<PlaylistImportOutcome> importSoundcloud(ResolvePlaylist playlist) async {
    final urls = [
      for (final t in playlist.tracks)
        if (t.pageUrl.isNotEmpty) t.pageUrl,
    ];
    if (urls.isEmpty) return const PlaylistImportFailed('Aucun titre à importer.');
    final res = await ApiClient.postUri(
      Uri.parse('${ApiConfig.baseUrl}api/import/playlist'),
      body: {
        'platform': 'soundcloud',
        'track_urls': urls,
        'playlist_name': playlist.title.isNotEmpty ? playlist.title : 'Playlist SoundCloud',
        'source_url': playlist.sourceUrl,
      },
    );
    switch (res) {
      case Ok(:final data):
        return PlaylistImportDone(_summary(data, fallbackTotal: urls.length));
      case Err(:final statusCode, :final message):
        return PlaylistImportFailed(switch (statusCode) {
          413 => 'Playlist trop longue (500 titres maximum).',
          429 => 'Limite atteinte : 5 imports par heure. Réessaie plus tard.',
          _ => message,
        });
    }
  }

  /// `POST api/youtube/import/playlist/{id}` : nécessite le compte Google lié
  /// (403 → reconnexion).
  static Future<PlaylistImportOutcome> importYoutube(ResolvePlaylist playlist) async {
    if (playlist.playlistId.isEmpty) return const PlaylistImportFailed('Playlist YouTube introuvable.');
    final res = await YoutubeService.importPlaylist(playlist.playlistId);
    switch (res) {
      case Ok(:final data):
        return PlaylistImportDone(_summary(data, fallbackTotal: playlist.trackCount));
      case Err(:final statusCode, :final message):
        if (statusCode == 403) return const PlaylistImportNeedsReconnect();
        return PlaylistImportFailed(message);
    }
  }

  static PlaylistImportSummary _summary(dynamic data, {required int fallbackTotal}) {
    int n(dynamic v, int d) => v is num ? v.toInt() : d;
    if (data is! Map) {
      return PlaylistImportSummary(total: fallbackTotal, matched: 0, queued: 0, rejected: 0);
    }
    final rejected = data['rejected'];
    return PlaylistImportSummary(
      total: n(data['total'], fallbackTotal),
      matched: n(data['matched'], 0),
      queued: n(data['queued'], 0),
      rejected: rejected is List ? rejected.length : 0,
    );
  }
}
