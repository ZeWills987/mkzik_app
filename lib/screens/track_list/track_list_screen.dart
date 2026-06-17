import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/paginated_tracks_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/mini_player.dart';

/// Page "Voir tout" générique avec **chargement dynamique au scroll**
/// (pagination) : on ne charge qu'une page de titres à la fois, puis les
/// suivantes quand on approche du bas — évite de tout charger d'un coup.
///
/// Réutilisable pour "Dernière sortie", "Historique", etc. — seule la source
/// paginée change (passée via [provider]).
class TrackListScreen extends ConsumerStatefulWidget {
  final String title;
  final AutoDisposeStateNotifierProvider<PagedTracksNotifier, PagedTracksState> provider;
  final bool showPublishedAt; // affiche "il y a X" (date de sortie) si dispo

  const TrackListScreen({
    super.key,
    required this.title,
    required this.provider,
    this.showPublishedAt = false,
  });

  /// Helper de navigation.
  static Future<void> open(
    BuildContext context, {
    required String title,
    required AutoDisposeStateNotifierProvider<PagedTracksNotifier, PagedTracksState> provider,
    bool showPublishedAt = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackListScreen(title: title, provider: provider, showPublishedAt: showPublishedAt),
      ),
    );
  }

  @override
  ConsumerState<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends ConsumerState<TrackListScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // Déclenche le chargement de la page suivante à ~400px du bas
  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(widget.provider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title,
            style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      // Mini-player persistant (l'AppShell est masqué par cette route poussée)
      bottomNavigationBar: hasTrack ? const SafeArea(top: false, child: MiniPlayer()) : null,
      body: _buildBody(state),
    );
  }

  Widget _buildBody(PagedTracksState state) {
    if (state.initialLoading) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }
    if (state.error != null && state.tracks.isEmpty) {
      return const Center(
        child: Text('Erreur de chargement', style: TextStyle(color: kTextSecondary)),
      );
    }
    if (state.tracks.isEmpty) {
      return const Center(
        child: Text('Aucun titre', style: TextStyle(color: kTextSecondary, fontSize: 14)),
      );
    }

    final tracks = state.tracks;
    return RefreshIndicator(
      color: kAccent,
      backgroundColor: kSurface,
      onRefresh: () => ref.read(widget.provider.notifier).refresh(),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // +1 ligne pour le loader de bas de liste tant qu'il reste des pages
        itemCount: tracks.length + (state.hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= tracks.length) {
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
          return TrackResultRow(
            track: tracks[i],
            showPublishedAt: widget.showPublishedAt,
            onTap: () => ref.read(playerProvider.notifier).playTrack(tracks[i], queue: tracks),
            onMenu: () => showTrackActionsSheet(context, ref, tracks[i]),
          );
        },
      ),
    );
  }
}
