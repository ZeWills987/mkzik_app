// On masque RepeatMode de Flutter pour utiliser celui du provider
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track_visuals.dart';
import '../providers/player_provider.dart';
import '../navigation/app_nav.dart';
import '../screens/player/widgets/lyrics_fullscreen.dart';
import '../theme/app_theme.dart';
import 'track_cover.dart';
import 'marquee_text.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    if (player.currentTrack == null) return const SizedBox.shrink();

    final track = player.currentTrack!;
    final notifier = ref.read(playerProvider.notifier);
    // Desktop / fenêtre large : contrôles étendus (shuffle, prev, next, repeat).
    final wide = MediaQuery.of(context).size.width >= 800;

    return Container(
      decoration: const BoxDecoration(
        color: kMiniPlayerBg,
        border: Border(top: BorderSide(color: kBorderMini, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de progression fine
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: player.progress,
              backgroundColor: kBorderMini,
              valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
              minHeight: 2,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Cover + titre : ouvre le player modal au tap
                GestureDetector(
                  onTap: () => appNav.openPlayer(context),
                  child: TrackCover(track: track, size: 42, radius: 8),
                ),
                const SizedBox(width: 12),

                // Titre & artiste
                Expanded(
                  child: GestureDetector(
                    onTap: () => appNav.openPlayer(context),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MarqueeText(
                        text: track.title,
                        style: const TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        style: const TextStyle(color: kTextSecondary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  ),
                ),

                // Paroles : ouvre le plein écran (si le titre peut en avoir)
                if (track.hasLyrics || track.needsStream)
                  GestureDetector(
                    onTap: () {
                      final accent = track.accent;
                      LyricsFullscreen.open(
                        context,
                        track: track,
                        accent: accent,
                        accentLight: Color.lerp(accent, Colors.white, 0.18) ?? accent,
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.mic_none_rounded, color: kTextSecondary, size: 20),
                    ),
                  ),

                // Like
                GestureDetector(
                  onTap: notifier.toggleLike,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      player.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: player.isLiked ? kAccent : kTextSecondary,
                      size: 20,
                    ),
                  ),
                ),

                // Contrôles étendus desktop : shuffle + précédent
                if (wide) ...[
                  GestureDetector(
                    onTap: notifier.toggleShuffle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.shuffle,
                          color: player.isShuffle ? kAccent : kTextSecondary, size: 20),
                    ),
                  ),
                  GestureDetector(
                    onTap: player.canSkip ? notifier.previous : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.skip_previous,
                          color: player.canSkip ? kTextPrimary : kTextSecondary, size: 26),
                    ),
                  ),
                ],

                // Play / Pause
                GestureDetector(
                  onTap: notifier.togglePlayPause,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                    child: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),

                // Contrôles étendus desktop : suivant + repeat
                if (wide) ...[
                  GestureDetector(
                    onTap: player.canSkip ? notifier.next : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.skip_next,
                          color: player.canSkip ? kTextPrimary : kTextSecondary, size: 26),
                    ),
                  ),
                  GestureDetector(
                    onTap: notifier.cycleRepeat,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        player.repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                        color: player.repeatMode == RepeatMode.off ? kTextSecondary : kAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
