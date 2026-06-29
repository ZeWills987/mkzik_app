import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/track.dart';
import '../../../providers/player_provider.dart';
import '../../../utils/media.dart';
import 'player_lyrics_view.dart';
import 'player_waveform.dart';

/// Paroles en plein écran immersif : les lyrics occupent tout l'écran, avec un
/// fond flouté (pochette), un titre discret et des contrôles minimaux en bas.
/// La ligne active suit la lecture en temps réel ; tap sur une ligne → seek.
class LyricsFullscreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
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

                // Mini-contrôles : waveform + temps + play/pause
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    children: [
                      PlayerWaveform(
                        progress: player.progress,
                        duration: player.duration,
                        accent: accentLight,
                        seed: track.id.hashCode,
                        onSeek: notifier.seekTo,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(player.positionFormatted,
                              style: const TextStyle(color: Colors.white60, fontSize: 11)),
                          const Spacer(),
                          GestureDetector(
                            onTap: notifier.togglePlayPause,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [accentLight, accent]),
                              ),
                              child: Icon(
                                player.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            player.duration == Duration.zero
                                ? track.durationFormatted
                                : player.durationFormatted,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
