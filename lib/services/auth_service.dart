import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import 'api_client.dart';

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

  /// Connexion via compte Google : ouvre le navigateur sur `GET /connect/google`.
  /// Symfony redirige vers Google, puis rappelle l'app via deep link
  /// `mkzik://auth/google/callback?token=<jwt>` capturé par AuthGate.
  static Future<void> openGoogleConnect() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}connect/google');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw AuthException('Impossible d\'ouvrir le navigateur');
    }
  }

  static Uri _api(String path) => Uri.parse('${ApiConfig.baseUrl}$path');
}
