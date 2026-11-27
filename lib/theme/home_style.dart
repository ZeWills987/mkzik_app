import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Style de l'accueil, repris de la maquette https://mkzik-redesign.lumi.ing/.
/// Limité à l'accueil : le thème global (app_theme.dart) reste inchangé.

const kHomeBg = Color(0xFF070510); // fond violet très sombre
const kHomeInk = Color(0xFFF5F2FF); // texte principal
const kHomeInkSoft = Color(0xBFF5F2FF); // texte secondaire (75 %)
const kHomeInkFaint = Color(0x80F5F2FF); // libellés discrets (50 %)
const kHomeLine = Color(0x1AFFFFFF); // bordures fines (10 %)
const kHomeCoral = Color(0xFFFF6B57); // repères : « À LA UNE », « NOUVEAU »
const kHomeViolet = Color(0xFF7C5CFC); // accent (identique à kAccent)
const kHomeVioletSoft = Color(0xFFA99BFF); // sous-titres teintés

/// Titres : Bricolage Grotesque, graisse forte, interlettrage serré.
TextStyle homeDisplay({double size = 24, FontWeight weight = FontWeight.w800, Color color = kHomeInk, double? height}) =>
    GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height ?? 1.0,
      letterSpacing: -size * 0.04,
    );

/// Texte courant : Inter.
TextStyle homeBody({double size = 14, FontWeight weight = FontWeight.w500, Color color = kHomeInk, double? height}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

/// Étiquettes techniques (MKZ-014, GENRE, ÉCOUTES…) : JetBrains Mono en capitales espacées.
TextStyle homeMono({double size = 10, Color color = kHomeInkFaint, double spacing = 1.6, FontWeight weight = FontWeight.w400}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color, letterSpacing: spacing, fontWeight: weight);

/// Numéro de catalogue d'un titre : « MKZ-014 » (null si l'id numérique est inconnu).
String? homeCatalogCode(int? apiId) => apiId == null ? null : 'MKZ-${apiId.toString().padLeft(3, '0')}';
