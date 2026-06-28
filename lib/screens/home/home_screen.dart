import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../models/search_user.dart';
import '../../providers/player_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/paginated_tracks_provider.dart';
import '../../widgets/track_card.dart';
import '../../widgets/track_cover.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../track_list/track_list_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsync = ref.watch(newsFeedProvider);
    final historyAsync = ref.watch(historyPlayProvider);
    final suggestionsAsync = ref.watch(globalSuggestionsProvider);
    final trendingAsync = ref.watch(trendingUsersProvider);

    // Données affichées (le repli démo éventuel est géré dans les providers)
    final tracks = newsAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
    final historyTracks = historyAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
    final suggestionTracks = suggestionsAsync.maybeWhen(data: (d) => d, orElse: () => const <Track>[]);
    final artists = trendingAsync.maybeWhen(data: (d) => d, orElse: () => const <SearchUser>[]);
    final Track? featured = tracks.isNotEmpty ? tracks.first : null;
    final isLoadingNews = newsAsync.isLoading;
    final isLoadingHistory = historyAsync.isLoading;
    final isLoadingSuggestions = suggestionsAsync.isLoading;
    final isLoadingTrending = trendingAsync.isLoading;

    return SafeArea(
      child: RefreshIndicator(
        color: kAccent,
        backgroundColor: kSurface,
        onRefresh: () async {
          ref.invalidate(newsFeedProvider);
          ref.invalidate(historyPlayProvider);
          ref.invalidate(globalSuggestionsProvider);
          ref.invalidate(trendingUsersProvider);
          await Future.wait([
            ref.read(newsFeedProvider.future),
            ref.read(historyPlayProvider.future),
            ref.read(globalSuggestionsProvider.future),
            ref.read(trendingUsersProvider.future),
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
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: tracks.length,
                        separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => TrackCard(track: tracks[i], queue: tracks, showPublishedAt: true),
                      ),
              ),
            ),
            // Suggestions globales (mix top YouTube + top SoundCloud).
            // Masquée si vide (et pas en cours de chargement) — source externe.
            if (isLoadingSuggestions || suggestionTracks.isNotEmpty) ...[
              SliverToBoxAdapter(child: _SectionHeader(title: 'Suggestions', onSeeAll: () {})),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 250,
                  child: isLoadingSuggestions
                      ? const _LoadingRow(height: 250)
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: suggestionTracks.length,
                          separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                          itemBuilder: (_, i) => TrackCard(track: suggestionTracks[i], queue: suggestionTracks),
                        ),
                ),
              ),
            ],
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
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: historyTracks.length,
                        separatorBuilder: (ctx, idx) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => TrackCard(track: historyTracks[i], queue: historyTracks),
                      ),
              ),
            ),
            SliverToBoxAdapter(child: _SectionHeader(title: 'Artistes recommandés', onSeeAll: () {})),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: isLoadingTrending
                    ? const _LoadingRow(height: 120)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: artists.length,
                        separatorBuilder: (ctx, idx) => const SizedBox(width: 16),
                        itemBuilder: (_, i) => _ArtistAvatar(user: artists[i]),
                      ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
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
          // Bouton notification (contour)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3A3A5A), width: 1.5),
            ),
            child: const Icon(Icons.notifications_outlined, color: kTextPrimary, size: 20),
          ),
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
                      GestureDetector(
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
  final VoidCallback onSeeAll;
  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          GestureDetector(
            onTap: onSeeAll,
            child: const Text('Voir tout', style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Avatar artiste : avatar réseau ou sphère colorée + initiale ──────────────

class _ArtistAvatar extends StatelessWidget {
  final SearchUser user;
  const _ArtistAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    // Dégradé stable dérivé du nom (identité visuelle quand pas d'avatar)
    final colors = gradientForSeed(user.username.hashCode);
    final initial = user.username.isNotEmpty ? user.username[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => ProfileScreen.open(context, user.username),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  radius: 0.85,
                  colors: colors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors[0].withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: mediaUrl(user.avatarUrl).isNotEmpty
                  ? Image.network(
                      mediaUrl(user.avatarUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => _initial(initial),
                    )
                  : _initial(initial),
            ),
            const SizedBox(height: 8),
            Text(
              user.username,
              style: const TextStyle(color: kTextPrimary, fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _initial(String initial) => Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
        ),
      );
}
