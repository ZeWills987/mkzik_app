import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../models/track_visuals.dart';
import '../models/playlist.dart';
import '../providers/player_provider.dart';
import '../providers/import_provider.dart';
import '../providers/favourites_provider.dart';
import '../providers/notice_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/track_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import '../navigation/app_nav.dart';
import 'track_cover.dart';

/// Vignette carrée d'un track (cover réseau ou dégradé + note).
class TrackSquareThumb extends StatelessWidget {
  final Track track;
  final double size;
  const TrackSquareThumb({super.key, required this.track, this.size = 36});

  @override
  Widget build(BuildContext context) {
    if (track.hasCover) return TrackCover(track: track, size: size, radius: 8);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: track.gradientColors,
        ),
      ),
      child: Icon(Icons.music_note, color: Colors.white70, size: size * 0.5),
    );
  }
}

/// Badge "EXT" pour les tracks externes non intégrés.
class ExternalBadge extends StatelessWidget {
  const ExternalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    const color = kBadgeGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: const Text('EXT',
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }
}

// Couleurs de marque des plateformes externes.
const kYtMusicRed = Color(0xFFFF0000);
const kSoundcloudOrange = Color(0xFFFF5500);

/// Logo de la plateforme externe (YouTube Music = rond rouge + ▶, SoundCloud = nuage orange).
class PlatformLogo extends StatelessWidget {
  final ExtPlatform platform;
  final double size;
  const PlatformLogo({super.key, required this.platform, this.size = 18});

  @override
  Widget build(BuildContext context) {
    switch (platform) {
      case ExtPlatform.youtubeMusic:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: kYtMusicRed, shape: BoxShape.circle),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.72),
        );
      case ExtPlatform.soundcloud:
        return Icon(Icons.cloud, color: kSoundcloudOrange, size: size + 3);
      case ExtPlatform.other:
        return const ExternalBadge();
    }
  }
}

/// Badge plateforme d'un track externe (logo seul, déduit de la source).
class PlatformBadge extends StatelessWidget {
  final Track track;
  final double size;
  const PlatformBadge({super.key, required this.track, this.size = 18});

  @override
  Widget build(BuildContext context) => PlatformLogo(platform: track.extPlatform, size: size);
}

