import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/favourites_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favouritesProvider);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: kAccent,
          backgroundColor: kSurface,
          onRefresh: () async {
            ref.invalidate(favouritesProvider);
            await ref.read(favouritesProvider.future);
          },
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: kAccent)),
            error: (_, _) => _MessageState(
              physics: const AlwaysScrollableScrollPhysics(),
              icon: Icons.error_outline,
              title: 'Erreur de chargement',
              subtitle: 'Tire vers le bas pour réessayer.',
            ),
            data: (tracks) => CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _Header(count: tracks.length)),
                if (tracks.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MessageState(
                      icon: Icons.favorite_border,
                      title: 'Aucun favori',
                      subtitle: 'Like des Ziks pour les retrouver ici.',
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final track = tracks[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TrackResultRow(
                            track: track,
                            onTap: () =>
                                ref.read(playerProvider.notifier).playTrack(track, queue: tracks),
                            onMenu: () => showTrackActionsSheet(context, ref, track),
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
}

// En-tête : titre + compteur de favoris
class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ma librairie',
              style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.favorite, color: kAccent, size: 15),
              const SizedBox(width: 6),
              Text(
                count == 0 ? 'Favoris' : '$count ${count > 1 ? 'favoris' : 'favori'}',
                style: const TextStyle(color: kTextSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// État vide / erreur, centré
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ScrollPhysics? physics;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: kTextSecondary, size: 54),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSecondary, fontSize: 13)),
      ],
    );

    // Quand utilisé hors sliver (état d'erreur), on garde le pull-to-refresh.
    if (physics != null) {
      return ListView(
        physics: physics,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          content,
        ],
      );
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: content);
  }
}
