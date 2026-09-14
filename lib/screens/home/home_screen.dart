import 'package:flutter/material.dart';
import '../../providers/notifications_provider.dart';
import '../../widgets/mini_player.dart' show miniPlayerListPadding;
import '../../widgets/tappable.dart';
import '../notifications/notifications_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/player_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/imports_provider.dart';
import '../../providers/paginated_tracks_provider.dart';
import '../../config/api_config.dart';
import '../../widgets/track_card.dart';
import '../../widgets/track_cover.dart';
import '../../theme/app_theme.dart';
import '../track_list/track_list_screen.dart';
import '../../widgets/empty_state.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsync = ref.watch(newsFeedProvider);
    final historyAsync = ref.watch(historyPlayProvider);
    final importsState = ref.watch(importsProvider);
    final ytAsync = ApiConfig.externalStream ? ref.watch(youtubeSuggestionsProvider) : null;
    final ytTopAsync = ApiConfig.externalStream ? ref.watch(youtubeTopProvider) : null;
    final scAsync = ApiConfig.externalStream ? ref.watch(soundcloudSuggestionsProvider) : null;

    // Données affichées (le repli démo éventuel est géré dans les providers)
    final tracks = newsAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
    final historyTracks = historyAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
    final Track? featured = tracks.isNotEmpty ? tracks.first : null;
    final isLoadingNews = newsAsync.isLoading;
    final isLoadingHistory = historyAsync.isLoading;
    final importTracks = importsState.tracks;
    final isLoadingImports = importsState.initialLoading;

    return SafeArea(
      child: RefreshIndicator(
        color: kAccent,
        backgroundColor: kSurface,
        onRefresh: () async {
          ref.invalidate(newsFeedProvider);
          ref.invalidate(historyPlayProvider);
          if (ApiConfig.externalStream) {
            ref.invalidate(youtubeSuggestionsProvider);
            ref.invalidate(youtubeTopProvider);
            ref.invalidate(soundcloudSuggestionsProvider);
          }
          await Future.wait([
            ref.read(newsFeedProvider.future),
            ref.read(historyPlayProvider.future),
            ref.read(importsProvider.notifier).refresh(),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header()),
            if (featured != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: _FeaturedBanner(track: featured),
                ),
              ),
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Dernière sortie',
                onSeeAll: () => TrackListScreen.open(
                  context,
                  title: 'Dernière sortie',
                  provider: newsFeedPagedProvider,
                  showPublishedAt: true,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 272,
                child: isLoadingNews
                    ? const _LoadingRow(height: 272)
                    : tracks.isEmpty
                        ? const EmptyState(
                            icon: Icons.newspaper_rounded,
                            title: 'Aucune nouveauté',
                            subtitle: 'Les nouvelles sorties apparaîtront ici.',
                            fullScreen: false,
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: tracks.length,
                            separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                            itemBuilder: (_, i) => TrackCard(track: tracks[i], queue: tracks, showPublishedAt: true),
                          ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Historique',
                onSeeAll: () => TrackListScreen.open(
                  context,
                  title: 'Historique',
                  provider: historyPlayPagedProvider,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 250,
                child: isLoadingHistory
                    ? const _LoadingRow(height: 250)
                    : historyTracks.isEmpty
                        ? const EmptyState(
                            icon: Icons.history_rounded,
                            title: 'Aucun historique',
                            subtitle: 'Lance ta première écoute pour la retrouver ici.',
                            fullScreen: false,
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: historyTracks.length,
                            separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                            itemBuilder: (_, i) => TrackCard(track: historyTracks[i], queue: historyTracks),
                          ),
              ),
            ),
            // Suggestions YouTube Music (uniquement si streaming externe activé)
            if (ytAsync != null) ..._suggestionsSection(
              context,
              ref,
              title: 'Pour vous',
              icon: Icons.music_video_outlined,
              tracksAsync: ytAsync,
              pagedProvider: youtubeSuggestionsPagedProvider,
            ),
            // Top YouTube Music — charts mondiaux (uniquement si streaming externe activé)
            if (ytTopAsync != null) ..._suggestionsSection(
              context,
              ref,
              title: 'Top YouTube Music',
              icon: Icons.bar_chart_rounded,
              tracksAsync: ytTopAsync,
              pagedProvider: youtubeTopPagedProvider,
            ),
            // Top SoundCloud (uniquement si streaming externe activé)
            if (scAsync != null) ..._suggestionsSection(
              context,
              ref,
              title: 'Top SoundCloud',
              icon: Icons.cloud_outlined,
              tracksAsync: scAsync,
              pagedProvider: soundcloudSuggestionsPagedProvider,
            ),
            if (importTracks.isNotEmpty || isLoadingImports) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Importé',
                  onSeeAll: importTracks.isNotEmpty
                      ? () => TrackListScreen.open(
                            context,
                            title: 'Importé',
                            provider: importsPagedProvider,
                          )
                      : null,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 250,
                  child: isLoadingImports
                      ? const _LoadingRow(height: 250)
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: importTracks.length,
                          separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => TrackCard(track: importTracks[i], queue: importTracks),
                        ),
                ),
              ),
            ],
            // Espace de fin : + hauteur du player flottant s'il est affiché
            SliverToBoxAdapter(child: SizedBox(height: 32 + miniPlayerListPadding(ref))),
          ],
        ),
      ),
    );
  }
}

