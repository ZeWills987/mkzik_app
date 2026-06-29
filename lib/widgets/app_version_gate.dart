import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_version.dart';
import '../providers/app_version_provider.dart';
import '../screens/auth/auth_widgets.dart';
import '../theme/app_theme.dart';

/// Enveloppe l'app et applique le check de version :
/// - `required_` → écran **bloquant** « Mise à jour requise » (non dismissible) ;
/// - `available` → **bannière** « Mise à jour disponible » (dismissible) en haut ;
/// - sinon (à jour / chargement / erreur réseau) → l'app normale.
class AppVersionGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppVersionGate({super.key, required this.child});

  @override
  ConsumerState<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends ConsumerState<AppVersionGate> {
  bool _bannerDismissed = false;

  Future<void> _openStore(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Statut courant (upToDate tant que le check n'a pas répondu / a échoué).
    final state = ref.watch(appVersionProvider).maybeWhen(
          data: (s) => s,
          orElse: () => AppVersionState.ok,
        );

    if (state.status == UpdateStatus.required_) {
      return _UpdateRequiredScreen(onUpdate: () => _openStore(state.storeUrl));
    }

    return Stack(
      children: [
        widget.child,
        if (state.status == UpdateStatus.available && !_bannerDismissed)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _UpdateBanner(
                onUpdate: () => _openStore(state.storeUrl),
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bannière soft « Mise à jour disponible » (dismissible).
class _UpdateBanner extends StatelessWidget {
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;
  const _UpdateBanner({required this.onUpdate, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: kSheetBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: kAccent, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Une mise à jour est disponible',
                style: TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: onUpdate,
            child: const Text('Mettre à jour', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: kTextSecondary, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Écran bloquant « Mise à jour requise » (version < min_supported).
class _UpdateRequiredScreen extends StatelessWidget {
  final VoidCallback onUpdate;
  const _UpdateRequiredScreen({required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MkzikLogo(size: 40),
              const SizedBox(height: 28),
              const Icon(Icons.system_update, color: kAccent, size: 48),
              const SizedBox(height: 20),
              const Text('Mise à jour requise',
                  style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'Cette version de Mkzik n\'est plus prise en charge. Mets à jour l\'application pour continuer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSecondary, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onUpdate,
                  child: const Text('Mettre à jour',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
