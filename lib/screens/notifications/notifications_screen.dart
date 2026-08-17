import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/notification.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../navigation/app_nav.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../library/playlist_detail_screen.dart';

/// Centre de notifications : liste paginée au scroll, tap = lu + navigation,
/// glisser = supprimer, action « tout marquer lu ».
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Notifications',
            style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: notifier.markAllRead,
              child: const Text('Tout lire',
                  style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _buildBody(context, ref, state, notifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    NotificationsState state,
    NotificationsNotifier notifier,
  ) {
    if (state.initialLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }
    if (state.error && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Notifications indisponibles',
                style: TextStyle(color: kTextSecondary, fontSize: 14)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: notifier.refresh,
              child: const Text('Réessayer', style: TextStyle(color: kAccent)),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, color: kTextSecondary, size: 44),
            SizedBox(height: 12),
            Text('Aucune notification pour le moment',
                style: TextStyle(color: kTextSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kAccent,
      backgroundColor: kSurface,
      onRefresh: notifier.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) notifier.loadMore();
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          addAutomaticKeepAlives: false,
          itemCount: state.items.length + (state.loadingMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.2),
                  ),
                ),
              );
            }
            final n = state.items[i];
            return Dismissible(
              key: ValueKey('notif-${n.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => notifier.delete(n),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: kError.withValues(alpha: 0.25),
                child: const Icon(Icons.delete_outline, color: kErrorText),
              ),
              child: _NotificationRow(
                notification: n,
                onTap: () => _onTap(context, ref, n),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Tap : marque lue puis navigue selon le contenu (cf. doc back) :
  /// track → page du son ; playlist → page playlist ; follower → profil.
  void _onTap(BuildContext context, WidgetRef ref, AppNotification n) {
    ref.read(notificationsProvider.notifier).markRead(n);
    final track = n.track;
    final playlist = n.playlist;
    if (track != null) {
      appNav.openTrack(
        context,
        Track(
          id: '${track.id}',
          apiId: track.id,
          title: track.title,
          artist: n.actor?.username ?? '',
          coverUrl: track.thumbnails ?? '',
          pageUrl: track.url,
          duration: Duration.zero,
          audioUrl: '',
        ),
      );
    } else if (playlist != null) {
      PlaylistDetailScreen.open(context, Playlist(id: playlist.id, title: playlist.title));
    } else if (n.type == 'new_follower' && n.actor != null) {
      appNav.openProfile(context, n.actor!.username);
    }
  }
}

class _NotificationRow extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  const _NotificationRow({required this.notification, required this.onTap});

  IconData get _typeIcon => switch (notification.type) {
        'new_follower' => Icons.person_add_alt_1_rounded,
        'new_track' => Icons.music_note_rounded,
        'track_liked' => Icons.favorite_rounded,
        'track_added_playlist' => Icons.playlist_add_rounded,
        'import_track_done' || 'import_playlist_done' => Icons.cloud_done_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final avatar = mediaUrl(n.actor?.avatar ?? '');
    final thumb = mediaUrl(n.track?.thumbnails ?? '');

    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.isRead ? Colors.transparent : kAccent.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Vignette : avatar de l'acteur, sinon cover du titre, sinon icône type
            _Leading(avatar: avatar, thumb: thumb, icon: _typeIcon, username: n.actor?.username),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.label,
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 13.5,
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (n.createdAt != null) ...[
                    const SizedBox(height: 3),
                    Text(timeAgoFr(n.createdAt!),
                        style: const TextStyle(color: kTextSecondary, fontSize: 11.5)),
                  ],
                ],
              ),
            ),
            // Point non-lu
            if (!n.isRead)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final String avatar;
  final String thumb;
  final IconData icon;
  final String? username;
  const _Leading({required this.avatar, required this.thumb, required this.icon, this.username});

  @override
  Widget build(BuildContext context) {
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 21,
        backgroundColor: kUserBlue,
        backgroundImage: CachedNetworkImageProvider(avatar,
            maxWidth: (42 * MediaQuery.devicePixelRatioOf(context)).round()),
      );
    }
    if (thumb.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: thumb,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          memCacheWidth: (42 * MediaQuery.devicePixelRatioOf(context)).round(),
          errorWidget: (_, _, _) => _fallback(),
        ),
      );
    }
    if (username?.isNotEmpty == true) {
      return CircleAvatar(
        radius: 21,
        backgroundColor: kUserBlue,
        child: Text(username![0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: kAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Icon(icon, color: kAccent, size: 20),
      );
}
