import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/track.dart';
import '../services/track_service.dart';

/// Signature d'un chargeur de page de tracks (news, historique, …).
typedef TrackPageFetcher = Future<List<Track>> Function({required int limit, required int offset});

/// État d'une liste paginée chargée au fil du scroll.
class PagedTracksState {
  final List<Track> tracks;
  final bool initialLoading; // 1er chargement (écran vide)
  final bool loadingMore; // chargement de la page suivante
  final bool hasMore; // reste-t-il des pages à charger ?
  final Object? error; // erreur du 1er chargement uniquement

  const PagedTracksState({
    this.tracks = const [],
    this.initialLoading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  PagedTracksState copyWith({
    List<Track>? tracks,
    bool? initialLoading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return PagedTracksState(
      tracks: tracks ?? this.tracks,
      initialLoading: initialLoading ?? this.initialLoading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Charge les tracks par pages de [pageSize], pour un affichage dynamique
/// au scroll (évite de tout charger d'un coup quand il y a beaucoup de titres).
class PagedTracksNotifier extends StateNotifier<PagedTracksState> {
  final TrackPageFetcher _fetch;
  final int pageSize;

  PagedTracksNotifier(this._fetch, {this.pageSize = 20}) : super(const PagedTracksState()) {
    loadInitial();
  }

  /// Premier chargement (ou rechargement complet via pull-to-refresh).
  Future<void> loadInitial() async {
    state = const PagedTracksState(initialLoading: true);
    try {
      final page = await _fetch(limit: pageSize, offset: 0);
      // Repli démo si activé et résultat vide (dev sans backend)
      if (page.isEmpty && ApiConfig.useDemoData) {
        state = PagedTracksState(tracks: kDemoTracks, initialLoading: false, hasMore: false);
        return;
      }
      state = PagedTracksState(
        tracks: page,
        initialLoading: false,
        hasMore: page.length >= pageSize,
      );
    } catch (e) {
      state = PagedTracksState(initialLoading: false, hasMore: false, error: e);
    }
  }

  /// Charge la page suivante (appelé quand on approche du bas de la liste).
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.initialLoading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _fetch(limit: pageSize, offset: state.tracks.length);
      state = state.copyWith(
        tracks: [...state.tracks, ...page],
        loadingMore: false,
        hasMore: page.length >= pageSize,
      );
    } catch (_) {
      // On stoppe la pagination en cas d'erreur (pas de boucle de retry)
      state = state.copyWith(loadingMore: false, hasMore: false);
    }
  }

  Future<void> refresh() => loadInitial();
}

/// "Dernière sortie" paginée → `GET api/news?limit=&offset=`.
final newsFeedPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  return PagedTracksNotifier(
    ({required int limit, required int offset}) => TrackService.getNewsFeed(limit: limit, offset: offset),
  );
});

/// "Historique" paginé → `GET api/history_played?limit=&offset=`.
final historyPlayPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  return PagedTracksNotifier(
    ({required int limit, required int offset}) => TrackService.getHistoryPlay(limit: limit, offset: offset),
  );
});
