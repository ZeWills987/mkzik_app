import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../navigation/app_nav.dart';

// Widget horizontal/liste — utile pour les écrans de playlist ou résultats
class TrackTile extends ConsumerWidget {
  final Track track;
  final List<Track> queue;
  final int? index;

  const TrackTile({
    super.key,
    required this.track,
    required this.queue,
    this.index,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(playerProvider.select((s) => s.currentTrack));
    final isActive = currentTrack?.id == track.id;

    return ListTile(
      onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: queue),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: track.coverUrl,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => Container(color: kCard),
          errorWidget: (ctx, url, err) => Container(
            color: kCard,
            child: const Icon(Icons.music_note, color: kAccent),
          ),
        ),
      ),
      title: GestureDetector(
        onTap: () => appNav.openTrack(context, track),
        child: Text(
          track.title,
          style: TextStyle(
            color: isActive ? kAccent : kTextPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: GestureDetector(
        onTap: track.artist.isEmpty ? null : () => appNav.openProfile(context, track.artist),
        child: Text(
          track.artist,
          style: const TextStyle(color: kTextSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(track.durationFormatted, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
          const SizedBox(width: 8),
          const Icon(Icons.more_vert, color: kTextSecondary, size: 20),
        ],
      ),
    );
  }
}
