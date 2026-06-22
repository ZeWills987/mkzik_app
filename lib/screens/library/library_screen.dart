import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/favourites_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/notice_provider.dart';
import '../../services/playlist_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_actions.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0; // 0 = Tout, 1 = Favoris, 2 = Playlists

  @override
  Widget build(BuildContext context) {
    final favAsync = ref.watch(favouritesProvider);
    final plAsync = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          color: kAccent,
          backgroundColor: kSurface,
          onRefresh: () async {
            ref.invalidate(favouritesProvider);
            ref.invalidate(playlistsProvider);
            await Future.wait([
              ref.read(favouritesProvider.future),
              ref.read(playlistsProvider.future),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Header(onCreate: () => _createPlaylist(context, ref))),
              SliverToBoxAdapter(
                child: _Tabs(current: _tab, onTap: (i) => setState(() => _tab = i)),
              ),
              ..._contentSlivers(favAsync, plAsync),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _contentSlivers(AsyncValue<List<Track>> favAsync, AsyncValue<List<Playlist>> plAsync) {
    switch (_tab) {
      case 1:
        return [_favouritesSliver(context, ref, favAsync)];
      case 2:
        return [_playlistsSliver(context, ref, plAsync)];
      default:
        return [_allSliver(context, ref, favAsync, plAsync)];
    }
  }
}

// ── Onglet « Tout » : favoris + playlists entrelacés (récents en premier) ──────

Widget _allSliver(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<List<Track>> favAsync,
  AsyncValue<List<Playlist>> plAsync,
) {
  if (favAsync.isLoading || plAsync.isLoading) {
    return const SliverToBoxAdapter(child: _InlineLoader());
  }
  final tracks = favAsync.valueOrNull ?? const <Track>[];
  final playlists = plAsync.valueOrNull ?? const <Playlist>[];
  if (tracks.isEmpty && playlists.isEmpty) {
    return const SliverToBoxAdapter(
      child: _InlineMessage('Ta librairie est vide — like des Ziks ou crée une playlist.'),
    );
  }
  final items = _mergeRecent(playlists, tracks);
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, i) {
        final item = items[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: item is Playlist
              ? _PlaylistRow(
                  playlist: item,
                  onTap: () => PlaylistDetailScreen.open(context, item),
                  onRename: () => _renamePlaylist(context, ref, item),
                  onDelete: () => _deletePlaylist(context, ref, item),
                )
              : TrackResultRow(
                  track: item as Track,
                  onTap: () => ref.read(playerProvider.notifier).playTrack(item, queue: tracks),
                  onMenu: () => showTrackActionsSheet(context, ref, item),
                ),
        );
      },
      childCount: items.length,
    ),
  );
}

/// Entrelace playlists (id décroissant = plus récentes) et favoris (ordre API),
/// au mieux faute de timestamp d'action côté API.
List<Object> _mergeRecent(List<Playlist> playlists, List<Track> tracks) {
  final pls = [...playlists]..sort((a, b) => b.id.compareTo(a.id));
  final out = <Object>[];
  var pi = 0, ti = 0;
  while (pi < pls.length || ti < tracks.length) {
    if (ti >= tracks.length || (pi < pls.length && pi <= ti)) {
      out.add(pls[pi++]);
    } else {
      out.add(tracks[ti++]);
    }
  }
  return out;
}

// ── Slivers par section ───────────────────────────────────────────────────────

Widget _playlistsSliver(BuildContext context, WidgetRef ref, AsyncValue<List<Playlist>> async) {
  return async.when(
    loading: () => const SliverToBoxAdapter(child: _InlineLoader()),
    error: (_, _) => const SliverToBoxAdapter(child: _InlineMessage('Playlists indisponibles.')),
    data: (playlists) {
      if (playlists.isEmpty) {
        return const SliverToBoxAdapter(
          child: _InlineMessage('Aucune playlist — touche « Créer » pour en ajouter une.'),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PlaylistRow(
              playlist: playlists[i],
              onTap: () => PlaylistDetailScreen.open(context, playlists[i]),
              onRename: () => _renamePlaylist(context, ref, playlists[i]),
              onDelete: () => _deletePlaylist(context, ref, playlists[i]),
            ),
          ),
          childCount: playlists.length,
        ),
      );
    },
  );
}

