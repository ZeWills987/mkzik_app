import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'adaptive_sheet.dart';
import 'track_actions.dart';

/// Ouvre la file d'attente (current list) : bottom sheet sur mobile,
/// dialog centré sur desktop.
void showCurrentList(BuildContext context) {
  showAdaptiveSheet(
    context: context,
    tall: true,
    glass: true,
    builder: (_) => const _CurrentListSheet(),
  );
}

// Hauteur approx. d'une ligne de la file (cf. _QueueRow) — sert à dimensionner
// la feuille et à calculer le nombre de titres à précharger.
const _kRowH = 60.0;
const _kHeaderH = 140.0; // poignée + en-tête + bouton radio

class _CurrentListSheet extends ConsumerStatefulWidget {
  const _CurrentListSheet();

  @override
  ConsumerState<_CurrentListSheet> createState() => _CurrentListSheetState();
}

class _CurrentListSheetState extends ConsumerState<_CurrentListSheet> {
  bool _prefetched = false;

  /// Précharge, de chaque côté du titre courant, assez de titres pour remplir
  /// la hauteur visible + 2 en dépassement — pour ne pas avoir à recharger
  /// dès le premier petit scroll après l'ouverture.
  Future<void> _prefetchViewport() async {
    if (_prefetched || !mounted) return;
    _prefetched = true;
    final screenH = MediaQuery.of(context).size.height;
    final available = screenH * 0.9 - _kHeaderH;
    final target = (available / _kRowH).floor().clamp(1, 60) + 2;
    final notifier = ref.read(playerProvider.notifier);

    while (mounted) {
      final s = ref.read(playerProvider);
      final upcomingCount = s.queue.length - s.currentIndex - 1;
      if (upcomingCount >= target || notifier.loadedAllUpcoming) break;
      await notifier.loadMoreUpcoming();
    }
    while (mounted) {
      final s = ref.read(playerProvider);
      if (s.currentIndex >= target || notifier.loadedAllPrevious) break;
      await notifier.loadMorePrevious();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchViewport());
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ On ne surveille QUE la file / l'index / play-pause — surtout PAS la
    // position de lecture, sinon la liste se reconstruirait à chaque tick.
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final currentIndex = ref.watch(playerProvider.select((s) => s.currentIndex));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final notifier = ref.read(playerProvider.notifier);
    // Hauteur selon le contenu : la feuille grandit avec le nombre de titres
    // jusqu'à toute la hauteur disponible (bornée par le parent : safe area sur
    // mobile, 92 % en dialog desktop), sans descendre sous 45 % de l'écran.
    final screenH = MediaQuery.of(context).size.height;
    final screenTarget = (_kHeaderH + queue.length * _kRowH).clamp(screenH * 0.45, screenH).toDouble();

    final current = (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;
    final base = currentIndex + 1;
    final List<Track> upcoming = base < queue.length ? queue.sublist(base) : <Track>[];
    final previousCount = current == null ? 0 : currentIndex;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight.isFinite
            ? (screenTarget < constraints.maxHeight ? screenTarget : constraints.maxHeight)
            : screenTarget,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    const Text('File d\'attente',
                        style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: kTextSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Mode radio : enchaîne sur des titres du même mood à partir du courant.
              if (current != null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _RadioButton(),
                ),

              if (current == null)
                const Expanded(
                  child: Center(child: Text('Aucun titre en lecture', style: TextStyle(color: kTextSecondary))),
                )
              else
                Expanded(
                  // Approche d'un bord → on charge 10 titres de plus de ce côté
                  // (depuis la liste connue, sinon page suivante de l'API).
                  child: NotificationListener<ScrollNotification>(
                    // Uniquement à l'arrêt du scroll : sur chaque ScrollUpdate (60/s)
                    // les ajouts s'enchaînaient en cascade tant qu'on restait près du bord.
                    onNotification: (n) {
                      if (n is! ScrollEndNotification) return false;
                      final m = n.metrics;
                      if (m.pixels >= m.maxScrollExtent - 300) notifier.loadMoreUpcoming();
                      if (m.pixels <= m.minScrollExtent + 300) notifier.loadMorePrevious();
                      return false;
                    },
                    // `center` : la liste s'ouvre sur le titre en cours ; les
                    // précédents sont au-dessus, accessibles en remontant.
                    child: CustomScrollView(
                      center: const ValueKey('now-playing'),
                      slivers: [
                        // Slivers avant `center` : disposés vers le haut.
                        if (previousCount > 0)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                // i = 0 → titre juste avant le courant.
                                final qIdx = currentIndex - 1 - i;
                                return Opacity(
                                  opacity: 0.55,
                                  child: _QueueRow(
                                    track: queue[qIdx],
                                    onTap: () => notifier.jumpTo(qIdx),
                                    onLongPress: () => _showRowActions(context, ref, queue[qIdx]),
                                    addToPlaylist: _addToPlaylistButton(context, ref, queue[qIdx]),
                                  ),
                                );
                              },
                              childCount: previousCount,
                            ),
                          ),

                        SliverToBoxAdapter(
                          key: const ValueKey('now-playing'),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () => _showRowActions(context, ref, current),
                            child: Container(
                            color: kAccent.withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                TrackSquareThumb(track: current),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(current.title,
                                          style: const TextStyle(
                                              color: kAccent, fontSize: 14, fontWeight: FontWeight.w700),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(current.artist,
                                          style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                ?_addToPlaylistButton(context, ref, current),
                                Icon(isPlaying ? Icons.equalizer : Icons.pause, color: kAccent, size: 20),
                              ],
                            ),
                            ),
                          ),
                        ),

                        if (upcoming.isNotEmpty)
                          SliverReorderableList(
                            itemCount: upcoming.length,
                            // ignore: deprecated_member_use
                            onReorder: (oldI, newI) => notifier.reorder(base + oldI, base + newI),
                            itemBuilder: (context, i) {
                              final track = upcoming[i];
                              return _QueueRow(
                                key: ValueKey('${track.id}_$i'),
                                track: track,
                                onTap: () => notifier.jumpTo(base + i),
                                onLongPress: () => _showRowActions(context, ref, track,
                                    onRemove: () => notifier.removeAt(base + i)),
                                addToPlaylist: _addToPlaylistButton(context, ref, track),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isWide(context))
                                      IconButton(
                                        icon: const Icon(Icons.close, color: kTextSecondary, size: 18),
                                        onPressed: () => notifier.removeAt(base + i),
                                      ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.only(left: 2),
                                        child: Icon(Icons.drag_handle, color: kTextSecondary, size: 22),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton « ajouter à une playlist » — masqué pour un externe non importé
/// (pas d'id Mkzik à ajouter) et sur mobile (actions au appui long).
Widget? _addToPlaylistButton(BuildContext context, WidgetRef ref, Track track) {
  if (!_isWide(context) || track.isExternal || track.apiId == null) return null;
  return IconButton(
    icon: const Icon(Icons.playlist_add, color: kTextSecondary, size: 20),
    tooltip: 'Ajouter à une playlist',
    onPressed: () => showAddToPlaylistSheet(context, ref, track),
  );
}

/// Desktop : actions en boutons sur la ligne. Mobile : appui long (cf. [_showRowActions]).
bool _isWide(BuildContext context) => MediaQuery.of(context).size.width >= 800;

/// Actions d'une ligne de la file (appui long sur mobile).
void _showRowActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  VoidCallback? onRemove,
}) {
  final canAdd = !track.isExternal && track.apiId != null;
  if (!canAdd && onRemove == null) return;
  showAdaptiveSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                TrackSquareThumb(track: track),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(track.title,
                      style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: kBorderSoft),
          if (canAdd)
            _ActionItem(
              icon: Icons.library_add,
              label: 'AJOUTER À UNE PLAYLIST',
              onTap: () {
                Navigator.pop(ctx);
                showAddToPlaylistSheet(context, ref, track);
              },
            ),
          if (onRemove != null)
            _ActionItem(
              icon: Icons.close,
              label: 'RETIRER DE LA FILE',
              onTap: () {
                Navigator.pop(ctx);
                onRemove();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: kTextSecondary, size: 22),
            const SizedBox(width: 18),
            Text(label,
                style: const TextStyle(
                    color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? addToPlaylist;
  final Widget? trailing;
  const _QueueRow({
    super.key,
    required this.track,
    required this.onTap,
    this.onLongPress,
    this.addToPlaylist,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Material explicite : pendant un drag, la ligne est rendue dans l'Overlay,
    // hors du Material de la feuille → InkWell lèverait "No Material widget found".
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            TrackSquareThumb(track: track),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${track.artist}  ·  ${track.durationFormatted}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
              ?addToPlaylist,
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton « Mode radio » : lance une écoute du même mood depuis le titre courant.
class _RadioButton extends ConsumerStatefulWidget {
  const _RadioButton();

  @override
  ConsumerState<_RadioButton> createState() => _RadioButtonState();
}

class _RadioButtonState extends ConsumerState<_RadioButton> {
  bool _loading = false;

  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    final ok = await ref.read(playerProvider.notifier).startRadio();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(ok ? 'Mode radio activé — titres du même mood' : 'Aucune suggestion trouvée'),
      ),
    );
    if (ok) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAccent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _loading ? null : _start,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: _loading
                    ? const CircularProgressIndicator(strokeWidth: 2.2, color: kAccent)
                    : const Icon(Icons.radio, color: kAccent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(_loading ? 'Recherche du mood…' : 'Mode radio',
                  style: const TextStyle(color: kAccent, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
