import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/search_user.dart';
import '../../providers/player_provider.dart';
import '../../services/track_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../../widgets/track_actions.dart';
import '../profile/profile_screen.dart';
import 'search_controller.dart';

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
            _SearchBar(
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
    if (_query.isEmpty) return const _ExploreView();
    if (_showResults) return _buildResults();
    return _buildSuggestions();
  }

  // ── Suggestions + Récents ──────────────────────────────────────────────────

  Widget _buildSuggestions() {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (_suggestions.isNotEmpty) ...[
          const _SectionLabel('SUGGESTIONS'),
          ..._suggestions.map((s) => _SuggestionRow(
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
        ...recentSearches.items.map((r) => _RecentRow(label: r, onTap: () => _submit(r))),
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
                _SortChip('PERTINENCE', _sort == SearchSort.relevance, () => setState(() => _sort = SearchSort.relevance)),
                _SortChip('DATE', _sort == SearchSort.date, () => setState(() => _sort = SearchSort.date)),
                _SortChip('ÉCOUTES', _sort == SearchSort.plays, () => setState(() => _sort = SearchSort.plays)),
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
        if (_loadingInternal) return const _ResultsLoader();
        return _trackList(SearchEngine.sortTracks(_zik, _sort), external: false);
      case SearchTab.user:
        if (_loadingInternal) return const _ResultsLoader();
        return _userList(_users);
      case SearchTab.external:
        // L'externe arrive en streaming : on affiche au fur et à mesure,
        // avec un loader tant qu'aucun résultat n'est encore là.
        if (_external.isEmpty && _loadingExternal) {
          return const _ResultsLoader(label: 'Recherche YouTube / SoundCloud…');
        }
        // Erreur visible (au lieu d'un vide silencieux) si rien n'est revenu
        if (_external.isEmpty && _externalError != null) {
          return _ExternalErrorView(message: _externalError!);
        }
        return _trackList(
          SearchEngine.sortTracks(_external, _sort),
          external: true,
          footerLoading: _loadingExternal,
        );
    }
  }

  Widget _trackList(List<Track> tracks, {required bool external, bool footerLoading = false}) {
    if (tracks.isEmpty) return const _EmptyResults();
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
    if (users.isEmpty) return const _EmptyResults();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      itemBuilder: (_, i) => _ResultUserRow(user: users[i]),
    );
  }
}

// ── Barre de recherche ────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool hasText;

  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: kAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                cursorColor: kAccent,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Rechercher...',
                  hintStyle: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w400),
                ),
              ),
            ),
            if (hasText)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: kBorder, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: kTextSecondary, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Vue Explorer (grille de genres) ─────────────────────────────────────────

class _ExploreView extends StatelessWidget {
  const _ExploreView();

  static const _genres = [
    ('HIP-HOP', [Color(0xFF9B6BF2), Color(0xFF5A2DBF)]),
    ('ELECTRONIC', [Color(0xFF4A90D9), Color(0xFF2C5FA8)]),
    ('POP', [Color(0xFFE8506E), Color(0xFFB02340)]),
    ('R&B', [Color(0xFF2BB463), Color(0xFF157A3E)]),
    ('INDIE', [Color(0xFFB466E8), Color(0xFF7A2DBF)]),
    ('JAZZ', [Color(0xFFE8A23A), Color(0xFFC26A0A)]),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionLabel('EXPLORER'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: _genres.map((g) => _GenreCard(label: g.$1, colors: g.$2)).toList(),
        ),
      ],
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String label;
  final List<Color> colors;

