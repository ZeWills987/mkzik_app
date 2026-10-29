import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import '../utils/logger.dart';

/// État du fil « Banger » (scroll infini paginé par curseur).
class BangerState {
  final List<Track> items;
  final bool initialLoading; // 1er chargement (écran vide)
  final bool loadingMore; // chargement de la page suivante
  final bool ended; // fin du fil (next_cursor null ou page vide)
  final Object? error; // erreur du 1er chargement uniquement

  const BangerState({
    this.items = const [],
    this.initialLoading = false,
    this.loadingMore = false,
    this.ended = false,
    this.error,
  });

  BangerState copyWith({
    List<Track>? items,
    bool? initialLoading,
    bool? loadingMore,
    bool? ended,
    Object? error,
    bool clearError = false,
  }) {
    return BangerState(
      items: items ?? this.items,
      initialLoading: initialLoading ?? this.initialLoading,
      loadingMore: loadingMore ?? this.loadingMore,
      ended: ended ?? this.ended,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Charge le fil `GET api/feed` page par page. Le curseur est opaque : on le
/// renvoie tel quel. Le chargement est paresseux ([ensureLoaded]) pour ne pas
/// solliciter l'API tant que l'onglet n'a jamais été ouvert.
class BangerNotifier extends StateNotifier<BangerState> {
  BangerNotifier() : super(const BangerState());

  static const _pageSize = 20;

  String? _cursor;
  bool _started = false;
  Future<List<Track>>? _inflight; // page en cours : partagée entre appelants

  /// Premier chargement, une seule fois (les ouvertures suivantes de l'onglet
  /// réutilisent la liste en mémoire).
  void ensureLoaded() {
    if (_started) return;
    _started = true;
    loadInitial();
  }

  /// (Re)charge depuis la première page (pull-to-refresh, ou réessai).
  Future<void> loadInitial() async {
    _started = true;
    _cursor = null;
    state = const BangerState(initialLoading: true);
    try {
      final page = await TrackService.getFeed(limit: _pageSize);
      _cursor = page.nextCursor;
      state = BangerState(items: _dedup(const [], page.items), ended: page.nextCursor == null);
    } catch (e) {
      mkLog('Mkzik 🔥 Banger : chargement impossible : $e');
      state = BangerState(ended: true, error: e);
    }
  }

  /// Charge la page suivante et renvoie les titres ajoutés ([] si rien). Les
  /// appels simultanés (écran + file du player) partagent la même requête.
  Future<List<Track>> loadMore() {
    if (state.initialLoading || state.ended) return Future.value(const []);
    return _inflight ??= _fetchNext().whenComplete(() => _inflight = null);
  }

  Future<List<Track>> _fetchNext() async {
    state = state.copyWith(loadingMore: true);
    try {
      final page = await TrackService.getFeed(limit: _pageSize, cursor: _cursor);
      _cursor = page.nextCursor;
      final added = _dedup(state.items, page.items);
      // Page vide : fin du fil, même si un curseur est renvoyé (évite toute boucle).
      state = state.copyWith(
        items: [...state.items, ...added],
        loadingMore: false,
        ended: page.nextCursor == null || page.items.isEmpty,
      );
      return added;
    } catch (e) {
      mkLog('Mkzik 🔥 Banger : page suivante impossible : $e');
      // Pas de boucle de retry : on réessaiera au prochain scroll vers la fin.
      state = state.copyWith(loadingMore: false);
      return const [];
    }
  }

  // Le serveur évite les doublons entre pages ; on se protège quand même.
  static List<Track> _dedup(List<Track> existing, List<Track> page) {
    final seen = {for (final t in existing) t.id};
    return [
      for (final t in page)
        if (seen.add(t.id)) t,
    ];
  }
}

final bangerProvider = StateNotifierProvider<BangerNotifier, BangerState>((ref) => BangerNotifier());
