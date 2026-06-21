import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/notice_provider.dart';
import '../../services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/notice_banner.dart';
import '../../widgets/mini_player.dart';

/// Détail d'une playlist : ses titres, lecture, retrait (swipe).
class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  static Future<void> open(BuildContext context, Playlist playlist) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: playlist)),
    );
  }

  Future<bool> _removeTrack(WidgetRef ref, Track t) async {
    if (t.apiId == null) return false;
    final ok = await PlaylistService.removeTrack(playlist.id, t.apiId!);
    final notifier = ref.read(noticeProvider.notifier);
    if (ok) {
      ref.invalidate(playlistTracksProvider(playlist.id));
      ref.invalidate(playlistsProvider);
      notifier.show('Retiré de la playlist');
    } else {
      notifier.show('Suppression impossible');
    }
    return ok;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistTracksProvider(playlist.id));
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    return Scaffold(
      backgroundColor: kBg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [const BottomBanners(), if (hasTrack) const MiniPlayer()],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: kAccent,
          backgroundColor: kSurface,
          onRefresh: () async {
            ref.invalidate(playlistTracksProvider(playlist.id));
            await ref.read(playlistTracksProvider(playlist.id).future);
          },
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: kAccent)),
            error: (_, _) => _scrollMessage('Playlist indisponible', 'Tire vers le bas pour réessayer.'),
            data: (tracks) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    title: playlist.title,
                    count: tracks.length,
                    onBack: () => Navigator.of(context).maybePop(),
                    onPlayAll: tracks.isEmpty
                        ? null
                        : () => ref.read(playerProvider.notifier).playTrack(tracks.first, queue: tracks),
                  ),
                ),
                if (tracks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _centerMessage('Playlist vide', 'Ajoute des titres depuis le menu « … » d\'un Zik.'),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final track = tracks[i];
                        return Dismissible(
                          key: ValueKey('pl-${playlist.id}-${track.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _removeTrack(ref, track),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: kError.withValues(alpha: 0.25),
                            child: const Icon(Icons.delete_outline, color: kErrorText),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TrackResultRow(
                              track: track,
                              onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: tracks),
                              onMenu: () => showTrackActionsSheet(context, ref, track),
                            ),
                          ),
                        );
                      },
                      childCount: tracks.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollMessage(String title, String subtitle) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          _centerMessage(title, subtitle),
        ],
      );

  Widget _centerMessage(String title, String subtitle) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.queue_music, color: kTextSecondary, size: 54),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onBack;
  final VoidCallback? onPlayAll;
  const _Header({required this.title, required this.count, required this.onBack, this.onPlayAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: kTextPrimary),
            onPressed: onBack,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.w800),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(count <= 1 ? '$count titre' : '$count titres',
                          style: const TextStyle(color: kTextSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (onPlayAll != null)
                  GestureDetector(
                    onTap: onPlayAll,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [kAccentLight, kAccent]),
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
