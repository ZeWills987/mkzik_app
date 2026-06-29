import 'package:flutter/material.dart';
import '../../../models/track.dart';
import '../../../models/search_user.dart';
import '../../../services/profile_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/media.dart';
import '../../../widgets/track_actions.dart';
import '../../profile/profile_screen.dart';

/// Chip de tri (PERTINENCE / DATE / ÉCOUTES).
class SortChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const SortChip(this.label, this.active, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Text(label,
            style: TextStyle(
              color: active ? kAccent : kTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            )),
      ),
    );
  }
}

/// Chip de filtre plateforme externe (logo + libellé) — onglet Externe.
class PlatformChip extends StatelessWidget {
  final String label;
  final ExtPlatform? platform; // null = "TOUT" (pas de logo)
  final bool active;
  final VoidCallback onTap;

  const PlatformChip({super.key, required this.label, this.platform, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (platform != null) ...[
              Opacity(opacity: active ? 1 : 0.55, child: PlatformLogo(platform: platform!, size: 15)),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  color: active ? kAccent : kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                )),
          ],
        ),
      ),
    );
  }
}

/// Ligne de résultat utilisateur : avatar + nom (→ profil) + bouton suivre.
class ResultUserRow extends StatefulWidget {
  final SearchUser user;
  const ResultUserRow({super.key, required this.user});

  @override
  State<ResultUserRow> createState() => _ResultUserRowState();
}

class _ResultUserRowState extends State<ResultUserRow> {
  late bool _following = widget.user.isFollowing;
  bool _busy = false; // évite les double-taps pendant l'appel

  // Bascule optimiste + appel API, rollback si échec (cf. profil)
  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _following = !_following;
    });
    final ok = await ProfileService.toggleFollow(widget.user.username);
    if (!mounted) return;
    setState(() {
      if (!ok) _following = !_following; // rollback
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Avatar + nom cliquables → profil de l'utilisateur/artiste
          Expanded(
            child: GestureDetector(
              onTap: () => ProfileScreen.open(context, u.username),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final av = mediaUrl(u.avatarUrl);
                    return CircleAvatar(
                    radius: 22,
                    backgroundColor: kUserBlue,
                    backgroundImage: av.isNotEmpty ? NetworkImage(av) : null,
                    child: av.isEmpty
                        ? Text(u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                        : null,
                  );
                  }),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.username,
                            style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${formatCount(u.nbFollowers)} abonnés',
                            style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _following ? Colors.transparent : kAccent,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: kAccent),
              ),
              child: Text(_following ? 'Suivi' : 'Suivre',
                  style: TextStyle(
                    color: _following ? kAccent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

/// État "aucun résultat".
class EmptyResults extends StatelessWidget {
  const EmptyResults({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Aucun résultat', style: TextStyle(color: kTextSecondary, fontSize: 14)),
    );
  }
}

/// Affiche l'erreur de la recherche externe (au lieu d'un vide silencieux).
class ExternalErrorView extends StatelessWidget {
  final String message;
  const ExternalErrorView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: kTextSecondary, size: 40),
            const SizedBox(height: 14),
            const Text('Recherche externe indisponible',
                style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Loader centré avec libellé optionnel (recherche en cours).
class ResultsLoader extends StatelessWidget {
  final String? label;
  const ResultsLoader({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kAccent),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