Widget _favouritesSliver(BuildContext context, WidgetRef ref, AsyncValue<List<Track>> async) {
  return async.when(
    loading: () => const SliverToBoxAdapter(child: _InlineLoader()),
    error: (_, _) => const SliverToBoxAdapter(child: _InlineMessage('Favoris indisponibles.')),
    data: (tracks) {
      if (tracks.isEmpty) {
        return const SliverToBoxAdapter(
          child: _InlineMessage('Aucun favori — like des Ziks pour les retrouver ici.'),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TrackResultRow(
              track: tracks[i],
              onTap: () => ref.read(playerProvider.notifier).playTrack(tracks[i], queue: tracks),
              onMenu: () => showTrackActionsSheet(context, ref, tracks[i]),
            ),
          ),
          childCount: tracks.length,
        ),
      );
    },
  );
}

// ── Actions playlist (créer / renommer / supprimer) ───────────────────────────

Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
  final name = await _promptName(context, title: 'Nouvelle playlist');
  if (name == null || name.trim().isEmpty) return;
  final pl = await PlaylistService.create(name.trim());
  final notifier = ref.read(noticeProvider.notifier);
  if (pl != null) {
    ref.invalidate(playlistsProvider);
    notifier.show('Playlist « ${pl.title} » créée', icon: NoticeIcon.queue);
  } else {
    notifier.show('Création impossible, réessaie');
  }
}

Future<void> _renamePlaylist(BuildContext context, WidgetRef ref, Playlist pl) async {
  final name = await _promptName(context, title: 'Renommer la playlist', initial: pl.title);
  if (name == null || name.trim().isEmpty || name.trim() == pl.title) return;
  final ok = await PlaylistService.rename(pl.id, name.trim());
  final notifier = ref.read(noticeProvider.notifier);
  if (ok) {
    ref.invalidate(playlistsProvider);
    notifier.show('Playlist renommée', icon: NoticeIcon.queue);
  } else {
    notifier.show('Renommage impossible');
  }
}

Future<void> _deletePlaylist(BuildContext context, WidgetRef ref, Playlist pl) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetBg,
      title: const Text('Supprimer ?', style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('La playlist « ${pl.title} » sera supprimée.',
          style: const TextStyle(color: kTextSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler', style: TextStyle(color: kTextSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Supprimer', style: TextStyle(color: kErrorText, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  final ok = await PlaylistService.remove(pl.id);
  final notifier = ref.read(noticeProvider.notifier);
  if (ok) {
    ref.invalidate(playlistsProvider);
    notifier.show('Playlist supprimée');
  } else {
    notifier.show('Suppression impossible');
  }
}

Future<String?> _promptName(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheetBg,
      title: Text(title, style: const TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: kTextPrimary),
        cursorColor: kAccent,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Nom de la playlist',
          hintStyle: TextStyle(color: kTextSecondary),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kAccent)),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler', style: TextStyle(color: kTextSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('OK', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onCreate;
  const _Header({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
      child: Row(
        children: [
          const Text('Ma librairie',
              style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
          const Spacer(),
          _AddButton(onTap: onCreate),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _Tabs({required this.current, required this.onTap});

  static const _labels = ['Tout', 'Favoris', 'Playlists'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final active = current == i;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 22, top: 4, bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_labels[i],
                      style: TextStyle(
                        color: active ? kAccent : kTextSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      )),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 2,
                    width: active ? 22 : 0,
                    color: kAccent,
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

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: kAccent, width: 1.3),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: kAccent, size: 16),
            SizedBox(width: 4),
            Text('Créer', style: TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  const _PlaylistRow({required this.playlist, required this.onTap, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kAccentLight, kAccent],
                ),
              ),
              child: const Icon(Icons.queue_music, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.title,
                      style: const TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(playlist.countLabel, style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: kSheetBg,
              icon: const Icon(Icons.more_horiz, color: kTextSecondary, size: 24),
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renommer', style: TextStyle(color: kTextPrimary))),
                PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: kErrorText))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineLoader extends StatelessWidget {
  const _InlineLoader();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: kAccent)),
      );
}

class _InlineMessage extends StatelessWidget {
  final String text;
  const _InlineMessage(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(text, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
      );
}
