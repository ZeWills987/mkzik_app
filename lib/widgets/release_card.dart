import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../navigation/app_nav.dart';
import '../providers/paginated_tracks_provider.dart' show TrackPageFetcher;
import '../providers/player_provider.dart';
import '../theme/home_style.dart';
import 'track_cover.dart';

/// Carte « Dernière sortie » de l'accueil : pochette large, titre en grand sur
/// l'image, bouton lecture rond, puis titre / artiste dessous.
class ReleaseCard extends ConsumerWidget {
  final Track track;
  final List<Track> queue;
  final TrackPageFetcher? fetchMore;
  final int pageSize;
  final double width;

  const ReleaseCard({
    super.key,
    required this.track,
    required this.queue,
    this.fetchMore,
    this.pageSize = 20,
    this.width = 232,
  });

  /// « NOUVEAU » pendant deux semaines après la publication.
  bool get isNew {
    final d = track.publishedAt;
    return d != null && DateTime.now().difference(d).inDays <= 14;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(playerProvider.select((s) => s.currentTrack?.id == track.id));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final height = width * 0.78;
    final code = homeCatalogCode(track.apiId);

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).playTrack(track,
          queue: queue, fetchMore: fetchMore, pageSize: pageSize, hasMore: queue.length >= pageSize),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Pochette carrée recadrée au format de la carte.
                    OverflowBox(
                      maxWidth: width,
                      maxHeight: width,
                      child: TrackCover(track: track, size: width, radius: 0),
                    ),
                    // Voile pour la lisibilité du titre.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xB3070510)],
                        ),
                      ),
                    ),
                    if (isNew)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: kHomeCoral, borderRadius: BorderRadius.circular(99)),
                          child: Text('NOUVEAU', style: homeMono(size: 9, color: kHomeBg, spacing: 1.4, weight: FontWeight.w500)),
                        ),
                      ),
                    if (code != null)
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Text(code, style: homeMono(size: 9, color: Colors.white70)),
                      ),
                    Positioned(
                      left: 14,
                      right: 62,
                      bottom: 14,
                      child: Text(
                        track.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: homeDisplay(size: 20, color: Colors.white, height: 1.02),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isActive ? kHomeViolet : kHomeInk,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (isActive && isPlaying) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: isActive ? Colors.white : kHomeBg,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => appNav.openTrack(context, track),
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeBody(size: 15, weight: FontWeight.w600, color: isActive ? kHomeViolet : kHomeInk),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(track.durationFormatted, style: homeMono(size: 10)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: track.artist.isEmpty ? null : () => appNav.openArtist(context, track),
              child: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: homeBody(size: 13, weight: FontWeight.w400, color: kHomeInkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
