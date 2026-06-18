import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/profile.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/notice_provider.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/notice_banner.dart';
import '../../widgets/mini_player.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends ConsumerWidget {
  /// null = profil de l'utilisateur connecté (onglet Profil).
  /// non-null = profil d'un autre utilisateur / artiste (route poussée).
  final String? username;

  const ProfileScreen({super.key, this.username});

  /// Ouvre le profil d'un username quelconque (artiste / autre user).
  static Future<void> open(BuildContext context, String username) {
    if (username.trim().isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(username: username)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUsername = ref.watch(authProvider.select((s) => s.username));
    final resolved = username ?? authUsername;

    if (resolved == null || resolved.isEmpty) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: Text('Non connecté', style: TextStyle(color: kTextSecondary))),
      );
    }

    final pushed = username != null; // route poussée (vs onglet)
    final isOwn = resolved == authUsername;
    final async = ref.watch(profileProvider(resolved));
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    return Scaffold(
      backgroundColor: kBg,
      // En route poussée, l'AppShell est masqué → on remet bannières + mini-player
      bottomNavigationBar: pushed
          ? SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const BottomBanners(), if (hasTrack) const MiniPlayer()],
              ),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kAccent)),
        error: (err, stack) => const Center(
          child: Text('Erreur de chargement', style: TextStyle(color: kTextSecondary)),
        ),
        data: (data) => RefreshIndicator(
          color: kAccent,
          backgroundColor: kSurface,
          onRefresh: () async {
            ref.invalidate(profileProvider(resolved));
            await ref.read(profileProvider(resolved).future);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  profile: data.profile,
                  isOwn: isOwn,
                  showBack: pushed,
                  onBack: () => Navigator.of(context).maybePop(),
                  onLogout: isOwn && !pushed ? () => ref.read(authProvider.notifier).logout() : null,
                  onEdit: () => EditProfileScreen.open(context, data.profile, resolved),
                ),
              ),
              SliverToBoxAdapter(child: _StatsCard(data: data)),
              if (data.profile.description.isNotEmpty)
                SliverToBoxAdapter(child: _Bio(text: data.profile.description)),
              SliverToBoxAdapter(child: _ZiksHeader(count: data.tracks.length)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final track = data.tracks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TrackResultRow(
                        track: track,
                        onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: data.tracks),
                        onMenu: () => showTrackActionsSheet(context, ref, track),
                      ),
                    );
                  },
                  childCount: data.tracks.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero : cover + avatar + nom + bouton ─────────────────────────────────────

class _Hero extends StatelessWidget {
  final Profile profile;
  final bool isOwn;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback? onLogout;
  final VoidCallback onEdit;

  const _Hero({
    required this.profile,
    required this.isOwn,
    required this.showBack,
    required this.onBack,
    required this.onLogout,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientForSeed(profile.username.hashCode);
    final accent = colors.first;

    return Column(
      children: [
        SizedBox(
          height: 230,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Cover (image ou dégradé + glow)
              SizedBox(
                height: 170,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (mediaUrl(profile.backgroundUrl).isNotEmpty)
                      CachedNetworkImage(imageUrl: mediaUrl(profile.backgroundUrl), fit: BoxFit.cover)
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: colors,
                          ),
                        ),
                      ),
                    // Glow radial
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.6),
                          radius: 1.0,
                          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
                        ),
                      ),
                    ),
                    // Fondu vers le fond de l'app
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, kBg],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Retour (haut gauche) en route poussée
              if (showBack)
                Positioned(
                  top: 0, left: 4,
                  child: SafeArea(
                    child: _CircleIcon(icon: Icons.arrow_back, onTap: onBack),
                  ),
                ),

              // Déconnexion (haut droite) sur son propre profil (onglet)
              if (onLogout != null)
                Positioned(
                  top: 0, right: 4,
                  child: SafeArea(
                    child: _CircleIcon(icon: Icons.logout, onTap: onLogout!),
                  ),
                ),

              // Avatar centré, débordant
              Positioned(
                bottom: 0,
                left: 0, right: 0,
                child: Center(child: _Avatar(profile: profile, accent: accent)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Nom + handle
        Text(profile.username,
            style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('@${profile.username.toLowerCase()}',
            style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        // Bouton : Modifier (soi) ou Suivre/Suivi (autre)
        if (isOwn)
          _OutlineButton(label: 'Modifier le profil', icon: Icons.edit_outlined, onTap: onEdit)
        else
          _FollowButton(username: profile.username, initialFollowing: profile.isFollowing),
        const SizedBox(height: 18),
      ],
    );
  }
}