// Génère header + liste pour une section de suggestions (YouTube / SoundCloud)
List<Widget> _suggestionsSection(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required IconData icon,
  required AsyncValue<List<Track>> tracksAsync,
  required AutoDisposeStateNotifierProvider<PagedTracksNotifier, PagedTracksState> pagedProvider,
}) {
  final tracks = tracksAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
  final loading = tracksAsync.isLoading;
  if (!loading && tracks.isEmpty) return const [];
  return [
    SliverToBoxAdapter(
      child: _SectionHeader(
        title: title,
        onSeeAll: tracks.isNotEmpty
            ? () => TrackListScreen.open(context, title: title, provider: pagedProvider)
            : null,
      ),
    ),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 250,
        child: loading
            ? const _LoadingRow(height: 250)
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) => TrackCard(track: tracks[i], queue: tracks),
              ),
      ),
    ),
  ];
}

// Indicateur de chargement horizontal simple
class _LoadingRow extends StatelessWidget {
  final double height;
  const _LoadingRow({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(child: CircularProgressIndicator(color: kAccent)),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          // Cercle violet avant le logo
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          // Logo MKZIK
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              children: [
                TextSpan(text: 'MK', style: TextStyle(color: kTextPrimary)),
                TextSpan(text: 'ZIK', style: TextStyle(color: kAccent)),
              ],
            ),
          ),
          const Spacer(),
          // Cloche notifications : badge non-lues + ouverture du centre
          Consumer(builder: (context, ref, _) {
            final unread = ref.watch(unreadNotificationsProvider);
            return Tappable(
              onTap: () => NotificationsScreen.open(context),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF3A3A5A), width: 1.5),
                    ),
                    child: const Icon(Icons.notifications_outlined, color: kTextPrimary, size: 20),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: kAccent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: kBg, width: 1.5),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(width: 10),
          // Avatar profil (cercle violet)
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// ── Bannière titre en vedette ─────────────────────────────────────────────────

class _FeaturedBanner extends ConsumerWidget {
  final Track track;
  const _FeaturedBanner({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        // Fond sombre légèrement teinté
        color: const Color(0xFF0E0E1E),
      ),
      child: Stack(
        children: [
          // Lueur violet en haut à droite
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [kAccent.withValues(alpha:0.25), Colors.transparent],
                ),
              ),
            ),
          ),

          // Contenu principal
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colonne gauche : textes + bouton
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge "TITRE EN VEDETTE"
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: kAccent.withValues(alpha:0.6), width: 1),
                          color: kAccent.withValues(alpha:0.08),
                        ),
                        child: const Text(
                          'TITRE EN VEDETTE',
                          style: TextStyle(
                            color: kAccentLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.artist}  ·  ${track.durationFormatted}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kTextSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      // Bouton Écouter
                      Tappable(
                        onTap: () => ref.read(playerProvider.notifier).playTrack(track),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Écouter',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Cover flottante à droite — carte inclinée
                Align(
                  alignment: Alignment.centerRight,
                  child: Transform.rotate(
                    angle: 0.12, // légère inclinaison
                    child: _FloatingAlbumCard(track: track),
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

// Carte album flottante avec dégradé et ombre
class _FloatingAlbumCard extends StatelessWidget {
  final Track track;
  const _FloatingAlbumCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 115,
      height: 115,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: track.gradientColors.first.withValues(alpha:0.5), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Vraie thumbnail réseau (sinon dégradé + sphère via TrackCover)
            TrackCover(track: track, size: 115, radius: 16),
            // Voile sombre en bas pour la lisibilité du texte
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  ),
                ),
              ),
            ),
            // Texte en bas
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    track.artist,
                    style: TextStyle(color: Colors.white.withValues(alpha:0.7), fontSize: 9),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ── En-tête de section ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (onSeeAll != null)
            Tappable(
              onTap: onSeeAll,
              child: const Text('Voir tout', style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

