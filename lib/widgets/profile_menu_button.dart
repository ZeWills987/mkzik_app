import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/profile.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../utils/media.dart';
import '../screens/settings/account_settings_screen.dart';
import '../screens/upload/upload_track_screen.dart';
import '../screens/upload/upload_album_screen.dart';
import '../screens/profile/youtube_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/resolve/resolve_track_screen.dart';

enum ProfileMenuAction { editProfile, youtube, uploadTrack, uploadAlbum, importLink, settings, logout }

final _urlPattern = RegExp(r'https?://\S+');

/// Dialog de collage d'un lien (YouTube / SoundCloud / TikTok) → ouvre
/// l'identification du titre (même flow que le partage depuis une autre app).
Future<void> _promptImportLink(BuildContext context) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Importer depuis un lien',
          style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: kTextPrimary),
        cursorColor: kAccent,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'Lien YouTube, SoundCloud ou TikTok',
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
          child: const Text('Importer', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  final match = url == null ? null : _urlPattern.firstMatch(url)?.group(0);
  if (match == null || !context.mounted) return;
  ResolveTrackScreen.open(context, match);
}

/// Avatar + menu d'actions du compte connecté (modifier profil, YouTube,
/// publier, paramètres, déconnexion). Réutilisé sur le header d'accueil et
/// sur son propre profil.
class ProfileMenuButton extends ConsumerWidget {
  final Profile profile;
  final Color accent;
  final double size;

  const ProfileMenuButton({super.key, required this.profile, this.accent = kAccent, this.size = 36});

  void _handle(BuildContext context, WidgetRef ref, ProfileMenuAction action) {
    switch (action) {
      case ProfileMenuAction.editProfile:
        EditProfileScreen.open(context, profile, profile.username);
      case ProfileMenuAction.youtube:
        YoutubeScreen.open(context);
      case ProfileMenuAction.uploadTrack:
        UploadTrackScreen.open(context);
      case ProfileMenuAction.uploadAlbum:
        UploadAlbumScreen.open(context);
      case ProfileMenuAction.importLink:
        _promptImportLink(context);
      case ProfileMenuAction.settings:
        AccountSettingsScreen.open(context);
      case ProfileMenuAction.logout:
        ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = mediaUrl(profile.avatarUrl);
    final initial = profile.username.isNotEmpty ? profile.username[0].toUpperCase() : '?';

    return PopupMenuButton<ProfileMenuAction>(
      onSelected: (a) => _handle(context, ref, a),
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorderSoft),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        _item(ProfileMenuAction.editProfile, Icons.edit_outlined, 'Modifier le profil'),
        _item(ProfileMenuAction.youtube, Icons.music_video_outlined, 'YouTube Music',
            color: const Color(0xFFFF0000)),
        const PopupMenuDivider(height: 8),
        _item(ProfileMenuAction.uploadTrack, Icons.cloud_upload_outlined, 'Publier une zik', color: kAccent),
        _item(ProfileMenuAction.uploadAlbum, Icons.album_outlined, 'Publier un album', color: kAccent),
        const PopupMenuDivider(height: 8),
        _item(ProfileMenuAction.importLink, Icons.link, 'Importer depuis un lien', color: kAccent),
        const PopupMenuDivider(height: 8),
        _item(ProfileMenuAction.settings, Icons.manage_accounts_outlined, 'Paramètres'),
        _item(ProfileMenuAction.logout, Icons.logout, 'Déconnexion', color: kErrorText),
      ],
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
        ),
        child: ClipOval(
          child: avatar.isNotEmpty
              ? CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover)
              : Center(
                  child: Text(initial,
                      style: TextStyle(
                          color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w700)),
                ),
        ),
      ),
    );
  }

  PopupMenuItem<ProfileMenuAction> _item(ProfileMenuAction action, IconData icon, String label,
      {Color? color}) {
    final c = color ?? kTextPrimary;
    return PopupMenuItem(
      value: action,
      child: Row(children: [
        Icon(icon, color: c, size: 18),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: c, fontSize: 13.5, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
