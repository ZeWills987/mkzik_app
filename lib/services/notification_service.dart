import '../config/api_config.dart';
import '../models/notification.dart';
import 'api_client.dart';

/// Résultat d'une page de notifications (la liste ET le compteur non-lues,
/// renvoyés ensemble par l'API — pas besoin d'appeler la route badge en plus).
class NotificationsPage {
  final List<AppNotification> notifications;
  final int unreadCount;
  const NotificationsPage({this.notifications = const [], this.unreadCount = 0});
}

/// Accès aux routes notifications (toutes authentifiées JWT).
class NotificationService {
  /// `GET api/notifications?limit=&offset=&unread_only=` → liste + unread_count.
  static Future<NotificationsPage?> list({int limit = 20, int offset = 0, bool unreadOnly = false}) async {
    final res = await ApiClient.getUri(_api('api/notifications', {
      'limit': '$limit',
      'offset': '$offset',
      if (unreadOnly) 'unread_only': 'true',
    }));
    final data = res.orElse(null);
    if (data is! Map) return null; // null = erreur réseau (≠ liste vide)
    final list = data['notifications'];
    return NotificationsPage(
      notifications: (list is List ? list : const [])
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList(),
      unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// `GET api/notifications/unread-count` → badge seul (route légère à poller).
  static Future<int?> unreadCount() async {
    final res = await ApiClient.getUri(_api('api/notifications/unread-count'));
    final data = res.orElse(null);
    if (data is! Map) return null;
    return (data['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// `PATCH api/notifications/{id}/read` → marque une notif lue.
  static Future<bool> markRead(int id) async {
    final res = await ApiClient.patchUri(_api('api/notifications/$id/read'));
    return res.isOk;
  }

  /// `POST api/notifications/read-all` → tout marquer lu.
  static Future<bool> markAllRead() async {
    final res = await ApiClient.postUri(_api('api/notifications/read-all'));
    return res.isOk;
  }

  /// `DELETE api/notifications/{id}` → supprime (204).
  static Future<bool> delete(int id) async {
    final res = await ApiClient.deleteUri(_api('api/notifications/$id'));
    return res.isOk;
  }

  static Uri _api(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
}
