import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';

/// Écran de connexion Google pour Windows (desktop).
///
/// Ouvre le flow web `GET /connect/google` dans une WebView2 intégrée, puis
/// intercepte la redirection finale `{FRONTEND_URL}/auth/google/callback?token=`
/// pour récupérer le JWT mkzik — sans dépendre de la valeur de FRONTEND_URL.
///
/// Renvoie le token (String) via `Navigator.pop`, ou `null` si annulé / échec.
class WindowsGoogleAuth extends StatefulWidget {
  const WindowsGoogleAuth({super.key});

  /// Ouvre l'écran et renvoie le JWT mkzik, ou null.
  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const WindowsGoogleAuth()),
    );
  }

  @override
  State<WindowsGoogleAuth> createState() => _WindowsGoogleAuthState();
}

class _WindowsGoogleAuthState extends State<WindowsGoogleAuth> {
  final _controller = WebviewController();
  StreamSubscription<String>? _urlSub;
  bool _ready = false;
  String? _error;
  bool _done = false; // évite un double pop si l'URL callback défile deux fois

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      _urlSub = _controller.url.listen(_onUrl);
      await _controller.loadUrl('${ApiConfig.baseUrl}connect/google');
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'WebView indisponible. Installe Microsoft Edge WebView2 Runtime.');
      }
    }
  }

  // Intercepte chaque changement d'URL : dès qu'on atteint la route de callback
  // avec un token, on le récupère et on ferme.
  void _onUrl(String url) {
    if (_done) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final isCallback = uri.path.endsWith('/auth/google/callback');
    final token = uri.queryParameters['token'];
    if (isCallback && token != null && token.isNotEmpty) {
      _done = true;
      Navigator.of(context).pop(token);
    }
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    _controller.dispose();
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
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextSecondary)),
              ),
            )
          : Stack(
              children: [
                if (_ready) Positioned.fill(child: Webview(_controller)),
                if (!_ready)
                  const Center(child: CircularProgressIndicator(color: kAccent)),
              ],
            ),
    );
  }
}
