import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance locale du jeton JWT.
///
/// Stocké dans le **stockage chiffré** de la plateforme (Android Keystore via
/// EncryptedSharedPreferences, iOS Keychain) — et non plus en `SharedPreferences`
/// en clair. Migration automatique one-shot depuis l'ancien emplacement pour ne
/// pas déconnecter les utilisateurs déjà connectés lors de la mise à jour.
class TokenStorage {
  static const _key = 'token';

  // Chiffrement au repos : Keystore (Android) / Keychain (iOS).
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<String?> read() async {
    final token = await _secure.read(key: _key);
    if (token != null && token.isNotEmpty) return token;
    // Pas de jeton en stockage chiffré → tente une migration depuis l'ancien
    // SharedPreferences (legacy), puis nettoie l'ancien emplacement.
    return _migrateLegacy();
  }

  static Future<void> write(String token) async {
    await _secure.write(key: _key, value: token);
  }

  static Future<void> clear() async {
    await _secure.delete(key: _key);
    // Purge aussi l'éventuel jeton legacy resté en clair.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// Migre un jeton stocké en clair par une ancienne version (SharedPreferences)
  /// vers le stockage chiffré, puis supprime l'ancien. Renvoie le jeton migré.
  static Future<String?> _migrateLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_key);
      if (legacy == null || legacy.isEmpty) return null;
      await _secure.write(key: _key, value: legacy);
      await prefs.remove(_key);
      return legacy;
    } catch (_) {
      return null;
    }
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
