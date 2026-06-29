import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/track_visuals.dart';

/// Décor de fond du player (utilisé quand le morceau n'a pas de pochette) :
/// trame de losanges subtile + scène thématique (pyramide / ville / étoiles)
/// dérivée de [Track.scene]. La couleur vient de l'accent du morceau.
class ScenePainter extends CustomPainter {
  final SceneType scene;
  final Color accent;

  ScenePainter({required this.scene, required this.accent});

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
  bool shouldRepaint(ScenePainter old) => old.scene != scene || old.accent != accent;
}
