import 'package:flutter/material.dart';

const kAccent = Color(0xFF7C5CFC);
const kAccentLight = Color(0xFFA084FD);
const kBg = Color(0xFF0D0D0D);
const kSurface = Color(0xFF1A1A2E);
const kCard = Color(0xFF16213E);
const kCardAlt = Color(0xFF1E1E30);
const kTextPrimary = Color(0xFFFFFFFF);
const kTextSecondary = Color(0xFFAAAAAA);
const kMiniPlayerBg = Color(0xFF1C1C2E);

// Chrome / bordures / surfaces secondaires
const kBorder = Color(0xFF2A2A40); // bordures champs, barres
const kBorderSoft = Color(0xFF26263A); // séparateurs, contours discrets
const kBorderMini = Color(0xFF2A2A4A); // bordure/piste du mini-player
const kSheetBg = Color(0xFF15151F); // fond des bottom sheets
const kDivider = Color(0xFF1E1E2E); // diviseurs

// Sémantiques
const kError = Color(0xFFE8375A); // rouge erreur (bordure/fond)
const kErrorText = Color(0xFFE8607A); // texte erreur
const kUserBlue = Color(0xFF4A90D9); // avatars / badge USER
const kBadgeGray = Color(0xFF8A8AA0); // badge EXT

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    primaryColor: kAccent,
    colorScheme: const ColorScheme.dark(
      primary: kAccent,
      secondary: kAccentLight,
      surface: kSurface,
    ),
    fontFamily: 'Nunito',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800, fontSize: 24),
      headlineMedium: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 20),
      titleLarge: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600, fontSize: 16),
      titleMedium: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w500, fontSize: 14),
      bodyMedium: TextStyle(color: kTextSecondary, fontSize: 13),
      labelSmall: TextStyle(color: kTextSecondary, fontSize: 11),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kSurface,
      selectedItemColor: kAccent,
      unselectedItemColor: kTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
