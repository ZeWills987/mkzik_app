import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointerDeviceKind;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/banger_provider.dart';
import '../../providers/notice_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/tappable.dart';
import '../../widgets/track_actions.dart';
import '../../widgets/track_cover.dart';

/// Quand il reste ce nombre de titres (ou moins) devant l'utilisateur, on
/// précharge la page suivante du fil.
const int _kPrefetchAhead = 4;

/// « Banger » : fil vertical plein écran façon TikTok « Pour toi ». Un titre par
/// page ; la page visible est lue automatiquement via le player global (donc
/// notification / lockscreen cohérents). Quitter l'onglet met la lecture en pause.
class BangerScreen extends ConsumerStatefulWidget {
  /// Vrai quand l'onglet est affiché (les onglets vivent dans un IndexedStack).
  final bool active;
  const BangerScreen({super.key, required this.active});

  @override
  ConsumerState<BangerScreen> createState() => _BangerScreenState();
}

class _BangerScreenState extends ConsumerState<BangerScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _onActivated();
  }

  @override
  void didUpdateWidget(BangerScreen old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    widget.active ? _onActivated() : _onDeactivated();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _onActivated() {
    ref.read(bangerProvider.notifier).ensureLoaded();
    // Après le build : le PageView doit exister avant de démarrer la lecture.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _playIndex(_index, resume: true);
    });
  }

  void _onDeactivated() {
    final items = ref.read(bangerProvider).items;
    final player = ref.read(playerProvider);
    final cur = player.currentTrack;
    if (cur != null && player.isPlaying && items.any((t) => t.id == cur.id)) {
      ref.read(playerProvider.notifier).togglePlayPause();
    }
  }

  /// Lance le titre de la page [i]. Si c'est déjà le titre courant, on ne le
  /// relance pas (sinon il repartirait du début) : on le reprend seulement.
  void _playIndex(int i, {bool resume = false}) {
    final items = ref.read(bangerProvider).items;
    if (i < 0 || i >= items.length) return;
    final track = items[i];
    final player = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    if (player.currentTrack?.id == track.id) {
      if (resume && !player.isPlaying) notifier.togglePlayPause();
      return;
    }
    final feed = ref.read(bangerProvider.notifier);
    notifier.playTrack(
      track,
      queue: items,
      // La file du player s'étend avec la même source que l'écran.
      fetchMore: ({required int limit, required int offset}) => feed.loadMore(),
      hasMore: !ref.read(bangerProvider).ended,
    );
  }

  void _onPageChanged(int i) {
    _index = i;
    final feed = ref.read(bangerProvider);
    if (i >= feed.items.length - _kPrefetchAhead) {
      ref.read(bangerProvider.notifier).loadMore();
    }
    if (widget.active) _playIndex(i);
  }

  /// Le player enchaîne tout seul (fin de titre) → la page suit.
  void _followPlayer(String? currentId) {
    if (!widget.active || currentId == null || !_page.hasClients) return;
    final items = ref.read(bangerProvider).items;
    final idx = items.indexWhere((t) => t.id == currentId);
    if (idx < 0 || idx == _index) return;
    _index = idx;
    _page.animateToPage(idx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(bangerProvider);
    ref.listen(playerProvider.select((s) => s.currentTrack?.id), (_, id) => _followPlayer(id));

    final Widget body;
    if (feed.initialLoading) {
      body = const Center(child: CircularProgressIndicator(color: kAccent));
    } else if (feed.items.isEmpty) {
      body = feed.error != null
          ? EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Impossible de charger Banger',
              subtitle: 'Vérifie ta connexion puis réessaie.',
              actionLabel: 'Réessayer',
              onAction: () => ref.read(bangerProvider.notifier).loadInitial(),
            )
          : EmptyState(
              icon: Icons.local_fire_department_rounded,
              title: 'Pas encore de Banger',
              subtitle: 'Le fil se remplit au fur et à mesure que le catalogue grandit.',
              actionLabel: 'Actualiser',
              onAction: () => ref.read(bangerProvider.notifier).loadInitial(),
            );
    } else {
      body = ScrollConfiguration(
        // Souris / stylet : glisser à la souris sur desktop, comme au doigt.
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus},
        ),
        child: PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          onPageChanged: _onPageChanged,
          // +1 : la dernière page « Tu as tout vu » quand le fil est terminé.
          itemCount: feed.items.length + (feed.ended ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= feed.items.length) {
              return _EndOfFeed(onRefresh: () {
                _index = 0;
                ref.read(bangerProvider.notifier).loadInitial().then((_) {
                  if (_page.hasClients) _page.jumpToPage(0);
                  if (mounted && widget.active) _playIndex(0);
                });
              });
            }
            return _BangerPage(track: feed.items[i]);
          },
        ),
      );
    }

    return ColoredBox(color: kBg, child: body);
  }
}

