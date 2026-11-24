import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../navigation/app_nav.dart';
import '../../providers/player_provider.dart';
import '../../theme/home_style.dart';
import '../../widgets/tappable.dart';
import '../../widgets/track_cover.dart';

/// « À la une cette semaine » : le titre le plus récent mis en avant, avec les
/// deux sorties précédentes empilées derrière sa pochette.
class HomeHero extends ConsumerWidget {
  /// Dernières sorties, la plus récente en premier (au moins une).
  final List<Track> tracks;
  const HomeHero({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks.first;
    final published = track.publishedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _CoverStack(tracks: tracks.take(3).toList())),
          const SizedBox(height: 26),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: kHomeCoral, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'À LA UNE CETTE SEMAINE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: homeMono(size: 11, color: kHomeCoral, spacing: 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            track.artist.isEmpty ? track.title : track.artist,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: homeDisplay(size: 52, height: 0.95),
          ),
          if (track.artist.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'signe « ${track.title} »',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: homeBody(size: 20, weight: FontWeight.w400, color: kHomeVioletSoft, height: 1.2),
            ),
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Tappable(
                onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: tracks),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  decoration: BoxDecoration(color: kHomeViolet, borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text('Écouter', style: homeBody(size: 14, weight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              if (track.artist.isNotEmpty)
                Tappable(
                  onTap: () => appNav.openArtist(context, track),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: kHomeLine),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Voir l'artiste", style: homeBody(size: 14, weight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, color: kHomeInk, size: 16),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Container(height: 1, color: kHomeLine),
          const SizedBox(height: 16),
          Wrap(
            runSpacing: 14,
            children: [
              if (published != null) _Stat(label: 'SORTI EN', value: '${published.year}'),
              _Stat(label: 'DURÉE', value: track.durationFormatted),
              if (track.listen > 0) _Stat(label: 'ÉCOUTES', value: formatCount(track.listen)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: homeMono(size: 10)),
          const SizedBox(height: 6),
          Text(value, style: homeBody(size: 15, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Pochettes empilées : la plus récente devant, les deux autres inclinées derrière.
class _CoverStack extends StatelessWidget {
  final List<Track> tracks;
  const _CoverStack({required this.tracks});

  static const double _size = 196;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 96,
      height: _size + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Derrière : sorties précédentes, de la plus lointaine à la plus proche.
          if (tracks.length > 2) _card(tracks[2], angle: 0.17, dx: 60, dy: 26, scale: 0.84, dim: 0.35),
          if (tracks.length > 1) _card(tracks[1], angle: -0.16, dx: -58, dy: 14, scale: 0.9, dim: 0.2),
          _card(tracks.first, angle: 0.0, dx: 0, dy: 0, scale: 1, dim: 0, front: true),
        ],
      ),
    );
  }

  Widget _card(Track t, {required double angle, required double dx, required double dy, required double scale, required double dim, bool front = false}) {
    final code = homeCatalogCode(t.apiId);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: _size * scale,
          height: _size * scale,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: kHomeLine),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 28, offset: const Offset(0, 14))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                TrackCover(track: t, size: _size * scale, radius: 0),
                if (dim > 0) ColoredBox(color: kHomeBg.withValues(alpha: dim)),
                if (front)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3070510)],
                      ),
                    ),
                  ),
                if (code != null)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Text(code, textAlign: TextAlign.center, style: homeMono(size: 9, color: Colors.white70)),
                  ),
                if (front)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Text(
                      t.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: homeDisplay(size: math.min(26, 220 / math.max(8, t.title.length) * 1.6), color: Colors.white, height: 1.0),
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
