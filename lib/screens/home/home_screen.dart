import 'package:flutter/material.dart';
import '../../providers/notifications_provider.dart';
import '../../widgets/mini_player.dart' show miniPlayerListPadding;
import '../../widgets/profile_menu_button.dart';
import '../../widgets/tappable.dart';
import '../notifications/notifications_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/imports_provider.dart';
import '../../providers/paginated_tracks_provider.dart';
import '../../providers/profile_provider.dart';
import '../../config/api_config.dart';
import '../../services/track_service.dart';
import '../../widgets/track_card.dart';
import '../../widgets/release_card.dart';
import '../../theme/home_style.dart';
import 'home_hero.dart';
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
    final hasNewsError = newsAsync.hasError;
    final hasHistoryError = historyAsync.hasError;
    final importTracks = importsState.tracks;
    final isLoadingImports = importsState.initialLoading;

    return ColoredBox(
      color: kHomeBg,
      child: SafeArea(
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
            if (featured != null) SliverToBoxAdapter(child: HomeHero(tracks: tracks)),
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Dernière sortie',
                subtitle: 'Les nouveautés publiées cette semaine.',
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
                height: 250,
                child: isLoadingNews
                    ? const _LoadingRow(height: 250)
                    : hasNewsError
                        ? const EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Connexion indisponible',
                            subtitle: 'Tire vers le bas pour réessayer.',
                            fullScreen: false,
                          )
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
                            itemBuilder: (_, i) => ReleaseCard(
                              track: tracks[i],
                              queue: tracks,
                              fetchMore: ({required int limit, required int offset}) =>
                                  TrackService.getNewsFeed(limit: limit, offset: offset),
                            ),
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
                    : hasHistoryError
                        ? const EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Connexion indisponible',
                            subtitle: 'Tire vers le bas pour réessayer.',
                            fullScreen: false,
                          )
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
                            itemBuilder: (_, i) => TrackCard(
                              track: historyTracks[i],
                              queue: historyTracks,
                              fetchMore: ({required int limit, required int offset}) =>
                                  TrackService.getHistoryPlay(limit: limit, offset: offset),
                            ),
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
                          itemBuilder: (_, i) => TrackCard(
                            track: importTracks[i],
                            queue: importTracks,
                            fetchMore: ref.read(importsProvider.notifier).fetcher,
                          ),
                        ),
                ),
              ),
            ],
            // Espace de fin : + hauteur du player flottant s'il est affiché
            SliverToBoxAdapter(child: SizedBox(height: 32 + miniPlayerListPadding(ref))),
          ],
        ),
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
          // Logo MKZIK : même coupure « MK » / « ZIK » qu'avant, dans la nouvelle police
          RichText(
            text: TextSpan(
              style: homeDisplay(size: 26),
              children: const [
                TextSpan(text: 'MK', style: TextStyle(color: kHomeInk)),
                TextSpan(text: 'ZIK', style: TextStyle(color: kHomeViolet)),
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
          // Avatar profil : même menu (modifier, YouTube, publier, paramètres…)
          // que sur l'onglet Profil.
          Consumer(builder: (context, ref, _) {
            final username = ref.watch(authProvider.select((s) => s.username));
            if (username == null || username.isEmpty) {
              return const CircleAvatar(radius: 19, backgroundColor: kAccent);
            }
            final profileAsync = ref.watch(profileProvider(username));
            return profileAsync.when(
              loading: () => const CircleAvatar(radius: 19, backgroundColor: kAccent),
              error: (_, _) => const CircleAvatar(radius: 19, backgroundColor: kAccent),
              data: (profile) => ProfileMenuButton(profile: profile, size: 38),
            );
          }),
        ],
      ),
    );
  }
}

// ── En-tête de section ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, this.subtitle, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: homeDisplay(size: 26, weight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: homeBody(size: 13, weight: FontWeight.w400, color: kHomeInkSoft)),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            Tappable(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('VOIR TOUT', style: homeMono(size: 11, color: kHomeVioletSoft, spacing: 1.6)),
              ),
            ),
        ],
      ),
    );
  }
}

