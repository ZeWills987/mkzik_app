import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Barre de recherche en haut de l'écran : champ texte + bouton effacer.
class SearchInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool hasText;

  const SearchInputBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: kAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                cursorColor: kAccent,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Rechercher...',
                  hintStyle: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w400),
                ),
              ),
            ),
            if (hasText)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: kBorder, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: kTextSecondary, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