/// Ligne de résultat track (style page de recherche) — réutilisable.
/// Tap = lecture, "…" = menu d'actions.
class TrackResultRow extends ConsumerWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final bool showPublishedAt; // affiche "il y a X" (date de sortie) si dispo

  const TrackResultRow({
    super.key,
    required this.track,
    required this.onTap,
    required this.onMenu,
    this.showPublishedAt = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(playerProvider.select((s) => s.currentTrack?.id));
    final active = currentId == track.id;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            TrackSquareThumb(track: track, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre cliquable → page détaillée de la track
                  GestureDetector(
                    onTap: () => appNav.openTrack(context, track),
                    child: Text(track.title,
                        style: TextStyle(
                          color: active ? kAccent : kTextPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: 4),
                  // Nom d'artiste cliquable → son profil
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: track.artist.isEmpty ? null : () => appNav.openProfile(context, track.artist),
                          child: Text(track.artist,
                              style: const TextStyle(color: kTextSecondary, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      Text('  ·  ${track.durationFormatted}',
                          style: const TextStyle(color: kTextSecondary, fontSize: 13)),
                    ],
                  ),
                  // Date de sortie en relatif (page search uniquement)
                  if (showPublishedAt && track.publishedLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(track.publishedLabel!,
                        style: const TextStyle(color: kTextSecondary, fontSize: 11.5),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (track.isExternal) Padding(padding: const EdgeInsets.only(right: 6), child: PlatformBadge(track: track)),
            GestureDetector(
              onTap: onMenu,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz, color: kTextSecondary, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ouvre le bottom sheet d'actions d'un track et câble toutes les actions
/// sur le player + l'API (réutilisé par la recherche et les pages liste).
void showTrackActionsSheet(BuildContext context, WidgetRef ref, Track track) {
  void toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kSurface, behavior: SnackBarBehavior.floating),
    );
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: kSheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TrackMenuSheet(
      track: track,
      onPlayNext: () {
        Navigator.pop(ctx);
        ref.read(playerProvider.notifier).addToList(track, playNext: true);
        ref.read(noticeProvider.notifier).show('Sera joué ensuite', icon: NoticeIcon.playNext);
      },
      onAddToList: () {
        Navigator.pop(ctx);
        ref.read(playerProvider.notifier).addToList(track);
        ref.read(noticeProvider.notifier).show('Ajouté à la liste courante', icon: NoticeIcon.queue);
      },
      onLike: () async {
        Navigator.pop(ctx);
        if (track.apiId == null) {
          toast('Action indisponible pour ce titre');
          return;
        }
        final res = await TrackService.toggleLike(track.apiId!);
        if (!res.ok) {
          toast('Échec, réessaie');
          return;
        }
        ref.invalidate(favouritesProvider); // la librairie se met à jour
        toast(res.isLiked ? 'Ajouté aux favoris' : 'Retiré des favoris');
      },
      onShare: () {
        Navigator.pop(ctx);
        Clipboard.setData(ClipboardData(text: track.pageUrl.isNotEmpty ? track.pageUrl : track.title));
        ref.read(noticeProvider.notifier).show('Lien copié', icon: NoticeIcon.share);
      },
      onImport: () {
        Navigator.pop(ctx);
        // Lance l'import : la progression s'affiche dans la bannière (notifications)
        ref.read(importProvider.notifier).startAndWait(track);
      },
      onAddToPlaylist: () {
        Navigator.pop(ctx);
        showAddToPlaylistSheet(context, ref, track);
      },
      onOther: (label) {
        Navigator.pop(ctx);
        toast('$label — à venir');
      },
    ),
  );
}

class _TrackMenuSheet extends StatelessWidget {
  final Track track;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToList;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onImport;
  final VoidCallback onAddToPlaylist;
  final ValueChanged<String> onOther;

  const _TrackMenuSheet({
    required this.track,
    required this.onPlayNext,
    required this.onAddToList,
    required this.onLike,
    required this.onShare,
    required this.onImport,
    required this.onAddToPlaylist,
    required this.onOther,
  });

  @override
  Widget build(BuildContext context) {
    final external = track.isExternal;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                TrackSquareThumb(track: track),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(track.artist,
                                style: const TextStyle(color: kTextSecondary, fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (external) const SizedBox(width: 8),
                          if (external) PlatformBadge(track: track),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: kBorderSoft),
          _MenuItem(icon: Icons.playlist_play, label: 'JOUER ENSUITE', onTap: onPlayNext),
          _MenuItem(icon: Icons.queue_music, label: 'AJOUTER À LA LISTE COURANTE', onTap: onAddToList),
          // Like indisponible pour un externe non importé (pas encore sur Mkzik)
          if (!external)
            _MenuItem(
              icon: track.isFavoris ? Icons.favorite : Icons.favorite_border,
              label: track.isFavoris ? 'RETIRER DES FAVORIS' : 'LIKER',
              accent: track.isFavoris,
              onTap: onLike,
            ),
          // Ajout en playlist : nécessite un id Mkzik → masqué pour les externes
          if (!external) _MenuItem(icon: Icons.library_add, label: 'AJOUTER À UNE PLAYLIST', onTap: onAddToPlaylist),
          // Partage indisponible pour un externe non importé (pas d'URL Mkzik)
          if (!external) _MenuItem(icon: Icons.ios_share, label: 'PARTAGER', onTap: onShare),
          _MenuItem(icon: Icons.download, label: 'TÉLÉCHARGER HORS LIGNE', onTap: () => onOther('Téléchargement')),
          if (external)
            _MenuItem(icon: Icons.cloud_upload, label: 'IMPORTER SUR MKZIK', accent: true, onTap: onImport),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = accent ? kAccent : kTextPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: accent ? kAccent : kTextSecondary, size: 22),
            const SizedBox(width: 18),
            Text(label,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Ouvre une feuille pour ajouter [track] à une des playlists de l'utilisateur.
void showAddToPlaylistSheet(BuildContext context, WidgetRef ref, Track track) {
  if (track.apiId == null) {
    ref.read(noticeProvider.notifier).show('Indisponible pour ce titre');
    return;
  }
  showModalBottomSheet(
    context: context,
    backgroundColor: kSheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  final Track track;
  const _AddToPlaylistSheet({required this.track});

  Future<void> _add(BuildContext context, WidgetRef ref, Playlist pl) async {
    Navigator.pop(context);
    final ok = await PlaylistService.addTrack(pl.id, track.apiId!);
    final notifier = ref.read(noticeProvider.notifier);
    if (ok) {
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistTracksProvider(pl.id));
      notifier.show('Ajouté à « ${pl.title} »', icon: NoticeIcon.queue);
    } else {
      notifier.show('Ajout impossible');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistsProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Ajouter à une playlist',
                  style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const Divider(height: 1, color: kBorderSoft),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: kAccent),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Playlists indisponibles.', style: TextStyle(color: kTextSecondary)),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Aucune playlist — crée-en une dans la Bibliothèque.',
                      style: TextStyle(color: kTextSecondary)),
                );
              }
              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: playlists.length,
                  itemBuilder: (_, i) {
                    final pl = playlists[i];
                    return _MenuItem(
                      icon: Icons.queue_music,
                      label: pl.title.toUpperCase(),
                      onTap: () => _add(context, ref, pl),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
