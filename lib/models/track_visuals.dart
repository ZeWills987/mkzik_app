import 'package:flutter/material.dart';
import 'track.dart';

/// Décor de fond du player modal (dérivé de l'identité du track).
enum SceneType { pyramid, city, stars }

// Palette de dégradés stable dérivée d'un seed (identité visuelle du track).
const _kPalettes = <List<Color>>[
  [Color(0xFF9B6BF2), Color(0xFF5A2DBF), Color(0xFF1A0A4A)],
  [Color(0xFFE8375A), Color(0xFF8B1A3A), Color(0xFF3D0A1A)],
  [Color(0xFF4A90D9), Color(0xFF2C5FA8), Color(0xFF0D2060)],
  [Color(0xFF1DD9B8), Color(0xFF0F8A74), Color(0xFF043D32)],
  [Color(0xFFE87B3A), Color(0xFFB04010), Color(0xFF5A1A00)],
  [Color(0xFF31C5F4), Color(0xFF2476B8), Color(0xFF0D2A4A)],
  [Color(0xFFFFD060), Color(0xFFD4960A), Color(0xFF7A5200)],
];

/// Dégradé déterministe à partir d'un seed (réutilisé pour avatars, etc.).
List<Color> gradientForSeed(int seed) => _kPalettes[seed.abs() % _kPalettes.length];

/// Habillage visuel dérivé d'une [Track] — séparé du modèle de domaine.
/// Disponible partout où `track_visuals.dart` est importé.
extension TrackVisuals on Track {
  /// Dégradé d'habillage (fallback de cover, fond du player, vignettes…).
  List<Color> get gradientColors => gradientForSeed(visualSeed);

  /// Couleur d'accent principale (glow, waveform, boutons).
  Color get accent => gradientColors.first;

  /// Décor de fond du player modal, déterministe par track.
  SceneType get scene => SceneType.values[visualSeed.abs() % SceneType.values.length];
}
