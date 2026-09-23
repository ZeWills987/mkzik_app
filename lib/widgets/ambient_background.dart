import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fond ambiant animé (style Spotify) : quelques halos de couleur qui dérivent
/// lentement les uns sur les autres. Dérivé des couleurs du titre en cours.
///
/// Rendu volontairement léger : des dégradés radiaux (aucun blur GPU), repeints
/// ~20 fois par seconde et isolés dans un [RepaintBoundary]. L'animation est
/// désactivée si l'utilisateur a demandé la réduction des animations.
class AmbientBackground extends StatefulWidget {
  final List<Color> colors;
  final double opacity;

  const AmbientBackground({super.key, required this.colors, this.opacity = 0.55});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    if (still && _c.isAnimating) _c.stop();
    if (!still && !_c.isAnimating) _c.repeat();

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _AmbientPainter(
              t: _c.value,
              colors: widget.colors,
              opacity: widget.opacity,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final double t; // 0 → 1, boucle
  final List<Color> colors;
  final double opacity;

  _AmbientPainter({required this.t, required this.colors, required this.opacity});

  // Trajectoires lentes et décalées : chaque halo suit sa propre courbe.
  static const _paths = <({double fx, double fy, double px, double py, double r})>[
    (fx: 1, fy: 2, px: 0.0, py: 0.4, r: 0.75),
    (fx: 2, fy: 1, px: 1.1, py: 2.2, r: 0.62),
    (fx: 1, fy: 3, px: 2.4, py: 1.0, r: 0.85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = size.shortestSide;
    for (var i = 0; i < _paths.length; i++) {
      final p = _paths[i];
      final a = 2 * math.pi * t;
      final cx = size.width * (0.5 + 0.34 * math.sin(a * p.fx + p.px));
      final cy = size.height * (0.5 + 0.30 * math.cos(a * p.fy + p.py));
      final color = colors[i % colors.length];
      final radius = base * p.r;
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius)),
      );
    }
    // Voile sombre : garde le texte lisible quels que soient les halos.
    canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      // ~20 fps : un repeint tous les 3 frames suffit pour un mouvement aussi lent.
      (old.t * 480).floor() != (t * 480).floor() ||
      old.colors != colors ||
      old.opacity != opacity;
}
