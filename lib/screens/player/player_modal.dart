import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
// On masque RepeatMode de Flutter pour utiliser celui du provider
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/player_provider.dart';
import '../../providers/notice_provider.dart';
import '../../widgets/current_list_sheet.dart';
import '../../widgets/track_cover.dart';
import '../../widgets/track_actions.dart';
import '../../utils/media.dart';
import '../profile/profile_screen.dart';
import 'widgets/player_scene_painter.dart';
import 'widgets/player_waveform.dart';
import 'widgets/player_controls.dart';
import '../../models/lyrics.dart';
import '../../providers/lyrics_provider.dart';
import 'widgets/player_lyrics_view.dart';
import 'widgets/lyrics_fullscreen.dart';

/// Player modal plein écran.
///
/// Tout le thème (fond, glow, dégradé du titre, waveform, bouton play, décor)
/// est dérivé de [Track.gradientColors] → chaque morceau a sa propre ambiance.
class PlayerModal extends ConsumerStatefulWidget {
  const PlayerModal({super.key});

  /// Ouvre le modal en bottom-sheet plein écran avec animation de montée.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (ctx, anim, secAnim) => const PlayerModal(),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  ConsumerState<PlayerModal> createState() => _PlayerModalState();
}

class _PlayerModalState extends ConsumerState<PlayerModal>
    with SingleTickerProviderStateMixin {
  // Décalage vertical courant pendant le glissement (0 = position fermée/haute)
  double _dragOffset = 0;
  // Mode paroles : la zone centrale (pochette) laisse place aux lyrics.
  bool _showLyrics = false;
  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // On ne suit que vers le bas (offset >= 0)
    setState(() => _dragOffset = math.max(0, _dragOffset + d.delta.dy));
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final h = MediaQuery.of(context).size.height;
    // Ferme si glissé sur > 25% de l'écran OU geste rapide vers le bas
    if (_dragOffset > h * 0.25 || velocity > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    // Sinon : retour élastique à la position initiale
    final anim = Tween(begin: _dragOffset, end: 0.0)
        .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOut));
    void listener() => setState(() => _dragOffset = anim.value);
    anim.addListener(listener);
    _snap.forward(from: 0).whenComplete(() => anim.removeListener(listener));
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final notifier = ref.read(playerProvider.notifier);
    final colors = track.gradientColors;
    final accent = track.accent;
    final accentLight = _lighten(accent, 0.18);
    final coverUrl = mediaUrl(track.coverUrl);
    final artSize = (MediaQuery.of(context).size.width * 0.58).clamp(150.0, 300.0);

    final screenH = MediaQuery.of(context).size.height;
    final dragT = (_dragOffset / screenH).clamp(0.0, 1.0);

    // Bouton/mode LYRICS :
    //  • interne → flag serveur `track.hasLyrics`.
    //  • externe → toujours tentable (le fetch `/lyrics?url=` retourne `found: false`
    //    si pas de paroles — la sonde via /stream a été supprimée car elle ouvrait une
    //    connexion concurrente sur le même flux yt-dlp et provoquait des sauts prématurés).
    final isExternal = track.source.isNotEmpty && track.pageUrl.isNotEmpty;
    final canTryLyrics = track.hasLyrics || isExternal;
    final showLyrics = _showLyrics && canTryLyrics;

    // Bloc titre + artiste, partagé entre le mode léger et le mode paroles.
    final Widget titleBlock = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          _GradientText(
            track.title.toUpperCase(),
            colors: [Colors.white, accentLight, Colors.white],
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.5, height: 1.1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: track.artist.isEmpty
                ? null
                : () {
                    Navigator.of(context).maybePop();
                    ProfileScreen.open(context, track.artist);
                  },
            child: Text(
              track.artist.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(color: accentLight, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      // Glisser vers le bas n'importe où sur le fond pour fermer
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(
          opacity: (1 - dragT * 0.7).clamp(0.0, 1.0),
          child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Fond : pochette floutée (style Apple Music) ou dégradé du track ─
          if (coverUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55, tileMode: TileMode.clamp),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const ColoredBox(color: Color(0xFF101014)),
                ),
              ),
            )
          else ...[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _darken(colors.length > 1 ? colors[1] : accent, 0.35),
                      _darken(colors.last, 0.55),
                      const Color(0xFF050507),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: ScenePainter(scene: track.scene, accent: accent),
              ),
            ),
          ],

          // Scrim sombre vertical → lisibilité du texte et des contrôles
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.52),
                    Colors.black.withValues(alpha: 0.86),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Halo accent subtil (ambiance du morceau)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.1, -0.7),
                  radius: 1.1,
                  colors: [accent.withValues(alpha: 0.30), Colors.transparent],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Poignée + bouton fermer
                PlayerTopBar(
                  onClose: () => Navigator.of(context).maybePop(),
                  onQueue: () => showCurrentList(context),
                ),

                if (!showLyrics) ...[
                  const Spacer(flex: 2),

                  // Pochette nette (style Apple Music) — cadre verre + ombre portée
                  Container(
                    width: artSize,
                    height: artSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 40,
                          offset: const Offset(0, 22),
                        ),
                      ],
                    ),
                    child: TrackCover(track: track, size: artSize, radius: 24),
                  ),

                  const SizedBox(height: 26),
                  titleBlock,
                  const SizedBox(height: 10),
                  _CurrentLyricsLine(track: track, accentLight: accentLight),
                  const Spacer(flex: 3),
                ] else ...[
                  // Mode paroles : titre compact en haut, paroles qui remplissent
                  // l'espace jusqu'au panneau de contrôles.
                  const SizedBox(height: 14),
                  titleBlock,
                  const SizedBox(height: 12),
                  Expanded(
                    child: Stack(
                      children: [
                        LyricsView(track: track, accent: accent, accentLight: accentLight),
                        // Passage en plein écran immersif
                        Positioned(
                          top: 0,
                          right: 4,
                          child: IconButton(
                            tooltip: 'Plein écran',
                            onPressed: () => LyricsFullscreen.open(
                              context,
                              track: track,
                              accent: accent,
                              accentLight: accentLight,
                            ),
                            icon: const Icon(Icons.open_in_full, color: Colors.white54, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Panneau "liquid glass" : toutes les commandes ────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _glassPanel(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        children: [
                          // Barre d'actions : LIKE / LYRICS / SHARE / MORE
                          PlayerActionsRow(
                            isLiked: player.isLiked,
                            likes: track.likesLabel,
                            accent: accent,
                            hasLyrics: canTryLyrics,
                            lyricsActive: showLyrics,
                            onLyrics: () => setState(() => _showLyrics = !_showLyrics),
                            onLike: notifier.toggleLike,
                            onShare: () {
                              Clipboard.setData(ClipboardData(
                                  text: track.pageUrl.isNotEmpty ? track.pageUrl : track.title));
                              ref.read(noticeProvider.notifier).show('Lien copié', icon: NoticeIcon.share);
                            },
                            onMore: () => showTrackActionsSheet(context, ref, track),
                          ),
                          const SizedBox(height: 18),
                          // Waveform + temps
                          PlayerWaveform(
                            progress: player.progress,
                            duration: player.duration,
                            accent: accentLight,
                            seed: track.id.hashCode,
                            onSeek: notifier.seekTo,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(player.positionFormatted,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              Text(
                                player.duration == Duration.zero
                                    ? track.durationFormatted
                                    : player.durationFormatted,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Shuffle · prev · play · next · repeat
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: notifier.toggleShuffle,
                                child: Icon(
                                  Icons.shuffle,
                                  size: 22,
                                  color: player.isShuffle ? accentLight : Colors.white54,
                                ),
                              ),
                              const SizedBox(width: 22),
                              PlayerControlButton(
                                icon: Icons.skip_previous,
                                enabled: player.canSkip,
                                onTap: notifier.previous,
                              ),
                              const SizedBox(width: 20),
                              PlayerPlayButton(
                                isPlaying: player.isPlaying,
                                colors: [accentLight, accent],
                                onTap: notifier.togglePlayPause,
                              ),
                              const SizedBox(width: 20),
                              PlayerControlButton(
                                icon: Icons.skip_next,
                                enabled: player.canSkip,
                                onTap: notifier.next,
                              ),
                              const SizedBox(width: 22),
                              GestureDetector(
                                onTap: notifier.cycleRepeat,
                                child: Icon(
                                  player.repeatMode == RepeatMode.one
                                      ? Icons.repeat_one
                                      : Icons.repeat,
                                  size: 22,
                                  color: accentLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}

// ── Ligne de lyrics courante (mode normal, sous le titre) ────────────────────

class _CurrentLyricsLine extends ConsumerWidget {
  final Track track;
  final Color accentLight;
  const _CurrentLyricsLine({required this.track, required this.accentLight});

  static const _leadMs = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Lyrics? lyrics;
    if (track.source.isEmpty && track.apiId != null) {
      // Track interne → route Symfony par id
      lyrics = ref.watch(lyricsProvider(track.apiId!)).valueOrNull;
    } else if (track.pageUrl.isNotEmpty) {
      // Track externe en flux direct → route Python (url + artist/title)
      lyrics = ref.watch(lyricsUrlProvider(track)).valueOrNull;
    } else {
      return const SizedBox.shrink();
    }
    if (lyrics == null || !lyrics.hasSyncedLines) return const SizedBox.shrink();

    final posMs = ref.watch(playerProvider.select((s) => s.position)).inMilliseconds;

    int active = -1;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (lyrics.lines[i].timeMs <= posMs + _leadMs) {
        active = i;
      } else {
        break;
      }
    }

    if (active < 0) return const SizedBox.shrink();
    final text = lyrics.lines[active].text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: ShaderMask(
          key: ValueKey(active),
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.white, accentLight, Colors.white],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── Texte avec dégradé (titre du morceau) ────────────────────────────────────

class _GradientText extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final TextStyle style;
  final TextAlign textAlign;

  const _GradientText(this.text,
      {required this.colors, required this.style, this.textAlign = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ).createShader(bounds),
      child: Text(text, textAlign: textAlign, style: style.copyWith(color: Colors.white)),
    );
  }
}

// ── Panneau verre dépoli (liquid glass) ──────────────────────────────────────

Widget _glassPanel({required Widget child}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: child,
      ),
    ),
  );
}

// ── Helpers couleur ───────────────────────────────────────────────────────────

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}
