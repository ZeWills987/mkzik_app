import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source d'une track dans les résultats de recherche.
enum SearchPlatform { mkzik, youtube, soundcloud }

const _kPrefKey = 'search_platform_v2';

/// Plateforme active pour les résultats de recherche — switch single-select
/// (une seule à la fois), persisté en local. Mkzik par défaut.
class SearchFilterNotifier extends StateNotifier<SearchPlatform> {
  SearchFilterNotifier() : super(SearchPlatform.mkzik) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefKey);
    if (saved == null) return;
    for (final p in SearchPlatform.values) {
      if (p.name == saved) {
        state = p;
        return;
      }
    }
  }

  Future<void> select(SearchPlatform platform) async {
    state = platform;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, platform.name);
  }
}

final searchFilterProvider = StateNotifierProvider<SearchFilterNotifier, SearchPlatform>(
  (ref) => SearchFilterNotifier(),
);
