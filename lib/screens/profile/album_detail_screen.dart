import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/album.dart';
import '../../providers/albums_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/mini_player.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final int albumId;
  final String albumTitle;
  final String coverUrl;

  const AlbumDetailScreen({
    super.key,
    required this.albumId,
    required this.albumTitle,
    this.coverUrl = '',
  });

  static Future<void> open(BuildContext context, Album album) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          albumId: album.id,
          albumTitle: album.title,
          coverUrl: album.coverUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumDetailProvider(albumId));
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    return Scaffold(
      backgroundColor: kBg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [if (hasTrack) const MiniPlayer()],
        ),
      ),
      body: async.when(
        loading: () => _LoadingView(title: albumTitle, coverUrl: coverUrl),
        error: (err, st) => const Center(
          child: Text('Impossible de charger l\'album', style: TextStyle(color: kTextSecondary)),
        ),
        data: (album) {
          if (album == null) {
            return const Center(
              child: Text('Album introuvable', style: TextStyle(color: kTextSecondary)),
            );
          }
          return _AlbumView(album: album);
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String title;
  final String coverUrl;
  const _LoadingView({required this.title, required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _AlbumAppBar(title: title, coverUrl: coverUrl, trackCount: null, totalDuration: null),
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator(color: kAccent)),
        ),
      ],
    );
  }
}

class _AlbumView extends ConsumerWidget {
  final Album album;
  const _AlbumView({required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);

    return CustomScrollView(
      slivers: [
        _AlbumAppBar(
          title: album.title,
          coverUrl: album.coverUrl,
          trackCount: album.displayTrackCount,
          totalDuration: album.tracks.isNotEmpty ? album.totalDuration : null,
          onPlayAll: album.tracks.isNotEmpty
              ? () => notifier.playTrack(album.tracks.first, queue: album.tracks)
              : null,
        ),
        if (album.description.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                album.description,
                style: const TextStyle(color: kTextSecondary, fontSize: 13),
              ),
            ),
          ),
        if (album.tracks.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text('Aucun titre dans cet album', style: TextStyle(color: kTextSecondary)),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final track = album.tracks[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: kTextSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: TrackResultRow(
                          track: track,
                          onTap: () => notifier.playTrack(track, queue: album.tracks),
                          onMenu: () => showTrackActionsSheet(context, ref, track),
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: album.tracks.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _AlbumAppBar extends StatelessWidget {
  final String title;
  final String coverUrl;
  final int? trackCount;
  final Duration? totalDuration;
  final VoidCallback? onPlayAll;

  const _AlbumAppBar({
    required this.title,
    required this.coverUrl,
    required this.trackCount,
    required this.totalDuration,
    this.onPlayAll,
  });

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '$m min';
  }

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: kBg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: kTextPrimary, size: 20),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Cover en fond flouté
            if (coverUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.55),
                colorBlendMode: BlendMode.darken,
              )
            else
              Container(color: kSurface),
            // Dégradé bas
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, kBg],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            // Pochette centrée + infos
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Cover(url: coverUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        if (trackCount != null)
                          Text(
                            [
                              '$trackCount titre${trackCount! > 1 ? 's' : ''}',
                              if (totalDuration != null) _fmtDuration(totalDuration!),
                            ].join(' · '),
                            style: const TextStyle(color: kTextSecondary, fontSize: 12),
                          ),
                        if (onPlayAll != null) ...[
                          const SizedBox(height: 10),
                          _PlayButton(onTap: onPlayAll!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String url;
  const _Cover({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 100,
        height: 100,
        child: url.isNotEmpty
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : Container(
                color: kSurface,
                child: const Icon(Icons.album, color: kTextSecondary, size: 40),
              ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PlayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(99)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text('Lire tout', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
