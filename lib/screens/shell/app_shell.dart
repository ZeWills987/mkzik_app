import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/player_provider.dart';
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
          const Spacer(),
        ],
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
