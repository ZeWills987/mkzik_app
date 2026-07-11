import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source d'une track dans les résultats de recherche.
enum SearchPlatform { mkzik, youtube, soundcloud }

const _kPrefKey = 'search_platforms_v1';

/// Ensemble des plateformes actives pour filtrer les résultats de recherche.
/// Persisté en local (shared_preferences) — au moins une plateforme reste
/// toujours active pour éviter une recherche vide.
class SearchFilterNotifier extends StateNotifier<Set<SearchPlatform>> {
  SearchFilterNotifier() : super(SearchPlatform.values.toSet()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kPrefKey);
    if (saved == null || saved.isEmpty) return;
    final restored = saved
        .map((s) => SearchPlatform.values.where((p) => p.name == s))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => matches.first)
        .toSet();
    if (restored.isNotEmpty) state = restored;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKey, state.map((p) => p.name).toList());
  }

  /// Bascule une plateforme — ignoré si c'est la dernière active.
  void toggle(SearchPlatform platform) {
    if (state.contains(platform)) {
      if (state.length == 1) return; // toujours ≥1 active
      state = {...state}..remove(platform);
    } else {
      state = {...state, platform};
    }
    _persist();
  }

  bool isActive(SearchPlatform platform) => state.contains(platform);
}

final searchFilterProvider = StateNotifierProvider<SearchFilterNotifier, Set<SearchPlatform>>(
  (ref) => SearchFilterNotifier(),
);
