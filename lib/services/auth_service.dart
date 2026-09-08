import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Le SDK google_sign_in ne supporte que mobile. Sur desktop il faudra le flow
/// web OAuth (GET /connect/google) — non câblé tant que le backend n'expose pas
/// une redirection dédiée desktop (deep link mkzik://).
bool get _googleSignInSupported => Platform.isAndroid || Platform.isIOS;

final _googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile'],
  serverClientId: '209129894628-l1es9tbodhdiqq3nft1ac8kl3mjfie5l.apps.googleusercontent.com',
);

/// Erreur d'authentification avec message lisible pour l'UI.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Accès aux routes d'authentification Mkzik.
class AuthService {
  /// `POST api/login_check` body {email, password} → { token }
  static Future<String> login(String email, String password) async {
    final res = await ApiClient.postUri(
      _api('api/login_check'),
      body: {'email': email, 'password': password},
      auth: false,
    );
    return _tokenOrThrow(res, fallbackError: 'Email ou mot de passe incorrect');
  }

  /// `POST api/register` body {username, email, password, rgpdConsent, ...} → { token }
  static Future<String> register({
    required String username,
    required String email,
    required String password,
    required bool rgpdConsent,
    String? firstName,
    String? lastName,
    String? description,
    String? birthDate,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'email': email,
      'password': password,
      'rgpdConsent': rgpdConsent,
      if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      if (description != null && description.isNotEmpty) 'description': description,
      if (birthDate != null && birthDate.isNotEmpty) 'birthDate': birthDate,
    };
    final res = await ApiClient.postUri(_api('api/register'), body: body, auth: false);
    return _tokenOrThrow(res, fallbackError: "Erreur lors de l'inscription");
  }

  static String _tokenOrThrow(ApiResult<dynamic> res, {required String fallbackError}) {
    switch (res) {
      case Ok(:final data):
        final token = (data is Map ? data['token'] : null)?.toString();
        if (token == null || token.isEmpty) {
          throw AuthException('Réponse invalide du serveur');
        }
        return token;
      case Err(:final message):
        throw AuthException(message.isNotEmpty ? message : fallbackError);
    }
  }

  /// Connexion via compte Google : SDK google_sign_in → id_token
  /// → `POST /api/auth/google` {id_token} → {token: jwt mkzik}
  static Future<String> loginWithGoogle() async {
    if (!_googleSignInSupported) {
      throw AuthException(
        'La connexion Google n\'est pas encore disponible sur desktop — '
        'utilise ton email et ton mot de passe.',
      );
    }
    await _googleSignIn.signOut(); // force le sélecteur de compte
    final account = await _googleSignIn.signIn();
    if (account == null) throw AuthException('Connexion Google annulée');

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthException('Token Google invalide, réessaie');
    }

    final res = await ApiClient.postUri(
      _api('api/auth/google'),
      body: {'id_token': idToken},
      auth: false,
    );
    return _tokenOrThrow(res, fallbackError: 'Connexion Google échouée');
  }

  /// `GET /api/auth/google/connect-url[?callback=http://localhost:PORT/callback]`
  /// → URL `accounts.google.com/…`
  /// Sur Windows le `callbackUrl` local remplace le redirect_uri Symfony.
  static Future<String?> fetchGoogleConnectUrl({String? callbackUrl}) async {
    final base = _api('api/auth/google/connect-url');
    final uri = callbackUrl != null
        ? base.replace(queryParameters: {'callback': callbackUrl})
        : base;
    final res = await ApiClient.getUri(uri, auth: false);
    final data = res.orElse(null);
    if (data is Map) return data['url']?.toString();
    return null;
  }

  /// `POST /api/auth/google/exchange-code {code, redirect_uri}` → `{token}`
  /// Échange le code OAuth reçu par le serveur local contre un JWT Mkzik.
  static Future<String?> exchangeGoogleCode({
    required String code,
    required String redirectUri,
  }) async {
    final res = await ApiClient.postUri(
      _api('api/auth/google/exchange-code'),
      body: {'code': code, 'redirect_uri': redirectUri},
      auth: false,
    );
    final data = res.orElse(null);
    if (data is Map) return data['token']?.toString();
    return null;
  }

  /// POST /api/password/forgot — envoie le lien de réinitialisation par mail.
  /// L'API renvoie toujours 200 (anti-énumération) ; seul le 400 (email invalide)
  /// lève une exception.
  static Future<void> forgotPassword(String email) async {
    final res = await ApiClient.postUri(
      _api('api/password/forgot'),
      body: {'email': email},
      auth: false,
    );
    if (res case Err(:final message)) {
      throw AuthException(message.isNotEmpty ? message : "Erreur lors de l'envoi");
    }
  }

  /// POST /api/password/reset — réinitialise le mot de passe via le token reçu par mail.
  static Future<void> resetPassword(String token, String newPassword) async {
    final res = await ApiClient.postUri(
      _api('api/password/reset'),
      body: {'token': token, 'password': newPassword},
      auth: false,
    );
    if (res case Err(:final message)) {
      throw AuthException(message.isNotEmpty ? message : 'Réinitialisation impossible');
    }
  }

  /// PUT /api/update — met à jour les champs fournis (username, email, password).
  /// Les champs absents ne sont pas modifiés.
  static Future<void> updateAccount({String? username, String? email, String? password}) async {
    final body = <String, dynamic>{
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (password != null) 'password': password,
    };
    final res = await ApiClient.putUri(_api('api/update'), body: body);
    if (res case Err(:final message)) {
      throw AuthException(message.isNotEmpty ? message : 'Mise à jour impossible');
    }
  }

  /// DELETE /api/delete_account — supprime le compte définitivement.
  /// Requiert le mot de passe actuel et sa confirmation.
  static Future<void> deleteAccount(String password, String passwordConfirmation) async {
    final res = await ApiClient.deleteUri(
      _api('api/delete_account'),
      body: {'password': password, 'passwordConfirmation': passwordConfirmation},
    );
    if (res case Err(:final message)) {
      throw AuthException(message.isNotEmpty ? message : 'Suppression impossible');
    }
  }

  static Uri _api(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
}
