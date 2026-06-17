import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration centrale de l'API Mkzik.
///
/// Les URLs sont lues depuis le fichier `.env` à la racine du projet :
///   API_URL    → [baseUrl]   (Symfony, équivaut à VITE_API_URL)
///   PYTHON_URL → [pythonUrl] (recherche externe, équivaut à VITE_PYTHON_URL)
///
/// ⚠️ Sur un appareil physique, `localhost` désigne le téléphone lui-même.
/// Utilise l'IP LAN de ta machine (ex: 192.168.1.x) dans le `.env`.
class ApiConfig {
  // Valeurs de secours si le .env est absent (émulateur Android par défaut).
  static const String _defaultBase = 'http://10.0.2.2:8000/';
  static const String _defaultPython = 'http://10.0.2.2:5000/';

  static String get baseUrl => _normalize(dotenv.maybeGet('API_URL') ?? _defaultBase);
  static String get pythonUrl => _normalize(dotenv.maybeGet('PYTHON_URL') ?? _defaultPython);

  // Jeton JWT courant (injecté par l'AuthProvider après connexion).
  static String? token;

  /// Repli sur des données de démonstration quand l'API ne renvoie rien.
  /// ⚠️ Laisser `false` en production : sinon les vraies erreurs API sont
  /// masquées par de faux contenus. Mettre DEMO=true dans le .env pour l'activer.
  static bool get useDemoData => (dotenv.maybeGet('DEMO') ?? 'false').toLowerCase() == 'true';

  // Garantit un slash final (les routes sont construites en "${baseUrl}api/...")
  static String _normalize(String url) => url.endsWith('/') ? url : '$url/';
}