// Petit bouton rond semi-transparent (back / logout sur la cover)
class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        width: 36, height: 36,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// Bouton Suivre/Suivi avec bascule optimiste + appel API
class _FollowButton extends ConsumerStatefulWidget {
  final String username;
  final bool initialFollowing;
  const _FollowButton({required this.username, required this.initialFollowing});

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  late bool _following = widget.initialFollowing;
  bool _busy = false; // évite les double-taps pendant l'appel

  // Resynchronise sur l'état réel quand le profil est rechargé (après succès).
  @override
  void didUpdateWidget(_FollowButton old) {
    super.didUpdateWidget(old);
    if (!_busy && old.initialFollowing != widget.initialFollowing) {
      _following = widget.initialFollowing;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _following = !_following;
    });
    final ok = await ProfileService.toggleFollow(widget.username);
    if (!mounted) return;
    setState(() {
      if (!ok) _following = !_following; // rollback si échec
      _busy = false;
    });
    final notifier = ref.read(noticeProvider.notifier);
    if (ok) {
      notifier.show(_following ? 'Abonné à @${widget.username}' : 'Désabonné');
      // Rafraîchit le profil affiché (compteurs + état de suivi réels)
      ref.invalidate(profileProvider(widget.username));
    } else {
      notifier.show('Action impossible, réessaie');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: _following ? Colors.transparent : kAccent,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: kAccent, width: 1.4),
        ),
        child: Text(
          _following ? 'Suivi' : 'Suivre',
          style: TextStyle(
            color: _following ? kAccent : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Profile profile;
  final Color accent;
  const _Avatar({required this.profile, required this.accent});

  @override
  Widget build(BuildContext context) {
    final initial = profile.username.isNotEmpty ? profile.username[0].toUpperCase() : '?';
    final avatar = mediaUrl(profile.avatarUrl); // nettoyée
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [kAccentLight, accent]),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 24, spreadRadius: 1)],
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBg, width: 3)),
        child: CircleAvatar(
          radius: 50,
          backgroundColor: accent,
          backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
          child: avatar.isNotEmpty
              ? null
              : Text(initial, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

// ── Carte de stats ────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final ProfileData data;
  const _StatsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderSoft),
      ),
      child: Row(
        children: [
          _Stat(value: data.profile.nbFollowers, label: 'Followers'),
          _divider(),
          _Stat(value: data.profile.nbFollowing, label: 'Suivis'),
          _divider(),
          _Stat(value: data.totalPlays, label: 'Écoutes'),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: const Color(0xFF2C2C40));
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [kAccentLight, kAccent],
            ).createShader(b),
            child: Text(formatCount(value),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Bio ───────────────────────────────────────────────────────────────────────

class _Bio extends StatelessWidget {
  final String text;
  const _Bio({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kTextSecondary, fontSize: 13, height: 1.5),
      ),
    );
  }
}

// ── En-tête section Ziks ───────────────────────────────────────────────────────

class _ZiksHeader extends StatelessWidget {
  final int count;
  const _ZiksHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text('Ziks', style: TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('$count', style: const TextStyle(color: kTextSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Bouton outline ──────────────────────────────────────────────────────────

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: kAccent, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kAccent, size: 16),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
