import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/track_visuals.dart';
import '../utils/media.dart';

/// Cover d'un track : affiche la thumbnail réseau si disponible,
/// sinon un dégradé coloré (identité visuelle dérivée du track).
class TrackCover extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;
  final bool showGloss; // sphère lumineuse sur le fallback

  const TrackCover({
    super.key,
    required this.track,
    required this.size,
    this.radius = 12,
    this.showGloss = true,
  });

  @override
  Widget build(BuildContext context) {
    final url = mediaUrl(track.coverUrl); // nettoyée (localhost/placeholder/S3 vide)
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Décode l'image à la taille affichée (× devicePixelRatio) au
                // lieu de la pleine résolution : mémoire et jank de décodage
                // divisés d'un facteur ~10-50 sur les vignettes de listes.
                // ⚠️ Largeur SEULE : si on force aussi memCacheHeight à la même
                // valeur (carré), le décodeur étire l'image de façon non
                // uniforme quand la source n'est pas carrée (déformation),
                // avant même que BoxFit.cover n'intervienne. Une seule
                // dimension laisse le décodeur préserver le ratio d'origine.
                memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                // Fondu court (défaut 500ms) : sur une liste qui défile vite,
                // des dizaines de crossfades longs qui se chevauchent coûtent
                // cher (AnimatedSwitcher par image) sans bénéfice visuel réel.
                fadeInDuration: const Duration(milliseconds: 120),
                fadeOutDuration: const Duration(milliseconds: 80),
                // Filtrage moins coûteux pour les petites vignettes de liste
                // (52px et moins) — imperceptible à cette taille, net gain GPU.
                filterQuality: size <= 56 ? FilterQuality.low : FilterQuality.medium,
                placeholder: (context, u) => _gradient(),
                errorWidget: (context, u, error) => _gradient(),
              )
            : _gradient(),
      ),
    );
  }

  Widget _gradient() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: track.gradientColors,
        ),
      ),
      child: showGloss
          ? Center(
              child: Container(
                width: size * 0.55,
                height: size * 0.55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    colors: [Colors.white.withValues(alpha: 0.35), Colors.transparent],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
