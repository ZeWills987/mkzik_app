import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Au-delà de cette largeur, les feuilles s'affichent en dialog centré (desktop)
/// plutôt qu'en bottom sheet glissant depuis le bas (mobile).
const double _kWideBreakpoint = 800;

/// Présente [builder] de façon adaptative :
/// - fenêtre étroite (mobile) → bottom sheet arrondi en bas
/// - fenêtre large (desktop)  → dialog centré à largeur contrainte
///
/// Les widgets internes utilisent `Navigator.pop(context)` de la même manière
/// dans les deux cas, donc aucun changement de câblage n'est nécessaire.
///
/// [tall] : la feuille peut monter jusqu'à toute la hauteur de l'écran (sinon
/// Flutter la plafonne à ~56 % sur mobile) — c'est au contenu de fixer sa taille.
/// [glass] : fond « liquid glass » (translucide + flou) au lieu du fond plein.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool tall = false,
  bool glass = false,
}) {
  final wide = MediaQuery.of(context).size.width >= _kWideBreakpoint;

  if (!wide) {
    const radius = BorderRadius.vertical(top: Radius.circular(20));
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: tall,
      useSafeArea: tall,
      backgroundColor: glass ? Colors.transparent : kSheetBg,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      builder: glass ? (ctx) => _Glass(radius: radius, child: builder(ctx)) : builder,
    );
  }

  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * (tall ? 0.92 : 0.75);
      final radius = BorderRadius.circular(16);
      final content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: builder(ctx),
      );
      return Dialog(
        backgroundColor: glass ? Colors.transparent : kSheetBg,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: glass ? _Glass(radius: radius, child: content) : content,
      );
    },
  );
}

/// Verre dépoli : flou du fond + voile translucide + liseré clair.
class _Glass extends StatelessWidget {
  final BorderRadius radius;
  final Widget child;
  const _Glass({required this.radius, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: kSheetBg.withValues(alpha: 0.72),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}
