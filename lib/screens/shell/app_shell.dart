import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/current_list_sheet.dart';
import '../../widgets/track_cover.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/notice_banner.dart';
import '../../widgets/tappable.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../library/library_screen.dart';
import '../profile/profile_screen.dart';

final _tabIndexProvider = StateProvider<int>((ref) => 0);

/// Au-delà de cette largeur, on bascule en disposition desktop (sidebar latérale).
/// En-dessous (mobile / fenêtre étroite), on garde la barre de navigation basse.
const double _kWideBreakpoint = 800;

/// Hauteur "visuelle" de la bottom nav bar (hors safe-area, qui est ajoutée à
/// part) — utilisée pour poser le mini-player flottant juste au-dessus, sans
/// dépendre d'une mesure post-frame.
const double _kNavBarContentHeight = 66;

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _pages = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(_tabIndexProvider);
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    void onTap(int i) => ref.read(_tabIndexProvider.notifier).state = i;

    // L'inset bas (gestes / barre système) est déjà géré par la nav bar basse,
    // et l'inset clavier est déjà consommé par le Scaffold racine (qui remonte
    // nav bar + mini player au-dessus du clavier). On retire les deux du
    // MediaQuery vu par le contenu, sinon les Scaffold/SafeArea des pages
    // les soustraient une 2e fois → contenu écrasé quand le clavier est ouvert.
    final content = MediaQuery(
      data: MediaQuery.of(context).removePadding(removeBottom: true).removeViewInsets(removeBottom: true),
      child: IndexedStack(index: currentIndex, children: _pages),
    );
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: kBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kWideBreakpoint;

          if (isWide) {
            // ── Disposition desktop : sidebar à gauche, contenu à droite ──
            // Pas de nav bar basse : le player flotte à faible distance du bord.
            return Row(
              children: [
                _MkzikSideBar(currentIndex: currentIndex, onTap: onTap),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: content),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 20,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const BottomBanners(),
                            if (hasTrack) const MiniPlayer(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // ── Disposition mobile : le contenu se cale sur la nav bar basse ;
          // le player flotte par-dessus, détaché des bords (liquid glass).
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(child: content),
                  _MkzikNavBar(currentIndex: currentIndex, onTap: onTap),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: _kNavBarContentHeight + bottomSafeArea + 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BottomBanners(),
                    if (hasTrack) const MiniPlayer(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

const _navItems = [
  _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Accueil'),
  _NavItem(icon: Icons.search, activeIcon: Icons.search, label: 'Recherche'),
  _NavItem(icon: Icons.music_note_outlined, activeIcon: Icons.music_note, label: 'Librairie'),
  _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profil'),
];

// ── Sidebar latérale (desktop) ────────────────────────────────────────────────
class _MkzikSideBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _MkzikSideBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo Mkzik en haut
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [kAccent, kAccentLight]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'MK', style: TextStyle(color: kTextPrimary)),
                      TextSpan(text: 'ZIK', style: TextStyle(color: kAccent)),
                    ],
                  ),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ],
            ),
          ),
          // Items de navigation
          ...List.generate(_navItems.length, (i) {
            final item = _navItems[i];
            final isActive = i == currentIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Material(
                color: isActive ? kAccent.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? kAccent : kTextSecondary,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: isActive ? kAccent : kTextSecondary,
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          // File d'attente : l'espace libre de la sidebar sert à la suite de lecture.
          const Expanded(child: _SideQueue()),
        ],
      ),
    );
  }
}

/// File de lecture dans la sidebar (desktop) : les titres déjà écoutés, le titre
/// en cours (surligné) et la suite. Clic = lecture. Aucune action sur les lignes
/// (elles restent dans la file d'attente).
class _SideQueue extends ConsumerStatefulWidget {
  const _SideQueue();

  @override
  ConsumerState<_SideQueue> createState() => _SideQueueState();
}

class _SideQueueState extends ConsumerState<_SideQueue> {
  static const _rowHeight = 46.0;
  final _scroll = ScrollController();
  String? _firstId; // 1er titre de la file : change quand des précédents sont chargés

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Amène le titre courant tout en haut de la liste.
  void _scrollToCurrent({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final index = ref.read(playerProvider).currentIndex;
    final target = (index * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final currentId = ref.watch(playerProvider.select((s) => s.currentTrack?.id));
    final currentIndex = ref.watch(playerProvider.select((s) => s.currentIndex));
    final notifier = ref.read(playerProvider.notifier);

    // Changement de titre → le titre en cours remonte en haut de la liste.
    ref.listen(playerProvider.select((s) => s.currentTrack?.id), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    });
    // Chargement de titres précédents → on garde le titre en cours à sa place.
    if (queue.isNotEmpty && _firstId != null && queue.first.id != _firstId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent(animate: false));
    }
    _firstId = queue.isEmpty ? null : queue.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              const Text('FILE DE LECTURE',
                  style: TextStyle(
                      color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const Spacer(),
              if (queue.isNotEmpty)
                Tappable(
                  onTap: () => showCurrentList(context),
                  child: const Icon(Icons.open_in_full, color: kTextSecondary, size: 14),
                ),
            ],
          ),
        ),
        Expanded(
          child: queue.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Aucun titre en lecture.',
                      style: TextStyle(color: kTextSecondary, fontSize: 12)),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is! ScrollEndNotification) return false;
                    final m = n.metrics;
                    if (m.pixels >= m.maxScrollExtent - 200) notifier.loadMoreUpcoming();
                    if (m.pixels <= m.minScrollExtent + 200) notifier.loadMorePrevious();
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemExtent: _rowHeight,
                    itemCount: queue.length,
                    itemBuilder: (context, i) {
                      final track = queue[i];
                      final isCurrent = track.id == currentId;
                      final played = i < currentIndex;
                      return _SideQueueRow(
                        track: track,
                        isCurrent: isCurrent,
                        played: played,
                        onTap: () => notifier.jumpTo(i),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _SideQueueRow extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final bool played; // déjà écouté → estompé
  final VoidCallback onTap;

  const _SideQueueRow({
    required this.track,
    required this.isCurrent,
    required this.played,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: played ? 0.5 : 1,
        child: Container(
          color: isCurrent ? kAccent.withValues(alpha: 0.12) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              TrackCover(track: track, size: 32, radius: 6),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        style: TextStyle(
                          color: isCurrent ? kAccent : kTextPrimary,
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(track.artist,
                        style: const TextStyle(color: kTextSecondary, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (isCurrent) const Icon(Icons.equalizer, color: kAccent, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom nav bar custom (mobile) avec indicateur point sous l'onglet actif ──
class _MkzikNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _MkzikNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      color: kSurface,
      padding: EdgeInsets.only(top: 8, bottom: 8 + bottomPadding),
      child: Row(
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final isActive = i == currentIndex;
          return Expanded(
            child: Tappable(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? item.activeIcon : item.icon,
                    color: isActive ? kAccent : kTextSecondary,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? kAccent : kTextSecondary,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Point indicateur sous l'onglet actif
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isActive ? 5 : 0,
                    height: isActive ? 5 : 0,
                    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
