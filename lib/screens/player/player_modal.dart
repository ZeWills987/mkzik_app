import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
// On masque RepeatMode de Flutter pour utiliser celui du provider
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/player_provider.dart';
import '../../providers/notice_provider.dart';
import '../../widgets/current_list_sheet.dart';
import '../../widgets/track_cover.dart';
import '../../utils/media.dart';
import '../profile/profile_screen.dart';

/// Player modal plein écran.
///
/// Tout le thème (fond, glow, dégradé du titre, waveform, bouton play, décor)
/// est dérivé de [Track.gradientColors] → chaque morceau a sa propre ambiance.
class PlayerModal extends ConsumerStatefulWidget {
  const PlayerModal({super.key});

  /// Ouvre le modal en bottom-sheet plein écran avec animation de montée.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (ctx, anim, secAnim) => const PlayerModal(),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  ConsumerState<PlayerModal> createState() => _PlayerModalState();
}

class _PlayerModalState extends ConsumerState<PlayerModal>
    with SingleTickerProviderStateMixin {
  // Décalage vertical courant pendant le glissement (0 = position fermée/haute)
  double _dragOffset = 0;
  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // On ne suit que vers le bas (offset >= 0)
    setState(() => _dragOffset = math.max(0, _dragOffset + d.delta.dy));
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final h = MediaQuery.of(context).size.height;
    // Ferme si glissé sur > 25% de l'écran OU geste rapide vers le bas
    if (_dragOffset > h * 0.25 || velocity > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    // Sinon : retour élastique à la position initiale
    final anim = Tween(begin: _dragOffset, end: 0.0)
        .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOut));
    void listener() => setState(() => _dragOffset = anim.value);
    anim.addListener(listener);
    _snap.forward(from: 0).whenComplete(() => anim.removeListener(listener));
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final notifier = ref.read(playerProvider.notifier);
    final colors = track.gradientColors;
    final accent = track.accent;
    final accentLight = _lighten(accent, 0.18);
    final coverUrl = mediaUrl(track.coverUrl);
    final artSize = (MediaQuery.of(context).size.width * 0.58).clamp(150.0, 300.0);

    final screenH = MediaQuery.of(context).size.height;
    final dragT = (_dragOffset / screenH).clamp(0.0, 1.0);

    return GestureDetector(
      // Glisser vers le bas n'importe où sur le fond pour fermer
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(
          opacity: (1 - dragT * 0.7).clamp(0.0, 1.0),
          child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Fond : pochette floutée (style Apple Music) ou dégradé du track ─
          if (coverUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55, tileMode: TileMode.clamp),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const ColoredBox(color: Color(0xFF101014)),
                ),
              ),
            )
          else ...[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _darken(colors.length > 1 ? colors[1] : accent, 0.35),
                      _darken(colors.last, 0.55),
                      const Color(0xFF050507),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _ScenePainter(scene: track.scene, accent: accent),
              ),
            ),
          ],

          // Scrim sombre vertical → lisibilité du texte et des contrôles
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.52),
                    Colors.black.withValues(alpha: 0.86),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Halo accent subtil (ambiance du morceau)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.1, -0.7),
                  radius: 1.1,
                  colors: [accent.withValues(alpha: 0.30), Colors.transparent],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Poignée + bouton fermer
                _TopBar(
                  onClose: () => Navigator.of(context).maybePop(),
                  onQueue: () => showCurrentList(context),
                ),

                const Spacer(flex: 2),

                // Pochette nette (style Apple Music) — cadre verre + ombre portée
                Container(
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 40,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  child: TrackCover(track: track, size: artSize, radius: 24),
                ),

                const SizedBox(height: 26),

                // Titre + artiste centrés
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      _GradientText(
                        track.title.toUpperCase(),
                        colors: [Colors.white, accentLight, Colors.white],
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      // Artiste cliquable → son profil (ferme le modal d'abord)
                      GestureDetector(
                        onTap: track.artist.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).maybePop();
                                ProfileScreen.open(context, track.artist);
                              },
                        child: Text(
                          track.artist.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accentLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                // ── Panneau "liquid glass" : toutes les commandes ────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _glassPanel(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      child: Column(
                        children: [
                          // Barre d'actions : LIKE / LYRICS / SHARE / MORE
                          _ActionsRow(
                            isLiked: player.isLiked,
                            likes: track.likesLabel,
                            accent: accent,
                            onLike: notifier.toggleLike,
                            onShare: () {
                              Clipboard.setData(ClipboardData(
                                  text: track.pageUrl.isNotEmpty ? track.pageUrl : track.title));
                              ref.read(noticeProvider.notifier).show('Lien copié', icon: NoticeIcon.share);
                            },
                          ),
                          const SizedBox(height: 18),
                          // Waveform + temps
                          _Waveform(
                            progress: player.progress,
                            duration: player.duration,
                            accent: accentLight,
                            seed: track.id.hashCode,
                            onSeek: notifier.seekTo,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(player.positionFormatted,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              Text(
                                player.duration == Duration.zero
                                    ? track.durationFormatted
                                    : player.durationFormatted,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Shuffle · prev · play · next · repeat
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: notifier.toggleShuffle,
                                child: Icon(
                                  Icons.shuffle,
                                  size: 22,
                                  color: player.isShuffle ? accentLight : Colors.white54,
                                ),
                              ),
                              const SizedBox(width: 22),
                              _ControlButton(
                                icon: Icons.skip_previous,
                                enabled: player.canSkip,
                                onTap: notifier.previous,
                              ),
                              const SizedBox(width: 20),
                              _PlayButton(
                                isPlaying: player.isPlaying,
                                colors: [accentLight, accent],
                                onTap: notifier.togglePlayPause,
                              ),
                              const SizedBox(width: 20),
                              _ControlButton(
                                icon: Icons.skip_next,
                                enabled: player.canSkip,
                                onTap: notifier.next,
                              ),
                              const SizedBox(width: 22),
                              GestureDetector(
                                onTap: notifier.cycleRepeat,
                                child: Icon(
                                  player.repeatMode == RepeatMode.one
                                      ? Icons.repeat_one
                                      : Icons.repeat,
                                  size: 22,
                                  color: accentLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
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

// ── Barre supérieure : poignée + fermeture ───────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onQueue;
  const _TopBar({required this.onClose, required this.onQueue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          // Poignée de glissement
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 28),
              ),
              const Spacer(),
              // Ouvre la file d'attente (titres à venir)
              IconButton(
                onPressed: onQueue,
                icon: const Icon(Icons.queue_music, color: Colors.white70, size: 24),
                tooltip: 'File d\'attente',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Barre d'actions ───────────────────────────────────────────────────────────

class _ActionsRow extends StatelessWidget {
  final bool isLiked;
  final String likes;
  final Color accent;
  final VoidCallback onLike;
  final VoidCallback onShare;

  const _ActionsRow({
    required this.isLiked,
    required this.likes,
    required this.accent,
    required this.onLike,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          label: 'LIKE',
          sublabel: likes,
          color: isLiked ? accent : Colors.white,
          onTap: onLike,
        ),
        _ActionItem(icon: Icons.mic_none, label: 'LYRICS', onTap: () {}),
        _ActionItem(icon: Icons.ios_share, label: 'SHARE', onTap: onShare),
        _ActionItem(icon: Icons.more_horiz, label: 'MORE', onTap: () {}),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    this.sublabel,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(sublabel!, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

// ── Boutons de contrôle ───────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 34),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final List<Color> colors;
  final VoidCallback onTap;

  const _PlayButton({required this.isPlaying, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(color: colors.last.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 2),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}

// ── Texte avec dégradé ────────────────────────────────────────────────────────

class _GradientText extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final TextStyle style;
  final TextAlign textAlign;

  const _GradientText(this.text,
      {required this.colors, required this.style, this.textAlign = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ).createShader(bounds),
      child: Text(text, textAlign: textAlign, style: style.copyWith(color: Colors.white)),
    );
  }
}

// ── Waveform interactive (tap + scrub au glissement) ─────────────────────────

class _Waveform extends StatefulWidget {
  final double progress;
  final Duration duration;
  final Color accent;
  final int seed;
  final ValueChanged<Duration> onSeek;

  const _Waveform({
    required this.progress,
    required this.duration,
    required this.accent,
    required this.seed,
    required this.onSeek,
  });

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  // Position visée pendant le glissement (null = pas de scrub en cours)
  double? _dragRatio;

  void _seekAt(double dx, double width) {
    final ratio = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragRatio = ratio);
    if (widget.duration > Duration.zero) {
      widget.onSeek(widget.duration * ratio);
    }
  }

  void _endScrub() => setState(() => _dragRatio = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Tap simple
          onTapDown: (d) => _seekAt(d.localPosition.dx, w),
          onTapUp: (_) => _endScrub(),
          onTapCancel: _endScrub,
          // Glissement (maintien) horizontal → scrub
          onHorizontalDragStart: (d) => _seekAt(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _seekAt(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _endScrub(),
          onHorizontalDragCancel: _endScrub,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                // Pendant le scrub on suit le doigt, sinon la lecture
                progress: _dragRatio ?? widget.progress,
                accent: widget.accent,
                seed: widget.seed,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── CustomPainter : waveform ──────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final int seed;

  _WaveformPainter({required this.progress, required this.accent, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    const barW = 3.0;
    const gap = 3.0;
    final count = (size.width / (barW + gap)).floor();
    final mid = size.height / 2;
    final playedX = size.width * progress;

    final paintPlayed = Paint()..color = accent;
    final paintUnplayed = Paint()..color = accent.withValues(alpha: 0.25);

    for (var i = 0; i < count; i++) {
      final x = i * (barW + gap);
      // Hauteur pseudo-aléatoire lissée façon onde
      final base = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(i * 0.5 + seed % 7));
      final noise = rnd.nextDouble() * 0.5;
      final h = (size.height * 0.9) * ((base + noise) / 1.5).clamp(0.1, 1.0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barW / 2, mid), width: barW, height: h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, x <= playedX ? paintPlayed : paintUnplayed);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.accent != accent;
}

// ── CustomPainter : décor (motif losange + scène) ─────────────────────────────

class _ScenePainter extends CustomPainter {
  final SceneType scene;
  final Color accent;

  _ScenePainter({required this.scene, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    _paintDiamondPattern(canvas, size);
    switch (scene) {
      case SceneType.pyramid:
        _paintPyramid(canvas, size);
      case SceneType.city:
        _paintCity(canvas, size, withStars: false);
      case SceneType.stars:
        _paintCity(canvas, size, withStars: true);
    }
  }

  // Trame de losanges très subtile sur tout le fond
  void _paintDiamondPattern(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    const step = 34.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width + step; x += step) {
        final path = Path()
          ..moveTo(x, y + step / 2)
          ..lineTo(x + step / 2, y)
          ..lineTo(x + step, y + step / 2)
          ..lineTo(x + step / 2, y + step)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  // Lignes de perspective convergentes (ambiance "After Dark")
  void _paintPyramid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final apex = Offset(size.width / 2, size.height * 0.42);
    final baseY = size.height * 0.75;
    // Ligne d'horizon
    canvas.drawLine(Offset(0, apex.dy), Offset(size.width, apex.dy), paint..color = accent.withValues(alpha: 0.2));
    // Faisceau de lignes vers le bas
    final p2 = Paint()
      ..color = accent.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (var i = -3; i <= 3; i++) {
      final targetX = size.width / 2 + i * (size.width / 5);
      canvas.drawLine(apex, Offset(targetX, baseY), p2);
    }
    // Lignes horizontales de profondeur
    for (var i = 1; i <= 3; i++) {
      final y = apex.dy + (baseY - apex.dy) * (i / 4);
      final spread = size.width * 0.12 * i;
      canvas.drawLine(
        Offset(size.width / 2 - spread, y),
        Offset(size.width / 2 + spread, y),
        p2..color = accent.withValues(alpha: 0.18),
      );
    }
  }

  // Silhouette de ville + étoiles/météores optionnels
  void _paintCity(Canvas canvas, Size size, {required bool withStars}) {
    final rnd = math.Random(scene.index + 99);
    final horizon = size.height * 0.62;

    // Faisceaux verticaux lumineux
    final beam = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent.withValues(alpha: 0.5), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, horizon))
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.2 + i * 0.15) + rnd.nextDouble() * 20;
      canvas.drawLine(Offset(x, size.height * 0.1), Offset(x, horizon), beam);
    }

    // Étoiles + météores
    if (withStars) {
      final star = Paint()..color = Colors.white.withValues(alpha: 0.8);
      for (var i = 0; i < 40; i++) {
        final x = rnd.nextDouble() * size.width;
        final y = rnd.nextDouble() * horizon;
        canvas.drawCircle(Offset(x, y), rnd.nextDouble() * 1.2 + 0.3,
            star..color = Colors.white.withValues(alpha: rnd.nextDouble() * 0.6 + 0.2));
      }
      final meteor = Paint()
        ..color = accent.withValues(alpha: 0.7)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final sx = size.width * (0.3 + rnd.nextDouble() * 0.5);
        final sy = size.height * (0.1 + rnd.nextDouble() * 0.2);
        canvas.drawLine(Offset(sx, sy), Offset(sx + 70, sy + 40), meteor);
      }
    }

    // Silhouette des immeubles
    final building = Paint()..color = const Color(0xFF050505).withValues(alpha: 0.92);
    double x = 0;
    while (x < size.width) {
      final w = 24.0 + rnd.nextDouble() * 30;
      final h = 40.0 + rnd.nextDouble() * (size.height * 0.28);
      canvas.drawRect(Rect.fromLTWH(x, horizon - h, w, size.height - (horizon - h)), building);
      x += w + 2;
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.scene != scene || old.accent != accent;
}

// ── Panneau verre dépoli (liquid glass) ──────────────────────────────────────

Widget _glassPanel({required Widget child}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: child,
      ),
    ),
  );
}

// ── Helpers couleur ───────────────────────────────────────────────────────────

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}
