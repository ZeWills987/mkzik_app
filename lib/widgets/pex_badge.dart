import 'package:flutter/material.dart';
import '../models/pex.dart';
import '../theme/app_theme.dart';

/// Badge Mini-Pex (remix / slowed / mashup…) : icône Material + libellé.
/// [compact] = version réduite pour les listes.
class PexBadge extends StatelessWidget {
  final PexTag tag;
  final bool compact;
  const PexBadge({super.key, required this.tag, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 11.0 : 13.0;
    final fontSize = compact ? 10.0 : 11.5;
    final hPad = compact ? 7.0 : 9.0;
    final vPad = compact ? 3.0 : 4.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, color: kAccentLight, size: iconSize),
          SizedBox(width: compact ? 3 : 5),
          Text(
            tag.label,
            style: TextStyle(
              color: kAccentLight,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
