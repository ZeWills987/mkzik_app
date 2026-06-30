import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../shell/app_shell.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';

/// Aiguille l'utilisateur selon l'état d'authentification :
/// - unknown        → splash (restauration du token)
/// - authenticated  → application (AppShell)
/// - unauthenticated→ écran de connexion
///
/// Écoute aussi les deep links entrants pour récupérer le JWT après le flow
/// OAuth Google : `mkzik://auth/google/callback?token=<jwt>`
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = AppLinks().uriLinkStream.listen(_handleDeepLink);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'mkzik' &&
        uri.host == 'auth' &&
        uri.path == '/google/callback') {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        ref.read(authProvider.notifier).applyNewToken(token);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authProvider.select((s) => s.status));

    final Widget child = switch (status) {
      AuthStatus.unknown => const _Splash(),
      AuthStatus.authenticated => const AppShell(),
      AuthStatus.unauthenticated => const LoginScreen(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(key: ValueKey(status), child: child),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MkzikLogo(size: 40),
            SizedBox(height: 24),
            SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
