import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? token;
  final String? username;
  final bool submitting; // requête login/register en cours
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.username,
    this.submitting = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    String? username,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      username: username ?? this.username,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    // Session expirée (401 sur une requête authentifiée) → déconnexion auto.
    ApiClient.onUnauthorized = _onUnauthorized;
    _bootstrap();
  }

  // Déconnecte sur token rejeté, seulement si on se croyait connecté
  // (évite les déconnexions/boucles parasites pendant le login ou hors session).
  void _onUnauthorized() {
    if (state.status != AuthStatus.authenticated) return;
    unawaited(logout());
  }

  // Au démarrage : charge le token persistant et restaure la session
  Future<void> _bootstrap() async {
    final token = await TokenStorage.read();
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    _applyToken(token);
  }

  void _applyToken(String token) {
    ApiConfig.token = token; // propage l'auth à toutes les requêtes API
    final payload = decodeJwt(token);
    state = AuthState(
      status: AuthStatus.authenticated,
      token: token,
      username: payload?['username']?.toString(),
    );
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final token = await AuthService.login(email.trim(), password);
      await TokenStorage.write(token);
      _applyToken(token);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, error: e.message);
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required bool rgpdConsent,
    String? firstName,
    String? lastName,
    String? description,
    String? birthDate,
  }) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final token = await AuthService.register(
        username: username.trim(),
        email: email.trim(),
        password: password,
        rgpdConsent: rgpdConsent,
        firstName: firstName,
        lastName: lastName,
        description: description,
        birthDate: birthDate,
      );
      await TokenStorage.write(token);
      _applyToken(token);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, error: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    await TokenStorage.clear();
    ApiConfig.token = null;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void updateUsername(String newUsername) {
    state = state.copyWith(username: newUsername);
  }

  /// Appelé après un changement d'username : stocke le nouveau JWT et
  /// met à jour l'état auth (username extrait du nouveau payload).
  Future<void> applyNewToken(String token) async {
    await TokenStorage.write(token);
    _applyToken(token);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
