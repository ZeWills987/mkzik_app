import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Widget d'état vide générique : icône + titre + sous-titre + bouton optionnel.
/// Utilisable en plein écran (Expanded/SliverFillRemaining) ou inline
/// dans une SizedBox (sections horizontales du home).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  /// true = plein écran (centré verticalement), false = compact (haut + padding)
  final bool fullScreen;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.fullScreen = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: kAccent.withValues(alpha: 0.7), size: 26),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );

    if (fullScreen) {
      return Center(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: content),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Center(child: content),
    );
  }
}
