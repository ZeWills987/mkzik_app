import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/logger.dart';

/// Résultat typé d'un appel API : succès (données) ou échec (message).
/// Remplace les `catch (_) => null/[]` qui avalaient les erreurs.
sealed class ApiResult<T> {
  const ApiResult();

  bool get isOk => this is Ok<T>;

  /// Donnée si succès, sinon [fallback].
  T orElse(T fallback) => switch (this) {
        Ok<T>(:final data) => data,
        Err<T>() => fallback,
      };
}

class Ok<T> extends ApiResult<T> {
  final T data;
  const Ok(this.data);
}

class Err<T> extends ApiResult<T> {
  final String message;
  final int? statusCode;
  const Err(this.message, {this.statusCode});
}

/// Client HTTP unique : headers, timeout, décodage et gestion d'erreurs
/// centralisés. Toutes les erreurs sont loggées (plus de silence).
class ApiClient {
  static const _timeout = Duration(seconds: 12);

  /// Déclenché quand une requête **authentifiée** se voit refuser par un 401
  /// (token expiré/invalide) → la couche auth s'y abonne pour déconnecter
  /// l'utilisateur au lieu de le laisser coincé. Branché par `AuthNotifier`.
  static void Function()? onUnauthorized;

  static Map<String, String> _headers(bool auth) => {
        'Content-Type': 'application/json',
        if (auth && (ApiConfig.token?.isNotEmpty ?? false)) 'Authorization': 'Bearer ${ApiConfig.token}',
      };

  static Future<ApiResult<dynamic>> getUri(Uri uri, {bool auth = true, Duration? timeout}) =>
      _send('GET', uri, auth: auth, timeout: timeout);

  static Future<ApiResult<dynamic>> postUri(Uri uri, {Object? body, bool auth = true}) =>
      _send('POST', uri, body: body, auth: auth);

  static Future<ApiResult<dynamic>> putUri(Uri uri, {Object? body, bool auth = true}) =>
      _send('PUT', uri, body: body, auth: auth);

  static Future<ApiResult<dynamic>> patchUri(Uri uri, {Object? body, bool auth = true}) =>
      _send('PATCH', uri, body: body, auth: auth);

  static Future<ApiResult<dynamic>> deleteUri(Uri uri, {Object? body, bool auth = true}) =>
      _send('DELETE', uri, body: body, auth: auth);

  static Future<ApiResult<dynamic>> _send(
    String method,
    Uri uri, {
    Object? body,
    bool auth = true,
    Duration? timeout,
  }) async {
    try {
      final headers = _headers(auth);
      final encoded = body == null ? null : jsonEncode(body);
      final t = timeout ?? _timeout;

      final http.Response res = await switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: encoded),
        'PUT' => http.put(uri, headers: headers, body: encoded),
        'PATCH' => http.patch(uri, headers: headers, body: encoded),
        'DELETE' => http.delete(uri, headers: headers, body: encoded),
        _ => throw ArgumentError('Méthode non supportée: $method'),
      }
          .timeout(t);

      return _handle(method, uri, res, auth: auth);
    } on TimeoutException {
      _log(method, uri, 'délai dépassé');
      return const Err('Délai dépassé, réessaie', statusCode: 408);
    } catch (e) {
      _log(method, uri, e);
      return const Err('Connexion au serveur impossible');
    }
  }

  static ApiResult<dynamic> _handle(String method, Uri uri, http.Response res, {required bool auth}) {
    final decoded = _tryDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Ok(decoded);
    }
    final message = _extractError(decoded) ?? 'Erreur ${res.statusCode}';
    _log(method, uri, 'HTTP ${res.statusCode} → $message');
    // Token rejeté sur une requête authentifiée → session expirée : on prévient
    // la couche auth pour déconnecter (les appels publics, auth:false, sont ignorés).
    if (auth && res.statusCode == 401) onUnauthorized?.call();
    return Err(message, statusCode: res.statusCode);
  }

  static dynamic _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // L'API renvoie message / error / detail, en string ou en liste
  static String? _extractError(dynamic decoded) {
    if (decoded is! Map) return null;
    final e = decoded['message'] ?? decoded['error'] ?? decoded['detail'];
    if (e == null) return null;
    if (e is List) return e.join(', ');
    return e.toString();
  }

  static void _log(String method, Uri uri, Object info) {
    mkLog('Mkzik API ✕ $method ${uri.path} : $info');
  }
}
