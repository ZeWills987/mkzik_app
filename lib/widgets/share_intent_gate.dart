import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../providers/auth_provider.dart';
import '../providers/notice_provider.dart';
import '../providers/share_provider.dart';
import '../screens/resolve/resolve_track_screen.dart';
import '../utils/logger.dart';

final _urlPattern = RegExp(r'https?://\S+');

/// Écoute les partages entrants depuis d'autres apps (TikTok, etc.) —
/// n'importe quelle URL trouvée dans le texte partagé ouvre l'écran
/// d'identification du titre. Android uniquement pour l'instant.
///
/// ⚠️ Placé EN DEHORS de `AuthGate` (actif dès le lancement, connecté ou
/// non) : `/stream` et `/download` exigent un JWT côté serveur, donc un
/// partage reçu sans connexion est mis en attente (`pendingSharedUrlProvider`)
/// plutôt que d'ouvrir directement l'écran — sinon un visiteur non connecté
/// pourrait faire écouter/importer un titre sans authentification.
class ShareIntentGate extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const ShareIntentGate({super.key, required this.child, required this.navigatorKey});

  @override
  ConsumerState<ShareIntentGate> createState() => _ShareIntentGateState();
}

class _ShareIntentGateState extends ConsumerState<ShareIntentGate> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handle,
      onError: (Object e) => mkLog('Mkzik 🔗 partage entrant erreur : $e'),
    );
  }

  Future<void> _checkInitial() async {
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) _handle(initial);
    } catch (e) {
      mkLog('Mkzik 🔗 partage initial erreur : $e');
    }
  }

  void _handle(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final text = files
        .map((f) => f.message?.isNotEmpty == true ? f.message! : f.path)
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final url = _urlPattern.firstMatch(text)?.group(0);
    ReceiveSharingIntent.instance.reset();
    if (url == null) return;

    if (ref.read(authProvider).status != AuthStatus.authenticated) {
      // Pas connecté : on ne peut pas appeler /stream ni /download (JWT
      // requis) → on garde le lien pour après la connexion.
      ref.read(pendingSharedUrlProvider.notifier).state = url;
      ref.read(noticeProvider.notifier).show('Connecte-toi pour identifier ce titre');
      return;
    }
    _openResolve(url);
  }

  void _openResolve(String url) {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    ResolveTrackScreen.open(nav.context, url);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Connexion qui vient d'aboutir + un lien était en attente → on l'ouvre.
    ref.listen(authProvider.select((s) => s.status), (previous, next) {
      if (next != AuthStatus.authenticated) return;
      final pending = ref.read(pendingSharedUrlProvider);
      if (pending == null) return;
      ref.read(pendingSharedUrlProvider.notifier).state = null;
      // Après le frame courant : laisse AuthGate basculer sur AppShell avant
      // de pousser l'écran par-dessus.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openResolve(pending));
    });
    return widget.child;
  }
}
