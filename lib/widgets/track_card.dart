import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../navigation/app_nav.dart';
import 'track_cover.dart';

class TrackCard extends ConsumerWidget {
  final Track track;
  final List<Track> queue;
  final double width;
  final bool showPublishedAt; // affiche "il y a X" (date de sortie) si dispo

  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    this.width = 170,
    this.showPublishedAt = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(playerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isActive = currentTrack?.id == track.id;

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: queue),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover : thumbnail réseau ou dégradé de secours
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: width,
                height: width,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TrackCover(track: track, size: width, radius: 16),
                    // Bouton play
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:isActive ? 0.9 : 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (isActive && isPlaying) ? Icons.pause : Icons.play_arrow,
                          color: isActive ? kAccent : Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Infos sous la cover
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre cliquable → page détaillée de la track
                  GestureDetector(
                    onTap: () => appNav.openTrack(context, track),
                    child: Text(
                      track.title,
                      style: TextStyle(
                        color: isActive ? kAccent : kTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Artiste cliquable → son profil
                  GestureDetector(
                    onTap: track.artist.isEmpty ? null : () => appNav.openProfile(context, track.artist),
                    child: Text(
                      track.artist,
                      style: const TextStyle(color: kTextSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    track.durationFormatted,
                    style: const TextStyle(color: kTextSecondary, fontSize: 11),
                  ),
                  // Date de sortie en relatif (section/page "Dernière sortie")
                  if (showPublishedAt && track.publishedLabel != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      track.publishedLabel!,
                      style: const TextStyle(color: kTextSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
