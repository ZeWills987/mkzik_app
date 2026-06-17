import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance locale du jeton JWT (équivalent du localStorage "token" côté web).
class TokenStorage {
  static const _key = 'token';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Décode le payload d'un JWT et renvoie le champ demandé (ex: "username").
/// Implémentation sans dépendance externe.
Map<String, dynamic>? decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
