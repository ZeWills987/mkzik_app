import 'package:flutter/material.dart';

/// Texte sur une seule ligne qui **défile s'il dépasse** la largeur disponible,
/// sinon reste statique.
///
/// Rythme pensé pour l'UX : pause au début → défilement jusqu'au bout →
/// pause à la fin → retour au début → (boucle). Rien ne bouge tant que le
/// texte tient dans la largeur.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double velocity; // vitesse de défilement en pixels/seconde
  final Duration pause; // temps d'arrêt à chaque extrémité

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 30,
    this.pause = const Duration(seconds: 2),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Animation<double>? _anim;
  double _maxScroll = -1; // distance de débordement actuellement configurée

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Construit la séquence : pause → aller → pause → retour, à vitesse constante.
  void _configure(double maxScroll) {
    _maxScroll = maxScroll;
    final scrollSeconds = (maxScroll / widget.velocity).clamp(0.4, 60.0);
    final pauseSeconds = widget.pause.inMilliseconds / 1000.0;

    _ctrl.duration = Duration(milliseconds: ((pauseSeconds * 2 + scrollSeconds * 2) * 1000).round());
    _anim = TweenSequence<double>([
      // Pause au début (texte calé à gauche)
      TweenSequenceItem(tween: ConstantTween(0.0), weight: pauseSeconds),
      // Aller : début → fin
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: maxScroll).chain(CurveTween(curve: Curves.easeInOut)),
        weight: scrollSeconds,
      ),
      // Pause à la fin
      TweenSequenceItem(tween: ConstantTween(maxScroll), weight: pauseSeconds),
      // Retour : fin → début
      TweenSequenceItem(
        tween: Tween(begin: maxScroll, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: scrollSeconds,
      ),
    ]).animate(_ctrl);

    // Démarrage post-frame pour ne pas muter le contrôleur pendant le build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        // Le texte rentre → statique, on arrête toute animation en cours.
        if (tp.width <= maxWidth) {
          if (_ctrl.isAnimating) _ctrl.stop();
          _maxScroll = -1;
          return Text(widget.text, style: widget.style, maxLines: 1, softWrap: false);
        }

        // Débordement → (re)configure si la distance a changé (nouveau titre/largeur).
        final maxScroll = tp.width - maxWidth;
        if (_maxScroll != maxScroll) _configure(maxScroll);

        return SizedBox(
          width: maxWidth,
          height: tp.height,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: tp.height,
              maxHeight: tp.height,
              child: AnimatedBuilder(
                animation: _anim!,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-_anim!.value, 0),
                  child: child,
                ),
                child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
              ),
            ),
          ),
        );
      },
    );
  }
}
