import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';
import '../../models/track.dart';
import '../../models/search_user.dart';
import '../../services/track_service.dart';

/// Onglets de résultats (cf. maquette : ZIK / USER / EXTERNE)
enum SearchTab { zik, user, external }

/// Tri des résultats (cf. maquette : PERTINENCE / DATE / ÉCOUTES)
enum SearchSort { relevance, date, plays }

/// Résultat agrégé d'une recherche.
class SearchResults {
  final List<Track> zik;
  final List<SearchUser> users;
  final List<Track> external;

  const SearchResults({this.zik = const [], this.users = const [], this.external = const []});

  bool get isEmpty => zik.isEmpty && users.isEmpty && external.isEmpty;
}

/// Une suggestion affichée pendant la frappe (avec son badge de source).
class Suggestion {
  final String label;
  final String subtitle;
  final SearchTab kind; // détermine le badge ZIK / USER / EXT
  final Track? track;
  final SearchUser? user;

  const Suggestion({
    required this.label,
    required this.subtitle,
    required this.kind,
    this.track,
    this.user,
  });
}

/// Logique de recherche : agrège les 3 sources et gère un fallback démo
/// quand le backend est injoignable (utile en dev sur appareil).
class SearchEngine {
  /// Recherche **interne** (Zik + Users) en parallèle.
  /// L'externe (YouTube/SoundCloud) est géré séparément en streaming SSE
  /// via [TrackService.searchExternalStream] car il est lent et progressif.
  static Future<SearchResults> searchInternal(String query) async {
    if (query.trim().isEmpty) return const SearchResults();

    final results = await Future.wait([
      TrackService.searchTracks(query),
      TrackService.searchUsers(query),
    ]);

    var zik = results[0] as List<Track>;
    final users = results[1] as List<SearchUser>;

    // Repli démo uniquement si activé (DEMO=true) — sinon on montre le vrai vide
    if (zik.isEmpty && users.isEmpty && ApiConfig.useDemoData) {
      zik = _demoFilter(query);
    }

    return SearchResults(zik: zik, users: users);
  }

  /// Construit les suggestions à partir des 3 sources (limité).
  static List<Suggestion> buildSuggestions(SearchResults r) {
    final out = <Suggestion>[];
    for (final t in r.zik.take(2)) {
      out.add(Suggestion(label: t.title, subtitle: t.artist, kind: SearchTab.zik, track: t));
    }
    for (final u in r.users.take(1)) {
      out.add(Suggestion(
        label: u.username,
        subtitle: '${formatCount(u.nbFollowers)} abonnés',
        kind: SearchTab.user,
        user: u,
      ));
    }
    for (final t in r.external.take(2)) {
      out.add(Suggestion(label: t.title, subtitle: t.artist, kind: SearchTab.external, track: t));
    }
    return out;
  }

  /// Trie une liste de tracks selon le critère choisi.
  static List<Track> sortTracks(List<Track> tracks, SearchSort sort) {
    final list = [...tracks];
    switch (sort) {
      case SearchSort.relevance:
        break; // ordre d'origine (pertinence backend)
      case SearchSort.date:
        // Tri par date de publication réelle, plus récent d'abord.
        // Les tracks sans date connue (souvent externes) sont reléguées en fin,
        // départagées par apiId pour rester stable.
        list.sort((a, b) {
          final da = a.publishedAt;
          final db = b.publishedAt;
          if (da == null && db == null) return (b.apiId ?? 0).compareTo(a.apiId ?? 0);
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case SearchSort.plays:
        list.sort((a, b) => b.listen.compareTo(a.listen));
    }
    return list;
  }

  static List<Track> _demoFilter(String query) {
    final q = query.toLowerCase();
    return kDemoTracks
        .where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q))
        .toList();
  }
}

/// Historique de recherches récent (en mémoire — à persister plus tard).
class RecentSearches extends ChangeNotifier {
  final List<String> _items = ['After Dark', 'Blinding Lights', 'Electronic'];

  List<String> get items => List.unmodifiable(_items);

  void add(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _items.remove(q);
    _items.insert(0, q);
    if (_items.length > 12) _items.removeLast();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

final recentSearches = RecentSearches();