  const _GenreCard({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Lance une recherche sur le genre via le sendPrompt local : on remonte
        // au parent en simulant une soumission.
        final state = context.findAncestorStateOfType<_SearchScreenState>();
        state?._submit(label);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Stack(
          children: [
            // Reflet lumineux
            Positioned(
              right: -10,
              top: -10,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white.withValues(alpha: 0.25), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lignes diverses ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(text,
          style: const TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
    );
  }
}

// Badge de source (ZIK / USER / EXT)
class _SourceBadge extends StatelessWidget {
  final SearchTab kind;
  const _SourceBadge(this.kind);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      SearchTab.zik => ('ZIK', kAccent),
      SearchTab.user => ('USER', kUserBlue),
      SearchTab.external => ('EXT', kBadgeGray),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final Suggestion suggestion;
  final String query;
  final VoidCallback onTap;

  const _SuggestionRow({required this.suggestion, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUser = suggestion.kind == SearchTab.user;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Vignette
            if (isUser)
              CircleAvatar(
                radius: 18,
                backgroundColor: kUserBlue,
                child: Text(
                  suggestion.label.isNotEmpty ? suggestion.label[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              )
            else if (suggestion.track != null)
              TrackSquareThumb(track: suggestion.track!)
            else
              const SizedBox(width: 36, height: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlight(suggestion.label, query),
                  const SizedBox(height: 2),
                  Text(suggestion.subtitle,
                      style: const TextStyle(color: kTextSecondary, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _SourceBadge(suggestion.kind),
          ],
        ),
      ),
    );
  }

  // Met en évidence la portion qui matche la requête (en accent)
  Widget _highlight(String label, String query) {
    final lower = label.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (q.isEmpty || idx < 0) {
      return Text(label,
          style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        children: [
          TextSpan(text: label.substring(0, idx), style: const TextStyle(color: kTextPrimary)),
          TextSpan(text: label.substring(idx, idx + q.length), style: const TextStyle(color: kAccent)),
          TextSpan(text: label.substring(idx + q.length), style: const TextStyle(color: kTextPrimary)),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RecentRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.history, color: kTextSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.north_west, color: kTextSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SortChip(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Text(label,
            style: TextStyle(
              color: active ? kAccent : kTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            )),
      ),
    );
  }
}

// Ligne de résultat utilisateur
class _ResultUserRow extends StatefulWidget {
  final SearchUser user;
  const _ResultUserRow({required this.user});

  @override
  State<_ResultUserRow> createState() => _ResultUserRowState();
}

class _ResultUserRowState extends State<_ResultUserRow> {
  late bool _following = widget.user.isFollowing;
  bool _busy = false; // évite les double-taps pendant l'appel

  // Bascule optimiste + appel API, rollback si échec (cf. profil)
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _following = !_following;
    });
    final ok = await ProfileService.toggleFollow(widget.user.username);
    if (!mounted) return;
    setState(() {
      if (!ok) _following = !_following; // rollback
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Avatar + nom cliquables → profil de l'utilisateur/artiste
          Expanded(
            child: GestureDetector(
              onTap: () => ProfileScreen.open(context, u.username),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final av = mediaUrl(u.avatarUrl);
                    return CircleAvatar(
                    radius: 22,
                    backgroundColor: kUserBlue,
                    backgroundImage: av.isNotEmpty ? NetworkImage(av) : null,
                    child: av.isEmpty
                        ? Text(u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                        : null,
                  );
                  }),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.username,
                            style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${formatCount(u.nbFollowers)} abonnés',
                            style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _following ? Colors.transparent : kAccent,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: kAccent),
              ),
              child: Text(_following ? 'Suivi' : 'Suivre',
                  style: TextStyle(
                    color: _following ? kAccent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Aucun résultat', style: TextStyle(color: kTextSecondary, fontSize: 14)),
    );
  }
}

// Affiche l'erreur de la recherche externe (au lieu d'un vide silencieux)
class _ExternalErrorView extends StatelessWidget {
  final String message;
  const _ExternalErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: kTextSecondary, size: 40),
            const SizedBox(height: 14),
            const Text('Recherche externe indisponible',
                style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

// Loader centré avec libellé optionnel (recherche en cours)
class _ResultsLoader extends StatelessWidget {
  final String? label;
  const _ResultsLoader({this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kAccent),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

