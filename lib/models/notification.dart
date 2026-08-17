/// Notifications utilisateur (cf. doc back `GET /api/notifications`).
/// Données pures, sans dépendance Flutter.
library;

/// Déclencheur d'une notification (peut avoir été supprimé → null côté notif).
class NotifActor {
  final int id;
  final String username;
  final String? avatar; // URL complète S3/CloudFront

  const NotifActor({required this.id, required this.username, this.avatar});

  factory NotifActor.fromJson(Map<String, dynamic> j) => NotifActor(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: (j['username'] ?? '').toString(),
        avatar: j['avatar']?.toString(),
      );
}

class NotifTrack {
  final int id;
  final String title;
  final String url; // slug
  final String? thumbnails;

  const NotifTrack({required this.id, required this.title, required this.url, this.thumbnails});

  factory NotifTrack.fromJson(Map<String, dynamic> j) => NotifTrack(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        thumbnails: j['thumbnails']?.toString(),
      );
}

class NotifPlaylist {
  final int id;
  final String title;

  const NotifPlaylist({required this.id, required this.title});

  factory NotifPlaylist.fromJson(Map<String, dynamic> j) => NotifPlaylist(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
      );
}

class AppNotification {
  final int id;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final String? message; // si non null → à afficher tel quel (imports, système)
  final NotifActor? actor;
  final NotifTrack? track;
  final NotifPlaylist? playlist;

  const AppNotification({
    required this.id,
    required this.type,
    required this.isRead,
    this.createdAt,
    this.message,
    this.actor,
    this.track,
    this.playlist,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num?)?.toInt() ?? 0,
        type: (j['type'] ?? '').toString(),
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse('${j['created_at']}'),
        message: j['message']?.toString(),
        actor: j['actor'] is Map<String, dynamic> ? NotifActor.fromJson(j['actor'] as Map<String, dynamic>) : null,
        track: j['track'] is Map<String, dynamic> ? NotifTrack.fromJson(j['track'] as Map<String, dynamic>) : null,
        playlist: j['playlist'] is Map<String, dynamic>
            ? NotifPlaylist.fromJson(j['playlist'] as Map<String, dynamic>)
            : null,
      );

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        message: message,
        actor: actor,
        track: track,
        playlist: playlist,
      );

  /// Libellé à afficher : `message` tel quel si présent, sinon construit
  /// depuis type + actor/track/playlist (cf. table de la doc back).
  /// Fallback « Un utilisateur » si l'actor a été supprimé entre-temps.
  String get label {
    if (message != null && message!.isNotEmpty) return message!;
    final who = actor?.username.isNotEmpty == true ? actor!.username : 'Un utilisateur';
    final trackTitle = track?.title ?? 'un titre';
    final playlistTitle = playlist?.title ?? 'une playlist';
    return switch (type) {
      'new_follower' => '$who a commencé à te suivre',
      'new_track' => '$who a publié « $trackTitle »',
      'track_liked' => '$who a liké « $trackTitle »',
      'track_added_playlist' => '$who a ajouté « $trackTitle » à « $playlistTitle »',
      'import_track_done' => 'Ton import « $trackTitle » est prêt',
      'import_playlist_done' => 'Import de playlist terminé',
      _ => 'Notification',
    };
  }
}
