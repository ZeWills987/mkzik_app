import 'package:flutter/material.dart';
import 'search_suggestions.dart' show SectionLabel;

/// Vue par défaut (champ vide) : grille de genres à explorer.
/// [onGenre] est appelé avec le libellé du genre tapé (→ lance une recherche).
class ExploreView extends StatelessWidget {
  final ValueChanged<String> onGenre;
  const ExploreView({super.key, required this.onGenre});

  static const _genres = [
    ('HIP-HOP', [Color(0xFF9B6BF2), Color(0xFF5A2DBF)]),
    ('ELECTRONIC', [Color(0xFF4A90D9), Color(0xFF2C5FA8)]),
    ('POP', [Color(0xFFE8506E), Color(0xFFB02340)]),
    ('R&B', [Color(0xFF2BB463), Color(0xFF157A3E)]),
    ('INDIE', [Color(0xFFB466E8), Color(0xFF7A2DBF)]),
    ('JAZZ', [Color(0xFFE8A23A), Color(0xFFC26A0A)]),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SectionLabel('EXPLORER'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: _genres
              .map((g) => _GenreCard(label: g.$1, colors: g.$2, onTap: () => onGenre(g.$1)))
              .toList(),
        ),
      ],
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  const _GenreCard({required this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Stack(
          children: [
            // Reflet lumineux
            Positioned(
              right: -10,
              top: -10,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Colors.white.withValues(alpha: 0.25), Colors.transparent],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
