import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'track_actions.dart';

/// Ouvre la file d'attente (current list) en bottom sheet.
void showCurrentList(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: kSheetBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CurrentListSheet(),
  );
}

class _CurrentListSheet extends ConsumerWidget {
  const _CurrentListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠️ On ne surveille QUE la file / l'index / play-pause — surtout PAS la
    // position de lecture, sinon la liste se reconstruirait à chaque tick.
    final queue = ref.watch(playerProvider.select((s) => s.queue));
    final currentIndex = ref.watch(playerProvider.select((s) => s.currentIndex));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final notifier = ref.read(playerProvider.notifier);
    final height = MediaQuery.of(context).size.height * 0.8;

    final current = (currentIndex >= 0 && currentIndex < queue.length) ? queue[currentIndex] : null;
    final base = currentIndex + 1; // début de "À suivre"
    final List<Track> upcoming = base < queue.length ? queue.sublist(base) : <Track>[];

    return SizedBox(
      height: height,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Text('File d\'attente',
                      style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${queue.length} titre${queue.length > 1 ? 's' : ''}',
                      style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                  IconButton(
                    icon: const Icon(Icons.close, color: kTextSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            if (current == null)
              const Expanded(
                child: Center(child: Text('Aucun titre en lecture', style: TextStyle(color: kTextSecondary))),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    // ── En lecture ──
                    const _Label('EN LECTURE'),
                    Container(
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
                                    style: const TextStyle(color: kAccent, fontSize: 14, fontWeight: FontWeight.w700),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(current.artist,
                                    style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Icon(isPlaying ? Icons.equalizer : Icons.pause, color: kAccent, size: 20),
                        ],
                      ),
                    ),

                    // ── À suivre ──
                    const _Label('À SUIVRE'),
                    if (upcoming.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Text('Fin de la file', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: upcoming.length,
                        // ignore: deprecated_member_use
                        onReorder: (oldI, newI) => notifier.reorder(base + oldI, base + newI),
                        itemBuilder: (context, i) {
                          final track = upcoming[i];
                          return Padding(
                            key: ValueKey('${track.id}_$i'),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => notifier.jumpTo(base + i),
                                  child: TrackSquareThumb(track: track),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => notifier.jumpTo(base + i),
                                    behavior: HitTestBehavior.opaque,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(track.title,
                                            style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Text('${track.artist}  ·  ${track.durationFormatted}',
                                            style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ),
                                // Retirer de la file
                                IconButton(
                                  icon: const Icon(Icons.close, color: kTextSecondary, size: 18),
                                  onPressed: () => notifier.removeAt(base + i),
                                ),
                                // Poignée de drag
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
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(text,
          style: const TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
    );
  }
}
