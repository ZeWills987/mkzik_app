import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../navigation/app_nav.dart';
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
