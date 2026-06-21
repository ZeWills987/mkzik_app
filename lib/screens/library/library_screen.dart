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

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              const SliverToBoxAdapter(child: _Header()),

              // ── Playlists ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _SectionHeader(
                  icon: Icons.queue_music,
                  label: 'Playlists',
                  trailing: _AddButton(onTap: () => _createPlaylist(context, ref)),
                ),
              ),
              _playlistsSliver(context, ref, plAsync),

              // ── Titres likés ────────────────────────────────────────────
              const SliverToBoxAdapter(
                child: _SectionHeader(icon: Icons.favorite, label: 'Titres likés'),
              ),
              _favouritesSliver(context, ref, favAsync),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Slivers de sections ───────────────────────────────────────────────────────

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
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Ma librairie',
            style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _SectionHeader({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(
        children: [
          Icon(icon, color: kAccent, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          ?trailing,
        ],
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
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: kAccent)),
      );
}

class _InlineMessage extends StatelessWidget {
  final String text;
  const _InlineMessage(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Text(text, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
      );
}
