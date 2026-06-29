import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/track.dart';
import '../../../utils/media.dart';
import 'player_lyrics_view.dart';

/// Paroles en plein écran immersif : les lyrics occupent tout l'écran, avec un
/// fond flouté (pochette), un titre discret et des contrôles minimaux en bas.
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

    return Scaffold(
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
            child: Column(
              children: [
                // En-tête : titre/artiste discrets + bouton réduire
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
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
                      IconButton(
                        tooltip: 'Réduire',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_fullscreen, color: Colors.white70, size: 22),
                      ),
                    ],
                  ),
                ),

                // Paroles plein écran
                Expanded(
                  child: LyricsView(track: track, accent: accent, accentLight: accentLight),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
