import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/search_user.dart';
import '../../providers/player_provider.dart';
import '../../providers/search_filter_provider.dart';
import '../../services/track_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/adaptive_sheet.dart';
import '../../widgets/mini_player.dart' show miniPlayerListPadding;
import '../../widgets/tappable.dart';
import 'search_controller.dart';
import 'widgets/search_input_bar.dart';
import 'widgets/explore_view.dart';
import 'widgets/search_suggestions.dart';
import 'widgets/search_result_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // Nombre de résultats demandés par page à l'API Python (par plateforme).
  static const _kExternalPageSize = 30;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  StreamSubscription<ExternalSearchEvent>? _extSub;

  String _query = '';
  bool _showResults = false;

  // Résultats par source (mis à jour incrémentalement pour l'externe SSE)
  List<Track> _zik = [];
  List<SearchUser> _users = [];
  List<Track> _external = [];
  bool _loadingInternal = false;
  bool _loadingExternal = false; // chargement de la 1ʳᵉ page externe
  bool _loadingMoreExternal = false; // chargement d'une page suivante (scroll)
  bool _hasMoreExternal = true; // reste-t-il des pages externes à charger ?
  int _externalPage = 1;
  String? _externalError; // erreur de la recherche externe (SSE)
  List<Suggestion> _suggestions = const [];

  SearchTab _tab = SearchTab.tracks;
  SearchSort _sort = SearchSort.relevance;

  @override
  void initState() {
    super.initState();
    recentSearches.addListener(_onRecentsChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _extSub?.cancel();
    _controller.dispose();
    _focus.dispose();
    recentSearches.removeListener(_onRecentsChanged);
    super.dispose();
  }

  void _onRecentsChanged() => setState(() {});

  // ── Logique de recherche ────────────────────────────────────────────────

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _showResults = false;
    });
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _extSub?.cancel();
      // Résultats vidés → les prochaines requêtes doivent refetcher
      _lastInternalRun = '';
      _lastExternalRun = '';
      _externalPage = 1;
      _hasMoreExternal = true;
      setState(() {
        _suggestions = const [];
        _zik = [];
        _users = [];
        _external = [];
      });
      return;
    }
    // Pendant la frappe : recherche INTERNE seulement (rapide, alimente les
    // suggestions). Le SSE externe (scraping yt-dlp coûteux côté serveur)
    // n'est lancé qu'au submit — sinon chaque pause de frappe déclencherait
    // une recherche YouTube+SoundCloud complète pour 2 lignes de suggestion.
    _debounce = Timer(const Duration(milliseconds: 350), () => _runInternal(value));
  }

  String _lastInternalRun = ''; // dernière requête interne lancée (anti double fetch)
  String _lastExternalRun = ''; // dernière requête SSE externe lancée

  /// Recherche interne (Zik + Users) — Future one-shot.
  void _runInternal(String query) {
    _lastInternalRun = query;
    setState(() => _loadingInternal = true);
    SearchEngine.searchInternal(query).then((res) {
      // On compare à l'identité du fetch (_lastInternalRun), pas au texte live :
      // sinon des résultats valides sont jetés si l'utilisateur a tapé puis
      // rétabli le même texte pendant le vol de la requête.
      if (!mounted || query != _lastInternalRun) return;
      setState(() {
        _zik = res.zik;
        _users = res.users;
        _loadingInternal = false;
        _rebuildSuggestions();
      });
    });
  }

  /// Recherche externe (YouTube/SoundCloud) — stream SSE progressif, 1ʳᵉ page.
  /// N'est lancée que si au moins une chip externe est active.
  void _runExternal(String query) {
    _lastExternalRun = query;
    _extSub?.cancel();
    _externalPage = 1;
    _hasMoreExternal = true;
    setState(() {
      _loadingExternal = true;
      _loadingMoreExternal = false;
      _external = [];
      _externalError = null;
    });
    _fetchExternalPage(query, 1);
  }

  /// Charge la page suivante de résultats externes (déclenché par le scroll).
  void _loadMoreExternal() {
    if (_query.isEmpty || !_showResults) return;
    if (_loadingExternal || _loadingMoreExternal || !_hasMoreExternal) return;
    if (ref.read(searchFilterProvider) == SearchPlatform.mkzik) return;
    _externalPage++;
    setState(() => _loadingMoreExternal = true);
    _fetchExternalPage(_query, _externalPage);
  }

  /// Fetch commun 1ʳᵉ page / pages suivantes — `GET /search/stream?...&page=`.
  void _fetchExternalPage(String query, int page) {
    var receivedThisPage = 0;
    _extSub = TrackService.searchExternalStream(query, maxResults: _kExternalPageSize, page: page).listen(
      (ev) {
        if (!mounted || query != _lastExternalRun) return;
        setState(() {
          if (ev.tracks.isNotEmpty) {
            _external = [..._external, ...ev.tracks];
            receivedThisPage += ev.tracks.length;
          }
          if (ev.error != null) _externalError = ev.error;
          if (ev.done) {
            _loadingExternal = false;
            _loadingMoreExternal = false;
            // Page vide (aucune track sur les 2 plateformes) → plus rien à paginer
            if (receivedThisPage == 0) _hasMoreExternal = false;
          }
          _rebuildSuggestions();
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _loadingExternal = false;
            _loadingMoreExternal = false;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _loadingExternal = false;
            _loadingMoreExternal = false;
          });
        }
      },
    );
  }

  /// Lance les fetchs manquants pour la requête soumise selon la plateforme
  /// sélectionnée (appelé au submit et au changement de plateforme).
  /// L'interne est toujours fetchée (rapide, alimente aussi l'onglet USER) ;
  /// le SSE externe (une seule requête pour YT+SC) seulement si besoin.
  void _ensureFetches() {
    if (!_showResults || _query.isEmpty) return;
    final selected = ref.read(searchFilterProvider);
    if (_query != _lastInternalRun) _runInternal(_query);
    if (selected != SearchPlatform.mkzik && _query != _lastExternalRun) _runExternal(_query);
  }

  void _rebuildSuggestions() {
    _suggestions = SearchEngine.buildSuggestions(
      SearchResults(zik: _zik, users: _users, external: _external),
    );
  }

  Future<void> _submit([String? q]) async {
    final query = (q ?? _query).trim();
    if (query.isEmpty) return;
    _controller.text = query;
    _focus.unfocus();
    recentSearches.add(query);
    // Annule un éventuel debounce en attente : sans ça il relancerait la même
    // recherche interne ~350ms après le submit.
    _debounce?.cancel();
    setState(() {
      _query = query;
      _showResults = true;
      _tab = SearchTab.tracks;
    });
    // Interne : réutilisé si le debounce l'a déjà fetchée. Externe : lancé
    // seulement maintenant (jamais pendant la frappe) et selon les chips.
    _ensureFetches();
  }

  void _clear() {
    _controller.clear();
    _extSub?.cancel();
    _lastInternalRun = '';
    _lastExternalRun = '';
    _externalPage = 1;
    _hasMoreExternal = true;
    setState(() {
      _query = '';
      _showResults = false;
      _suggestions = const [];
      _zik = [];
      _users = [];
      _external = [];
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            SearchInputBar(
              controller: _controller,
              focus: _focus,
              onChanged: _onChanged,
              onSubmitted: _submit,
              onClear: _clear,
              hasText: _query.isNotEmpty,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) return ExploreView(onGenre: _submit);
    if (_showResults) return _buildResults();
    return _buildSuggestions();
  }

  // ── Suggestions + Récents ──────────────────────────────────────────────────

  Widget _buildSuggestions() {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (_suggestions.isNotEmpty) ...[
          const SectionLabel('SUGGESTIONS'),
          ..._suggestions.map((s) => SuggestionRow(
                suggestion: s,
                query: _query,
                onTap: () => _submit(s.label),
              )),
        ] else if (_loadingInternal || _loadingExternal)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: kAccent)),
          ),
        const SizedBox(height: 8),
        // Récents
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              const Text('RÉCENTS',
                  style: TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const Spacer(),
              if (recentSearches.items.isNotEmpty)
                Tappable(
                  onTap: recentSearches.clear,
                  child: const Text('TOUT EFFACER',
                      style: TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
            ],
          ),
        ),
        ...recentSearches.items.map((r) => RecentRow(label: r, onTap: () => _submit(r))),
      ],
    );
  }

  // ── Résultats (onglets + tri) ───────────────────────────────────────────────

  Widget _buildResults() {
    final tabs = [
      ('TITRES', SearchTab.tracks),
      ('USER', SearchTab.user),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch plateforme (single-select, persisté) — onglet Titres uniquement
        if (_tab == SearchTab.tracks)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Consumer(
              builder: (context, ref, _) {
                final selected = ref.watch(searchFilterProvider);
                final notifier = ref.read(searchFilterProvider.notifier);
                return Row(
                  children: SearchPlatform.values
                      .map((p) => PlatformFilterChip(
                            platform: p,
                            active: selected == p,
                            onTap: () {
                              notifier.select(p);
                              // Bascule vers YT/SC après le submit → lance le
                              // fetch externe s'il n'a pas encore eu lieu.
                              _ensureFetches();
                            },
                          ))
                      .toList(),
                );
              },
            ),
          ),

        // Onglets TITRES / USER + bouton tri (à droite, ouvre la modale)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: tabs.map((t) {
                    final active = _tab == t.$2;
                    return Tappable(
                      onTap: () => setState(() => _tab = t.$2),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 22, top: 6, bottom: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.$1,
                                style: TextStyle(
                                  color: active ? kAccent : kTextSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                )),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 2,
                              width: active ? 24 : 0,
                              color: kAccent,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_tab == SearchTab.tracks)
                IconButton(
                  onPressed: _openSortSheet,
                  icon: Icon(Icons.swap_vert_rounded,
                      color: _sort != SearchSort.relevance ? kAccent : kTextSecondary, size: 22),
                  tooltip: 'Trier',
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: kDivider),

        Expanded(
          // Approche du bas de la liste (onglet Titres) → page suivante de
          // résultats externes (GET /search/stream?...&page=N+1).
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (_tab == SearchTab.tracks && n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                _loadMoreExternal();
              }
              return false;
            },
            child: _buildResultList(),
          ),
        ),
      ],
    );
  }

  // Modale de tri (PERTINENCE / DATE / ÉCOUTES) — ouverte via le bouton ↕.
  Future<void> _openSortSheet() async {
    final picked = await showAdaptiveSheet<SearchSort>(
      context: context,
      builder: (_) => _SortSheet(current: _sort),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Widget _buildResultList() {
    switch (_tab) {
      case SearchTab.tracks:
        return Consumer(
          builder: (context, ref, _) {
            final selected = ref.watch(searchFilterProvider);
            final isExternal = selected != SearchPlatform.mkzik;

            // Onglet Mkzik : toute la BD (exclus + importées) — l'onglet par
            // défaut doit toujours répondre ; la pastille distingue l'origine
            // (rouge/orange = importée, rien = exclu Mkzik).
            // Onglets YouTube / SoundCloud : les externes de la plateforme
            // + les tracks Mkzik importées de cette plateforme (pastille
            // violette = déjà dans Mkzik ; l'API Python exclut les importées
            // de ses résultats → pas de doublon au sein d'un onglet).
            final tracks = switch (selected) {
              SearchPlatform.mkzik => _zik,
              SearchPlatform.youtube => [
                  ..._zik.where((t) => t.extPlatforms.contains(ExtPlatform.youtubeMusic)),
                  ..._external.where((t) => t.extPlatform == ExtPlatform.youtubeMusic),
                ],
              SearchPlatform.soundcloud => [
                  ..._zik.where((t) => t.extPlatforms.contains(ExtPlatform.soundcloud)),
                  ..._external.where((t) => t.extPlatform == ExtPlatform.soundcloud),
                ],
            };

            final stillLoading =
                isExternal ? (_loadingExternal || _loadingInternal) : _loadingInternal;
            if (tracks.isEmpty && stillLoading) {
              return const ResultsLoader(label: 'Recherche en cours…');
            }
            if (tracks.isEmpty && isExternal && _externalError != null) {
              return ExternalErrorView(message: _externalError!);
            }

            return _trackList(
              SearchEngine.sortTracks(tracks, _sort, query: _query),
              external: isExternal,
              footerLoading: isExternal && (_loadingExternal || _loadingMoreExternal),
              // Pastille contextuelle : onglet Mkzik → origine (rouge/orange
              // = importée) ; onglets YT/SC → violet = déjà dans Mkzik.
              dot: isExternal ? TrackDot.inMkzik : TrackDot.origin,
            );
          },
        );
      case SearchTab.user:
        if (_loadingInternal) return const ResultsLoader();
        return _userList(_users);
    }
  }

  Widget _trackList(List<Track> tracks,
      {required bool external, bool footerLoading = false, TrackDot dot = TrackDot.origin}) {
    if (tracks.isEmpty) return const EmptyResults();
    return ListView.builder(
      // Padding bas augmenté quand le player flotte par-dessus la liste
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + miniPlayerListPadding(ref)),
      // TrackResultRow n'a pas d'état à préserver hors écran → pas besoin de
      // le garder vivant quand il sort du viewport (moins de mémoire/coût sur
      // les listes longues, notamment avec 60-80 résultats fusionnés).
      addAutomaticKeepAlives: false,
      // +1 ligne pour le loader de fin tant que le stream externe continue
      itemCount: tracks.length + (footerLoading ? 1 : 0),
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
          showPublishedAt: true,
          dot: dot,
          onTap: () => ref.read(playerProvider.notifier).playTrack(tracks[i], queue: tracks),
          onMenu: () => showTrackActionsSheet(context, ref, tracks[i]),
        );
      },
    );
  }

  Widget _userList(List<SearchUser> users) {
    if (users.isEmpty) return const EmptyResults();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      itemBuilder: (_, i) => ResultUserRow(user: users[i]),
    );
  }
}

/// Modale de tri des résultats — ouverte via le bouton ↕ (mobile : bottom
/// sheet ; desktop : dialog centré, cf. [showAdaptiveSheet]).
class _SortSheet extends StatelessWidget {
  final SearchSort current;
  const _SortSheet({required this.current});

  static const _options = [
    (SearchSort.relevance, 'Pertinence', Icons.auto_awesome_rounded),
    (SearchSort.date, 'Plus récents', Icons.schedule_rounded),
    (SearchSort.plays, 'Plus écoutés', Icons.trending_up_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Trier par',
                  style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const Divider(height: 1, color: kBorderSoft),
          ..._options.map((o) {
            final active = current == o.$1;
            return InkWell(
              onTap: () => Navigator.of(context).pop(o.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(o.$3, color: active ? kAccent : kTextSecondary, size: 22),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(o.$2,
                          style: TextStyle(
                            color: active ? kAccent : kTextPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    if (active) const Icon(Icons.check_rounded, color: kAccent, size: 20),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
