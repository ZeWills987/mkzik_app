import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import '../services/suggestion_service.dart';

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
///
/// [totalGetter] est optionnel : quand il retourne un entier (ex. depuis
/// `X-Total-Count`), la pagination s'arrête exactement au bon moment sans
/// requête vide de trop. Sans lui, on se rabat sur l'heuristique
/// `page.length >= pageSize`.
class PagedTracksNotifier extends StateNotifier<PagedTracksState> {
  final TrackPageFetcher _fetch;
  final int pageSize;
  final int? Function()? _getTotal;

  PagedTracksNotifier(this._fetch, {this.pageSize = 20, int? Function()? totalGetter})
      : _getTotal = totalGetter,
        super(const PagedTracksState()) {
    loadInitial();
  }

  /// Chargeur de pages, réutilisable par le player pour étendre sa file
  /// indépendamment de la durée de vie de ce notifier.
  TrackPageFetcher get fetcher => _fetch;

  bool _hasMore(List<Track> allTracks, List<Track> lastPage) {
    final total = _getTotal?.call();
    if (total != null) return allTracks.length < total;
    return lastPage.length >= pageSize;
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
        hasMore: _hasMore(page, page),
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
      final allTracks = [...state.tracks, ...page];
      state = state.copyWith(
        tracks: allTracks,
        loadingMore: false,
        hasMore: _hasMore(allTracks, page),
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

/// "Historique" paginé → `GET api/history/tracks?limit=&offset=`.
final historyPlayPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  return PagedTracksNotifier(
    ({required int limit, required int offset}) => TrackService.getHistoryPlay(limit: limit, offset: offset),
  );
});

/// "Suggestions YouTube" paginées — une seule page (Python ne supporte pas l'offset).
final youtubeSuggestionsPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  bool fetched = false;
  return PagedTracksNotifier(
    ({required int limit, required int offset}) async {
      if (fetched || offset > 0) return [];
      fetched = true;
      final hasJwt = ApiConfig.token?.isNotEmpty ?? false;
      if (hasJwt) {
        final personal = await SuggestionService.youtubePersonal(limit: 30);
        if (personal.isNotEmpty) return personal;
      }
      return SuggestionService.youtubeHome(limit: 30);
    },
    pageSize: 30,
  );
});

/// "Top YouTube Music" paginé — une seule page (charts mondiaux).
final youtubeTopPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  bool fetched = false;
  return PagedTracksNotifier(
    ({required int limit, required int offset}) async {
      if (fetched || offset > 0) return [];
      fetched = true;
      return SuggestionService.youtubeTop(limit: 30);
    },
    pageSize: 30,
  );
});

/// "Suggestions SoundCloud" paginées — une seule page.
final soundcloudSuggestionsPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  bool fetched = false;
  return PagedTracksNotifier(
    ({required int limit, required int offset}) async {
      if (fetched || offset > 0) return [];
      fetched = true;
      return SuggestionService.soundcloudTop(limit: 30);
    },
    pageSize: 30,
  );
});
