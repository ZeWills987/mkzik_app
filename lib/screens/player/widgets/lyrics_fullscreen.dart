import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/track.dart';
import '../../../utils/media.dart';
import '../../../widgets/track_cover.dart';
import 'player_lyrics_view.dart';

/// Au-delà de cette largeur : disposition Spotify (pochette à gauche, paroles à
/// droite). En-dessous (mobile) : paroles plein écran mono-colonne.
const double _kWideBreakpoint = 800;

/// Paroles en plein écran immersif.
/// - mobile  : les lyrics occupent tout l'écran, fond flouté, titre discret.
/// - desktop : pochette + infos à gauche, paroles à droite (style Spotify).
/// La ligne active suit la lecture en temps réel ; tap sur une ligne → seek.
class LyricsFullscreen extends StatelessWidget {
  final Track track;
  final Color accent;
  final Color accentLight;

  const LyricsFullscreen({
    super.key,
    required this.track,
    required this.accent,
    required this.accentLight,
  });

  /// Ouvre l'écran en fondu par-dessus le player.
  static Future<void> open(
    BuildContext context, {
    required Track track,
    required Color accent,
    required Color accentLight,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            LyricsFullscreen(track: track, accent: accent, accentLight: accentLight),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = mediaUrl(track.coverUrl);

    return CallbackShortcuts(
      // Échap ferme le plein écran (desktop / clavier)
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF050507),
          body: Stack(
            children: [
              // Fond : pochette très floutée, sinon dégradé sombre
              if (coverUrl.isNotEmpty)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.clamp),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF101014)),
                    ),
                  ),
                ),
              // Scrim sombre pour la lisibilité
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0.78),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= _kWideBreakpoint;
                    return wide ? _buildWide(context) : _buildNarrow(context);
                  },
                ),
              ),

              // Bouton réduire — toujours en haut à droite
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Réduire',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_fullscreen, color: Colors.white70, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Desktop : pochette + infos à gauche, paroles à droite (Spotify) ──────────
  Widget _buildWide(BuildContext context) {
    final coverSize = (MediaQuery.of(context).size.width * 0.24).clamp(220.0, 380.0);
    return Row(
      children: [
        // Panneau gauche : pochette + titre + artiste, centré verticalement
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 24, 24, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: TrackCover(track: track, size: coverSize, radius: 20),
                ),
                const SizedBox(height: 28),
                Text(track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
                if (track.artist.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(track.artist.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: accentLight, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                ],
              ],
            ),
          ),
        ),
        // Panneau droit : paroles
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: LyricsView(track: track, accent: accent, accentLight: accentLight),
          ),
        ),
      ],
    );
  }

  // ── Mobile : paroles plein écran mono-colonne ────────────────────────────────
  Widget _buildNarrow(BuildContext context) {
    return Column(
      children: [
        // En-tête : titre/artiste discrets (le bouton réduire est dans le Stack)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 56, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    if (track.artist.isNotEmpty)
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: accentLight, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LyricsView(track: track, accent: accent, accentLight: accentLight),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
