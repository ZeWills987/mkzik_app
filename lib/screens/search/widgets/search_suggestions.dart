import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/track_actions.dart';
import '../search_controller.dart';

/// Petit libellé de section ("EXPLORER", "SUGGESTIONS"…). Partagé.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(text,
          style: const TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
    );
  }
}

/// Badge de source (ZIK / USER / EXT).
class _SourceBadge extends StatelessWidget {
  final SearchTab kind;
  const _SourceBadge(this.kind);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      SearchTab.zik => ('ZIK', kAccent),
      SearchTab.user => ('USER', kUserBlue),
      SearchTab.external => ('EXT', kBadgeGray),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }
}

/// Ligne de suggestion (autocomplétion) : vignette + libellé surligné + badge source.
class SuggestionRow extends StatelessWidget {
  final Suggestion suggestion;
  final String query;
  final VoidCallback onTap;

  const SuggestionRow({super.key, required this.suggestion, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUser = suggestion.kind == SearchTab.user;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Vignette
            if (isUser)
              CircleAvatar(
                radius: 18,
                backgroundColor: kUserBlue,
                child: Text(
                  suggestion.label.isNotEmpty ? suggestion.label[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              )
            else if (suggestion.track != null)
              TrackSquareThumb(track: suggestion.track!)
            else
              const SizedBox(width: 36, height: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlight(suggestion.label, query),
                  const SizedBox(height: 2),
                  Text(suggestion.subtitle,
                      style: const TextStyle(color: kTextSecondary, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Externe → logo de la plateforme ; sinon badge ZIK / USER
            if (suggestion.kind == SearchTab.external && suggestion.track != null)
              PlatformBadge(track: suggestion.track!)
            else
              _SourceBadge(suggestion.kind),
          ],
        ),
      ),
    );
  }

  // Met en évidence la portion qui matche la requête (en accent)
  Widget _highlight(String label, String query) {
    final lower = label.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (q.isEmpty || idx < 0) {
      return Text(label,
          style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        children: [
          TextSpan(text: label.substring(0, idx), style: const TextStyle(color: kTextPrimary)),
          TextSpan(text: label.substring(idx, idx + q.length), style: const TextStyle(color: kAccent)),
          TextSpan(text: label.substring(idx + q.length), style: const TextStyle(color: kTextPrimary)),
        ],
      ),
    );
  }
}

/// Ligne d'une recherche récente.
class RecentRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const RecentRow({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.history, color: kTextSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.north_west, color: kTextSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}
