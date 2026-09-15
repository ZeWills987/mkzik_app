import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/artist_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/artist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/notice_banner.dart';
import '../../widgets/track_tile.dart';

/// Écran de tracks d'un artiste externe (YouTube / SoundCloud non importé).
/// Entrée : [artistUrl] = URL du profil artiste, [artistName] = nom d'affichage.
class ArtistTracksScreen extends ConsumerWidget {
  final String artistUrl;
  final String artistName;

  const ArtistTracksScreen({
    super.key,
    required this.artistUrl,
    required this.artistName,
  });

  static Future<void> open(BuildContext context, {required String artistUrl, required String artistName}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistTracksScreen(artistUrl: artistUrl, artistName: artistName),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(artistTracksProvider(artistUrl));
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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: kBg,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: kTextPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              artistName.isNotEmpty ? artistName : 'Artiste',
              style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          resultAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: kAccent)),
            ),
            error: (_, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: kTextSecondary, size: 40),
                    const SizedBox(height: 12),
                    const Text('Impossible de charger les ziks', style: TextStyle(color: kTextSecondary)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(artistTracksProvider(artistUrl)),
                      child: const Text('Réessayer', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            data: (result) {
              final tracks = result.tracks;
              final artist = result.artist;
              return SliverMainAxisGroup(
                slivers: [
                  if (artist != null)
                    SliverToBoxAdapter(child: _ArtistHeader(artist: artist)),
                  if (tracks.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text('Aucune zik trouvée', style: TextStyle(color: kTextSecondary)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => TrackTile(track: tracks[i], queue: tracks),
                          childCount: tracks.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  final ArtistPreview artist;
  const _ArtistHeader({required this.artist});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          // Avatar
          ClipOval(
            child: artist.thumbnail.isNotEmpty
                ? Image.network(
                    artist.thumbnail,
                    width: 64, height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(),
                  )
                : _avatarFallback(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name.isNotEmpty ? artist.name : artistName,
                  style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist.subscribers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    artist.subscribers,
                    style: const TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get artistName => artist.name;

  Widget _avatarFallback() => Container(
        width: 64, height: 64,
        color: kSurface,
        child: const Icon(Icons.person, color: kTextSecondary, size: 32),
      );
}
