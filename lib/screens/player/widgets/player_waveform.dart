import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Waveform interactive du player : tap pour viser une position, glissement
/// horizontal (maintien) pour scrubber. Le rendu suit le doigt pendant le scrub,
/// sinon la progression de lecture.
class PlayerWaveform extends StatefulWidget {
  final double progress;
  final Duration duration;
  final Color accent;
  final int seed;
  final ValueChanged<Duration> onSeek;

  const PlayerWaveform({
    super.key,
    required this.progress,
    required this.duration,
    required this.accent,
    required this.seed,
    required this.onSeek,
  });

  @override
  State<PlayerWaveform> createState() => _PlayerWaveformState();
}

class _PlayerWaveformState extends State<PlayerWaveform> {
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
