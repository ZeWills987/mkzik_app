import 'package:flutter/material.dart';

/// GestureDetector + curseur "main" au survol : à utiliser à la place d'un
/// GestureDetector nu pour tout contrôle cliquable — sans ça, le desktop
/// garde la flèche par défaut et paraît inerte au survol.
class Tappable extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior? behavior;

  const Tappable({super.key, required this.onTap, required this.child, this.behavior});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, behavior: behavior, child: child),
    );
  }
}