// ── Une page du fil ───────────────────────────────────────────────────────────

class _BangerPage extends ConsumerWidget {
  final Track track;
  const _BangerPage({required this.track});

  Future<void> _tap(WidgetRef ref) async {
    final player = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    if (player.currentTrack?.id == track.id) {
      await notifier.togglePlayPause();
    } else {
      await notifier.playTrack(track, queue: ref.read(bangerProvider).items);
    }
  }

  void _share(WidgetRef ref) {
    Clipboard.setData(ClipboardData(text: track.pageUrl.isNotEmpty ? track.pageUrl : track.title));
    ref.read(noticeProvider.notifier).show('Lien copié', icon: NoticeIcon.share);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(playerProvider.select((s) => s.currentTrack?.id == track.id));
    final isPlaying = ref.watch(playerProvider.select((s) => s.currentTrack?.id == track.id && s.isPlaying));
    final liked = ref.watch(playerProvider.select((s) => s.currentTrack?.id == track.id ? s.isLiked : track.isFavoris));
    final coverUrl = mediaUrl(track.coverUrl);
    final colors = track.gradientColors;
    final size = MediaQuery.sizeOf(context);
    final coverSize = math.min(math.min(size.width * 0.78, size.height * 0.42), 380.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(ref),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fond : pochette floutée, ou dégradé aux couleurs du titre.
          if (coverUrl.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50, tileMode: TileMode.clamp),
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const ColoredBox(color: Color(0xFF101014)),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.first.withValues(alpha: 0.55), const Color(0xFF050507)],
                ),
              ),
            ),
          // Voile sombre : lisibilité du texte et des actions.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Pochette centrale + indicateur « pause ».
          Align(
            alignment: const Alignment(0, -0.18),
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 2)],
                  ),
                  child: TrackCover(track: track, size: coverSize, radius: 22),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isCurrent && !isPlaying ? 1 : 0,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                  ),
                ),
              ],
            ),
          ),

          // En-tête.
          SafeArea(
            bottom: false,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, color: kAccent, size: 22),
                  SizedBox(width: 6),
                  Text('Banger',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ],
              ),
            ),
          ),

          // Infos du titre (bas gauche) + actions (droite).
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
                      const SizedBox(height: 6),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionButton(
                      icon: liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? kAccent : Colors.white,
                      label: track.likesLabel,
                      onTap: () async {
                        // Le like du player agit sur le titre courant : on le lance d'abord.
                        if (!isCurrent) await _tap(ref);
                        await ref.read(playerProvider.notifier).toggleLike();
                      },
                    ),
                    const SizedBox(height: 18),
                    _ActionButton(
                      icon: Icons.playlist_add_rounded,
                      label: 'Playlist',
                      onTap: () => showAddToPlaylistSheet(context, ref, track),
                    ),
                    const SizedBox(height: 18),
                    _ActionButton(icon: Icons.ios_share, label: 'Partager', onTap: () => _share(ref)),
                    const SizedBox(height: 18),
                    _ActionButton(
                      icon: Icons.more_horiz,
                      label: 'Plus',
                      onTap: () => showTrackActionsSheet(context, ref, track),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Progression du titre en cours, collée en bas.
          if (isCurrent) const Positioned(left: 0, right: 0, bottom: 0, child: _ProgressLine()),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Fine barre de progression : isolée pour que seule elle écoute la position.
class _ProgressLine extends ConsumerWidget {
  const _ProgressLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(playerProvider.select((s) => s.position));
    final dur = ref.watch(playerProvider.select((s) => s.duration));
    final value = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return LinearProgressIndicator(
      value: value,
      minHeight: 3,
      backgroundColor: Colors.white24,
      valueColor: const AlwaysStoppedAnimation(kAccent),
    );
  }
}

class _EndOfFeed extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EndOfFeed({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.check_circle_outline_rounded,
      title: 'Tu as tout vu',
      subtitle: 'Reviens plus tard, de nouveaux Bangers arrivent.',
      actionLabel: 'Recharger le fil',
      onAction: onRefresh,
    );
  }
}
