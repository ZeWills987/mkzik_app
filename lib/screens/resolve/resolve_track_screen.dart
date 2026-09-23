import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/player_provider.dart';
import '../../services/track_resolve_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';

/// Écran ouvert quand l'utilisateur partage un lien (TikTok…) vers Mkzik —
/// Python tente d'identifier le titre utilisé dans la vidéo.
class ResolveTrackScreen extends ConsumerStatefulWidget {
  final String sharedUrl;
  const ResolveTrackScreen({super.key, required this.sharedUrl});

  static Future<void> open(BuildContext context, String sharedUrl) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResolveTrackScreen(sharedUrl: sharedUrl)),
    );
  }

  @override
  ConsumerState<ResolveTrackScreen> createState() => _ResolveTrackScreenState();
}

class _ResolveTrackScreenState extends ConsumerState<ResolveTrackScreen> {
  late Future<ResolveResult> _future = TrackResolveService.resolve(widget.sharedUrl);

  void _retry() => setState(() => _future = TrackResolveService.resolve(widget.sharedUrl));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Titre partagé',
            style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<ResolveResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _StateView(
              icon: null,
              title: 'Recherche du titre…',
              subtitle: 'On identifie la musique utilisée dans la vidéo.',
              loading: true,
            );
          }
          final result = snap.data;
          if (result is ResolveFound) {
            final hasMeta = result.metaTitle?.isNotEmpty == true;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: result.tracks.length + (hasMeta ? 1 : 0),
              itemBuilder: (_, i) {
                if (hasMeta && i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Musique identifiée : ${result.metaTitle}'
                      '${result.metaArtist?.isNotEmpty == true ? ' · ${result.metaArtist}' : ''}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12.5),
                    ),
                  );
                }
                final track = result.tracks[i - (hasMeta ? 1 : 0)];
                return TrackResultRow(
                  track: track,
                  onTap: () {
                    ref.read(playerProvider.notifier).playTrack(track, queue: result.tracks);
                    Navigator.of(context).maybePop();
                  },
                  onMenu: () => showTrackActionsSheet(context, ref, track),
                );
              },
            );
          }
          if (result is ResolveNotFound) {
            return _StateView(
              icon: Icons.music_off_rounded,
              title: 'Aucune musique identifiée',
              subtitle: 'Cette vidéo utilise peut-être un son original, sans musique référencée.\n'
                  'Tu peux chercher le titre manuellement.',
              action: FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(widget.sharedUrl), mode: LaunchMode.externalApplication),
                style: FilledButton.styleFrom(backgroundColor: kAccent),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Voir la vidéo'),
              ),
            );
          }
          final message = result is ResolveError ? result.message : 'Erreur réseau';
          return _StateView(
            icon: Icons.cloud_off_rounded,
            title: 'Impossible de vérifier ce lien',
            subtitle: message,
            action: TextButton(
              onPressed: _retry,
              child: const Text('Réessayer', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String subtitle;
  final bool loading;
  final Widget? action;
  const _StateView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: kAccent)
            else if (icon != null)
              Icon(icon, color: kTextSecondary, size: 48),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary, fontSize: 13, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
