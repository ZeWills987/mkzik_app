import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/search_user.dart';
import '../../providers/player_provider.dart';
import '../../services/track_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
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
  bool _loadingExternal = false;
  String? _externalError; // erreur de la recherche externe (SSE)
  List<Suggestion> _suggestions = const [];

  SearchTab _tab = SearchTab.zik;
  SearchSort _sort = SearchSort.relevance;
  ExtPlatform? _extPlatform; // filtre plateforme de l'onglet Externe (null = toutes)

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
      setState(() {
        _suggestions = const [];
        _zik = [];
        _users = [];
        _external = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value));
  }

  /// Lance la recherche : interne (Future) + externe (stream SSE progressif).
  void _runSearch(String query) {
    _extSub?.cancel();
    setState(() {
      _loadingInternal = true;
      _loadingExternal = true;
      _external = [];
      _externalError = null;
    });

    // Interne (Zik + Users) — rapide, one-shot
    SearchEngine.searchInternal(query).then((res) {
      if (!mounted || query != _query) return;
      setState(() {
        _zik = res.zik;
        _users = res.users;
        _loadingInternal = false;
        _rebuildSuggestions();
      });
    });

    // Externe (YouTube/SoundCloud) — streaming, chaque source dès qu'elle répond
    _extSub = TrackService.searchExternalStream(query).listen(
      (ev) {
        if (!mounted || query != _query) return;
        setState(() {
          if (ev.tracks.isNotEmpty) _external = [..._external, ...ev.tracks];
          if (ev.error != null) _externalError = ev.error;
          if (ev.done) _loadingExternal = false;
          _rebuildSuggestions();
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loadingExternal = false);
      },
      onDone: () {
        if (mounted) setState(() => _loadingExternal = false);
      },
    );
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
    setState(() {
      _query = query;
      _showResults = true;
      _tab = SearchTab.zik;
    });
    _runSearch(query);
  }

  void _clear() {
    _controller.clear();
    _extSub?.cancel();
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
                GestureDetector(
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
      ('ZIK', SearchTab.zik, _zik.length),
      ('USER', SearchTab.user, _users.length),
      ('EXTERNE', SearchTab.external, _external.length),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Onglets ZIK / USER / EXTERNE
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Row(
            children: tabs.map((t) {
              final active = _tab == t.$2;
              return GestureDetector(
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
        const Divider(height: 1, color: kDivider),

        // Sous-onglets de tri (uniquement pour les listes de tracks)
        if (_tab != SearchTab.user)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                SortChip('PERTINENCE', _sort == SearchSort.relevance, () => setState(() => _sort = SearchSort.relevance)),
                SortChip('DATE', _sort == SearchSort.date, () => setState(() => _sort = SearchSort.date)),
                SortChip('ÉCOUTES', _sort == SearchSort.plays, () => setState(() => _sort = SearchSort.plays)),
              ],
            ),
          ),

        // Filtres plateforme (uniquement pour l'onglet Externe)
        if (_tab == SearchTab.external)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Row(
              children: [
                PlatformChip(
                  label: 'TOUT',
                  active: _extPlatform == null,
                  onTap: () => setState(() => _extPlatform = null),
                ),
                PlatformChip(
                  label: 'YT MUSIC',
                  platform: ExtPlatform.youtubeMusic,
                  active: _extPlatform == ExtPlatform.youtubeMusic,
                  onTap: () => setState(() => _extPlatform = ExtPlatform.youtubeMusic),
                ),
                PlatformChip(
                  label: 'SOUNDCLOUD',
                  platform: ExtPlatform.soundcloud,
                  active: _extPlatform == ExtPlatform.soundcloud,
                  onTap: () => setState(() => _extPlatform = ExtPlatform.soundcloud),
                ),
              ],
            ),
          ),

        Expanded(child: _buildResultList()),
      ],
    );
  }

  Widget _buildResultList() {
    switch (_tab) {
      case SearchTab.zik:
        if (_loadingInternal) return const ResultsLoader();
        return _trackList(SearchEngine.sortTracks(_zik, _sort), external: false);
      case SearchTab.user:
        if (_loadingInternal) return const ResultsLoader();
        return _userList(_users);
      case SearchTab.external:
        // L'externe arrive en streaming : on affiche au fur et à mesure,
        // avec un loader tant qu'aucun résultat n'est encore là.
        if (_external.isEmpty && _loadingExternal) {
          return const ResultsLoader(label: 'Recherche YouTube / SoundCloud…');
        }
        // Erreur visible (au lieu d'un vide silencieux) si rien n'est revenu
        if (_external.isEmpty && _externalError != null) {
          return ExternalErrorView(message: _externalError!);
        }
        // Filtre par plateforme (YT Music / SoundCloud) si sélectionné
        final ext = _extPlatform == null
            ? _external
            : _external.where((t) => t.extPlatform == _extPlatform).toList();
        return _trackList(
          SearchEngine.sortTracks(ext, _sort),
          external: true,
          footerLoading: _loadingExternal,
        );
    }
  }

  Widget _trackList(List<Track> tracks, {required bool external, bool footerLoading = false}) {
    if (tracks.isEmpty) return const EmptyResults();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
