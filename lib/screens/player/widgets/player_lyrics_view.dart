import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/track.dart';
import '../../../models/lyrics.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/lyrics_provider.dart';

/// Charge les paroles à la demande (par id) et choisit le rendu :
/// synchronisé (karaoké) si dispo, sinon texte brut.
class LyricsView extends ConsumerWidget {
  final Track track;
  final Color accent;
  final Color accentLight;
  const LyricsView({super.key, required this.track, required this.accent, required this.accentLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Lyrics?> async;
    if (track.source.isEmpty && track.apiId != null) {
      // Track interne (intégrée en BD) → route Symfony par id
      async = ref.watch(lyricsProvider(track.apiId!));
    } else if (track.pageUrl.isNotEmpty) {
      // Track externe en flux direct → route Python (url + artist/title)
      async = ref.watch(lyricsUrlProvider(track));
    } else {
      return const _LyricsMessage('Paroles indisponibles');
    }
    return async.when(
      loading: () => const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70)),
      ),
      error: (_, _) => const _LyricsMessage('Paroles indisponibles'),
      data: (lyrics) {
        if (lyrics == null || lyrics.isEmpty) return const _LyricsMessage('Paroles indisponibles');
        if (lyrics.hasSyncedLines) {
          return _SyncedLyrics(lines: lyrics.lines, accent: accent, accentLight: accentLight);
        }
        return _PlainLyrics(text: lyrics.text);
      },
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  final String text;
  const _LyricsMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 14)),
    );
  }
}

/// Paroles non synchronisées : simple texte défilant.
class _PlainLyrics extends StatelessWidget {
  final String text;
  const _PlainLyrics({required this.text});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Paroles synchronisées (karaoké) : ligne active surlignée, auto-scroll centré,
/// tap sur une ligne → seek. La position vient du player en temps réel.
class _SyncedLyrics extends ConsumerStatefulWidget {
  final List<LyricLine> lines;
  final Color accent;
  final Color accentLight;
  const _SyncedLyrics({required this.lines, required this.accent, required this.accentLight});

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final ScrollController _scroll = ScrollController();
  late final List<GlobalKey> _keys;
  int _lastScrolled = -1;

  // Petite avance pour que le surlignage "tombe" juste avant l'attaque vocale.
  static const _leadMs = 200;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lines.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _activeIndex(int posMs) {
    var found = -1;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].timeMs <= posMs + _leadMs) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  void _scrollTo(int idx) {
    if (idx < 0 || idx >= _keys.length) return;
    final ctx = _keys[idx].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final posMs = ref.watch(playerProvider.select((s) => s.position)).inMilliseconds;
    final active = _activeIndex(posMs);

    // Auto-scroll uniquement quand la ligne active change (pas à chaque tick).
    if (active != _lastScrolled) {
      _lastScrolled = active;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(active));
    }

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
      child: Column(
        children: [for (var i = 0; i < widget.lines.length; i++) _line(i, active)],
      ),
    );
  }

  Widget _line(int i, int active) {
    final isActive = i == active;
    final isPast = i < active;
    final line = widget.lines[i];

    // ⚠️ Géométrie CONSTANTE (même taille + graisse pour toutes les lignes) :
    // la ligne active ne change pas de dimensions → aucun retour à la ligne qui
    // « saute ». L'emphase passe uniquement par la couleur (dégradé façon titre).
    const style = TextStyle(fontSize: 19, height: 1.4, fontWeight: FontWeight.w700);

    Widget text = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 220),
      style: style.copyWith(color: isPast ? Colors.white24 : Colors.white54),
      textAlign: TextAlign.center,
      child: Text(line.text, textAlign: TextAlign.center),
    );

    if (isActive) {
      // Coloration dégradée de la ligne courante, comme le titre du morceau.
      text = ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, widget.accentLight, Colors.white],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: Text(line.text, textAlign: TextAlign.center, style: style.copyWith(color: Colors.white)),
      );
    }

    return Padding(
      key: _keys[i],
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(playerProvider.notifier).seekTo(Duration(milliseconds: line.timeMs)),
        child: text,
      ),
    );
  }
}
