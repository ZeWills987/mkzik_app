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
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final wide = MediaQuery.of(context).size.width >= _kWideBreakpoint;

  if (!wide) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: kSheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: builder,
    );
  }

  final maxHeight = MediaQuery.of(context).size.height * 0.75;
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: kSheetBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: builder(ctx),
      ),
    ),
  );
}
