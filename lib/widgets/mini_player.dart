// On masque RepeatMode de Flutter pour utiliser celui du provider
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../navigation/app_nav.dart';
import '../screens/player/widgets/lyrics_fullscreen.dart';
import '../theme/app_theme.dart';
import 'track_cover.dart';
import 'marquee_text.dart';
import 'tappable.dart';

/// Rayon des coins du pill flottant — assez arrondi pour un rendu "liquid glass".
const double kMiniPlayerRadius = 26;

/// Espace à réserver en bas des listes scrollables quand le pill flotte
/// par-dessus (hauteur du pill + marges) — sinon le dernier élément reste
/// inatteignable sous le player.
const double kMiniPlayerOverlayPadding = 92;

/// Padding bas à ajouter aux listes : hauteur du player flottant si un titre
/// joue, sinon 0. À utiliser dans le `padding:` des scrollables plein écran.
double miniPlayerListPadding(WidgetRef ref) =>
    ref.watch(playerProvider.select((s) => s.currentTrack != null))
        ? kMiniPlayerOverlayPadding
        : 0;

/// Mini-player flottant : pill détaché des bords (marges gérées par le
/// parent qui le positionne), fond translucide + flou (liquid glass), coins
/// arrondis sur les 4 côtés. Ne dépend plus de la largeur de l'écran pour son
/// alignement — c'est le shell qui le pose via [Positioned].
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ Perf : pas de watch global de playerProvider ici — le positionStream
    // émet jusqu'à ~60 Hz et rebuilderait tout le pill (BackdropFilter compris)
    // à chaque tick. On sélectionne uniquement les champs "lents" ; la barre de
    // progression (seule dépendante de la position) est isolée dans _MiniProgressBar.
    final track = ref.watch(playerProvider.select((s) => s.currentTrack));
    if (track == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLiked = ref.watch(playerProvider.select((s) => s.isLiked));
    final isShuffle = ref.watch(playerProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playerProvider.select((s) => s.repeatMode));
    final canSkip = ref.watch(playerProvider.select((s) => s.canSkip));
    final notifier = ref.read(playerProvider.notifier);
    // Desktop / fenêtre large : contrôles étendus (shuffle, prev, next, repeat).
    final wide = MediaQuery.of(context).size.width >= 800;

    // Ombre AUTOUR du ClipRRect (dedans elle serait clippée → invisible),
    // sigma 12 : l'effet verre reste net sur une petite surface, pour ~2× moins
    // de coût GPU (le backdrop est ré-échantillonné à chaque frame de scroll).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kMiniPlayerRadius),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(kMiniPlayerRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: kMiniPlayerBg.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(kMiniPlayerRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barre de progression fine (widget isolé : seul lui rebuild au tick)
              const _MiniProgressBar(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                // Cover + titre : ouvre le player modal au tap
                Tappable(
                  onTap: () => appNav.openPlayer(context),
                  child: TrackCover(track: track, size: 42, radius: 8),
                ),
                const SizedBox(width: 12),

                // Titre & artiste
                Expanded(
                  child: Tappable(
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
                  Tappable(
                    onTap: () => LyricsFullscreen.open(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.mic_none_rounded, color: kTextSecondary, size: 20),
                    ),
                  ),

                // Like
                Tappable(
                  onTap: notifier.toggleLike,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? kAccent : kTextSecondary,
                      size: 20,
                    ),
                  ),
                ),

                // Contrôles étendus desktop : shuffle + précédent
                if (wide) ...[
                  Tappable(
                    onTap: notifier.toggleShuffle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.shuffle,
                          color: isShuffle ? kAccent : kTextSecondary, size: 20),
                    ),
                  ),
                  Tappable(
                    onTap: canSkip ? notifier.previous : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.skip_previous,
                          color: canSkip ? kTextPrimary : kTextSecondary, size: 26),
                    ),
                  ),
                ],

                // Play / Pause
                Tappable(
                  onTap: notifier.togglePlayPause,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),

                // Contrôles étendus desktop : suivant + repeat
                if (wide) ...[
                  Tappable(
                    onTap: canSkip ? notifier.next : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.skip_next,
                          color: canSkip ? kTextPrimary : kTextSecondary, size: 26),
                    ),
                  ),
                  Tappable(
                    onTap: notifier.cycleRepeat,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                        color: repeatMode == RepeatMode.off ? kTextSecondary : kAccent,
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
        ),
      ),
      ),
    );
  }
}

/// Barre de progression du mini-player, isolée : seul widget à écouter la
/// position (via `progress`), pour que le pill (blur, marquee, contrôles)
/// ne rebuild pas à chaque tick du positionStream.
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProvider.select((s) => s.progress));
    final buffered = ref.watch(playerProvider.select((s) => s.bufferedProgress));
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(kMiniPlayerRadius)),
      child: SizedBox(
        height: 2,
        child: CustomPaint(
          painter: _MiniBufferPainter(progress: progress, buffered: buffered),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MiniBufferPainter extends CustomPainter {
  final double progress;
  final double buffered;
  const _MiniBufferPainter({required this.progress, required this.buffered});

  @override
  void paint(Canvas canvas, Size size) {
    // Fond
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = kBorderMini.withValues(alpha: 0.5),
    );
    // Zone bufferisée
    if (buffered > progress) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * buffered, size.height),
        Paint()..color = kAccent.withValues(alpha: 0.35),
      );
    }
    // Zone jouée
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * progress, size.height),
      Paint()..color = kAccent,
    );
  }

  @override
  bool shouldRepaint(_MiniBufferPainter old) =>
      old.progress != progress || old.buffered != buffered;
}
