import '../models/track.dart';
import '../providers/paginated_tracks_provider.dart' show TrackPageFetcher;
import 'queue_navigation.dart';

/// La liste de lecture : tout ce qui est connu (pages déjà chargées), la page
/// suivante à demander à l'API, et l'ordre de lecture. Aucune dépendance au
/// lecteur ni à Riverpod : c'est de la pure gestion de liste.
///
/// La file affichée par l'interface n'est qu'une **fenêtre** de cette liste
/// ([window] titres avant et après le titre courant) ; les méthodes
/// [windowAround], [upcomingAfter] et [previousBefore] fournissent les morceaux.
class PlayQueue {
  /// Titres chargés avant / après le titre courant dans la fenêtre affichée.
  static const window = 10;

  List<Track> _src = [];
  TrackPageFetcher? _fetch;
  int _pageSize = 20;
  int _fetched = 0; // offset API = titres déjà reçus de la source
  bool _hasMore = false;
  int _epoch = 0;

  /// Change quand une autre liste est lancée : les tâches asynchrones qui
  /// l'avaient capturé savent qu'elles sont obsolètes.
  int get epoch => _epoch;
  int get length => _src.length;
  bool get isEmpty => _src.isEmpty;

  /// Reste-t-il des pages à demander à l'API ?
  bool get hasMore => _hasMore;
  List<Track> get tracks => List.unmodifiable(_src);

  int indexOfId(String id) => _src.indexWhere((t) => t.id == id);

  /// Définit la liste lue. Renvoie `true` si c'est une AUTRE liste que la
  /// précédente (l'époque change) ; `false` si c'est la même (on garde l'état).
  bool load(List<Track> list, {TrackPageFetcher? fetchMore, int pageSize = 20, bool hasMore = true}) {
    if (!_isSameList(list)) {
      _epoch++;
      _src = [...list];
      _fetch = fetchMore;
      _pageSize = pageSize;
      _fetched = list.length;
      _hasMore = fetchMore != null && hasMore;
      return true;
    }
    if (fetchMore != null && _fetch == null) {
      _fetch = fetchMore;
      _pageSize = pageSize;
      _hasMore = hasMore;
    }
    return false;
  }

  bool _isSameList(List<Track> list) {
    if (list.length > _src.length) return false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id != _src[i].id) return false;
    }
    return true;
  }

  /// La fenêtre autour de [track] (ajouté en tête s'il n'est pas dans la liste).
  List<Track> windowAround(Track track) {
    var i = indexOfId(track.id);
    if (i < 0) {
      _src.insert(0, track);
      i = 0;
    }
    return _src.sublist((i - window).clamp(0, _src.length), (i + window + 1).clamp(0, _src.length));
  }

  /// Les titres à ajouter après [last] (dernier titre de la fenêtre affichée).
  /// Demande la page suivante à l'API quand la liste connue est épuisée.
  Future<List<Track>> upcomingAfter(Track last) async {
    var lastSrc = indexOfId(last.id);
    if (lastSrc < 0) return const [];
    if (lastSrc + 1 >= _src.length && _fetch != null && _hasMore) {
      final epoch = _epoch;
      final page = await _fetch!(limit: _pageSize, offset: _fetched);
      if (epoch != _epoch) return const [];
      _fetched += page.length;
      _hasMore = page.length >= _pageSize;
      final known = {for (final t in _src) t.id};
      _src.addAll(page.where((t) => known.add(t.id)));
      lastSrc = indexOfId(last.id);
      if (lastSrc < 0) return const [];
    }
    return _src.sublist(lastSrc + 1, (lastSrc + 1 + window).clamp(0, _src.length));
  }

  /// Les titres à ajouter avant [first] (premier titre de la fenêtre affichée).
  List<Track> previousBefore(Track first) {
    final f = indexOfId(first.id);
    if (f <= 0) return const [];
    return _src.sublist((f - window).clamp(0, f), f);
  }

  /// Tout ce qui précède [first] est-il déjà dans la fenêtre ?
  bool loadedAllPrevious(Track? first) => first == null || indexOfId(first.id) <= 0;

  /// Tout ce qui suit [last] est-il déjà dans la fenêtre (et plus de page à charger) ?
  bool loadedAllUpcoming(Track? last) =>
      last == null || (!_hasMore && indexOfId(last.id) >= _src.length - 1);

  /// Titre qui suit [current] : suivant en boucle, ou au hasard si [shuffle].
  Track nextOf(Track current, {required bool shuffle}) {
    final i = nextSourceIndex(length: _src.length, current: indexOfId(current.id), shuffle: shuffle);
    return _src[i];
  }

  /// Titre qui précède [current] (en boucle).
  Track previousOf(Track current) {
    final i = previousSourceIndex(length: _src.length, current: indexOfId(current.id));
    return _src[i];
  }

  /// Remplace la portion couverte par [oldWindow] par [newWindow] (après un
  /// ajout / retrait / réordonnancement dans la file affichée).
  void replaceWindow(List<Track> oldWindow, List<Track> newWindow) {
    if (oldWindow.isEmpty) {
      _src = [...newWindow];
      return;
    }
    final start = indexOfId(oldWindow.first.id);
    final end = indexOfId(oldWindow.last.id);
    if (start < 0 || end < start) return;
    final ids = {for (final t in newWindow) t.id};
    _src = [
      ..._src.sublist(0, start).where((t) => !ids.contains(t.id)),
      ...newWindow,
      ..._src.sublist(end + 1).where((t) => !ids.contains(t.id)),
    ];
  }

  /// Insère [track] juste après [current] (en fin de liste si [current] est inconnu).
  void insertAfter(Track current, Track track) {
    final i = indexOfId(current.id);
    _src.insert(i < 0 ? _src.length : i + 1, track);
  }

  void addAll(Iterable<Track> tracks) => _src.addAll(tracks);

  /// Retire le titre [id] de la liste. Renvoie son ancien index (-1 s'il n'y était pas).
  int removeById(String id) {
    final i = indexOfId(id);
    if (i >= 0) _src.removeAt(i);
    return i;
  }

  /// Titre à l'index [i], en bouclant (pour retomber sur un titre valide après
  /// un retrait). Liste vide : `null`.
  Track? wrapAt(int i) => _src.isEmpty ? null : _src[i % _src.length];

  /// Remplace tout ce qui suit le début de la fenêtre ([first]) par [newQueue]
  /// (mode radio) : l'ancienne suite, y compris les pages pas encore chargées,
  /// est abandonnée.
  void replaceFrom(Track first, List<Track> newQueue) {
    final firstSrc = indexOfId(first.id);
    _src = [if (firstSrc > 0) ..._src.sublist(0, firstSrc), ...newQueue];
    _fetch = null;
    _hasMore = false;
  }
}
