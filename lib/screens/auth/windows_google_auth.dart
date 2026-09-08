import 'dart:async';
import 'dart:io' show HttpServer, InternetAddress, Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Connexion Google pour Windows via navigateur système.
///
/// Flow :
///   1. Démarre un serveur HTTP local sur un port aléatoire.
///   2. `GET /api/auth/google/connect-url?callback=http://localhost:PORT/callback`
///      → URL `accounts.google.com/…` avec redirect_uri=localhost.
///   3. Ouvre le navigateur système (`url_launcher`).
///   4. Google redirige sur `http://localhost:PORT/callback?code=xxx`.
///   5. Flutter reçoit le code, appelle
///      `POST /api/auth/google/exchange-code {code, redirect_uri}` → JWT.
///   6. On ferme le serveur et on retourne le token.
class WindowsGoogleAuth extends StatefulWidget {
  const WindowsGoogleAuth({super.key});

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const WindowsGoogleAuth()),
    );
  }

  @override
  State<WindowsGoogleAuth> createState() => _WindowsGoogleAuthState();
}

class _WindowsGoogleAuthState extends State<WindowsGoogleAuth> {
  String? _error;
  bool _waitingForBrowser = false;
  HttpServer? _server;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // 1. Serveur local sur port libre.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      final port = server.port;
      final callbackUrl = 'http://localhost:$port/callback';

      // 2. Récupère l'URL Google depuis Symfony avec redirect_uri local.
      final googleUrl = await AuthService.fetchGoogleConnectUrl(callbackUrl: callbackUrl);
      if (!mounted) { server.close(); return; }

      if (googleUrl == null || googleUrl.isEmpty) {
        server.close();
        setState(() => _error = 'Impossible de démarrer la connexion Google.\nVérifie ta connexion.');
        return;
      }

      // 3. Ouvre le navigateur système.
      final uri = Uri.parse(googleUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        server.close();
        setState(() => _error = 'Impossible d\'ouvrir le navigateur.\nLance manuellement : $googleUrl');
        return;
      }

      if (mounted) setState(() => _waitingForBrowser = true);

      // 4. Attend le callback du navigateur (timeout 5 min).
      final completer = Completer<String?>();
      final timeout = Timer(const Duration(minutes: 5), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      server.listen((req) async {
        final code = req.uri.queryParameters['code'];
        final error = req.uri.queryParameters['error'];

        // Page de confirmation dans le navigateur.
        req.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html; charset=utf-8')
          ..write(_successHtml(error == null && code != null))
          ..close();

        if (!completer.isCompleted) {
          completer.complete(code);
        }
      });

      final code = await completer.future;
      timeout.cancel();
      server.close();
      _server = null;

      if (!mounted) return;

      if (code == null || code.isEmpty) {
        setState(() { _waitingForBrowser = false; _error = 'Connexion Google annulée ou expirée.'; });
        return;
      }

      // 5. Échange le code contre un JWT via Symfony.
      if (mounted) setState(() => _waitingForBrowser = false);
      final token = await AuthService.exchangeGoogleCode(code: code, redirectUri: callbackUrl);
      if (!mounted) return;

      if (token == null || token.isEmpty) {
        setState(() => _error = 'Connexion Google échouée, réessaie.');
        return;
      }

      Navigator.of(context).pop(token);
    } catch (e) {
      _server?.close();
      if (mounted) setState(() => _error = 'Erreur inattendue : $e');
    }
  }

  String _successHtml(bool success) => success
      ? '<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
        '<h2 style="color:#22c55e">✓ Connecté avec Google</h2>'
        '<p>Tu peux fermer cet onglet et retourner dans Mkzik.</p></body></html>'
      : '<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
        '<h2 style="color:#ef4444">✗ Connexion annulée</h2>'
        '<p>Retourne dans Mkzik pour réessayer.</p></body></html>';

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kTextPrimary,
        title: const Text('Connexion Google'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kTextSecondary, height: 1.6)),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Retour', style: TextStyle(color: kAccent)),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: kAccent),
                    const SizedBox(height: 24),
                    Text(
                      _waitingForBrowser
                          ? 'Connecte-toi dans le navigateur\npuis reviens ici.'
                          : 'Préparation…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kTextSecondary, height: 1.6, fontSize: 15),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
