import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/profile.dart';
import '../../models/track_visuals.dart' show gradientForSeed;
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../auth/auth_widgets.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final Profile profile;
  final String username;

  const EditProfileScreen({super.key, required this.profile, required this.username});

  static Future<void> open(BuildContext context, Profile profile, String username) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile, username: username)),
    );
  }

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _picker = ImagePicker();
  File? _avatar;
  File? _background;

  late final _username = TextEditingController(text: widget.profile.username);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _firstName = TextEditingController(text: widget.profile.firstName);
  late final _lastName = TextEditingController(text: widget.profile.lastName);
  final _password = TextEditingController();
  late String _birthDate = widget.profile.birthDate;

  bool _savingText = false;
  bool _savingPhotos = false;

  @override
  void dispose() {
    for (final c in [_username, _email, _firstName, _lastName, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool isAvatar) async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    setState(() {
      if (isAvatar) {
        _avatar = File(x.path);
      } else {
        _background = File(x.path);
      }
    });
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    DateTime initial = DateTime(now.year - 18);
    final parsed = DateTime.tryParse(_birthDate);
    if (parsed != null) initial = parsed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.dark(primary: kAccent, surface: kSurface)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _birthDate =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _savePhotos() async {
    if (_avatar == null || _background == null) {
      _toast('Choisis un avatar ET une bannière');
      return;
    }
    setState(() => _savingPhotos = true);
    final res = await ProfileService.updateAvatar(avatar: _avatar!, background: _background!);
    if (!mounted) return;
    setState(() => _savingPhotos = false);
    _toast(res.message);
    if (res.ok) {
      ref.invalidate(profileProvider(widget.username));
    }
  }

  Future<void> _saveText() async {
    // N'envoie que les champs modifiés (+ password si saisi)
    final fields = <String, String>{};
    if (_username.text.trim() != widget.profile.username) fields['username'] = _username.text;
    if (_email.text.trim() != widget.profile.email) fields['email'] = _email.text;
    if (_firstName.text.trim() != widget.profile.firstName) fields['firstName'] = _firstName.text;
    if (_lastName.text.trim() != widget.profile.lastName) fields['lastName'] = _lastName.text;
    if (_birthDate != widget.profile.birthDate) fields['birthDate'] = _birthDate;
    if (_password.text.isNotEmpty) fields['password'] = _password.text;

    if (fields.isEmpty) {
      _toast('Aucune modification');
      return;
    }
    setState(() => _savingText = true);
    final res = await ProfileService.updateProfile(fields);
    if (!mounted) return;
    setState(() => _savingText = false);
    _toast(res.message);
    if (res.ok) {
      if (res.newToken != null) {
        // Nouveau JWT fourni par le backend (changement d'username) :
        // on le persiste et on met à jour l'auth state depuis son payload.
        await ref.read(authProvider.notifier).applyNewToken(res.newToken!);
      } else if (fields.containsKey('username')) {
        ref.read(authProvider.notifier).updateUsername(_username.text.trim());
      }
      ref.invalidate(profileProvider(widget.username));
      Navigator.of(context).maybePop();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kSurface, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Modifier le profil',
            style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        children: [
          _PhotosEditor(
            profile: widget.profile,
            avatar: _avatar,
            background: _background,
            onPickAvatar: () => _pick(true),
            onPickBackground: () => _pick(false),
          ),
          // Mise à jour des photos (les 2 requises)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Avatar + bannière doivent être choisis ensemble pour la mise à jour des photos.',
                  style: TextStyle(color: kTextSecondary, fontSize: 11.5, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                AuthButton(label: 'Mettre à jour les photos', loading: _savingPhotos, onPressed: _savePhotos),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 6),
            child: Text('Informations',
                style: TextStyle(color: kTextSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                AuthField(controller: _username, label: 'Pseudo', icon: Icons.person_outline),
                const SizedBox(height: 14),
                AuthField(controller: _email, label: 'Adresse mail', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: AuthField(controller: _lastName, label: 'Nom', icon: Icons.badge_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: AuthField(controller: _firstName, label: 'Prénom', icon: Icons.badge_outlined)),
                  ],
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: TextEditingController(text: _birthDate),
                  label: 'Date de naissance',
                  icon: Icons.cake_outlined,
                  readOnly: true,
                  onTap: _pickBirthDate,
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _password,
                  label: 'Nouveau mot de passe (optionnel)',
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 24),
                AuthButton(label: 'Enregistrer', loading: _savingText, onPressed: _saveText),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Éditeur de photos : bannière + avatar ────────────────────────────────────

class _PhotosEditor extends StatelessWidget {
  final Profile profile;
  final File? avatar;
  final File? background;
  final VoidCallback onPickAvatar;
  final VoidCallback onPickBackground;

  const _PhotosEditor({
    required this.profile,
    required this.avatar,
    required this.background,
    required this.onPickAvatar,
    required this.onPickBackground,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientForSeed(profile.username.hashCode);

    return SizedBox(
      height: 210,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Bannière
          GestureDetector(
            onTap: onPickBackground,
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (background != null)
                    Image.file(background!, fit: BoxFit.cover)
                  else if (mediaUrl(profile.backgroundUrl).isNotEmpty)
                    CachedNetworkImage(imageUrl: mediaUrl(profile.backgroundUrl), fit: BoxFit.cover)
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                      ),
                    ),
                  Container(color: Colors.black.withValues(alpha: 0.25)),
                  const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.white70, size: 28)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, kBg], stops: const [0.55, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Avatar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onPickAvatar,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [kAccentLight, colors.first]),
                  ),
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBg, width: 3)),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: colors.first,
                      backgroundImage: avatar != null
                          ? FileImage(avatar!)
                          : (mediaUrl(profile.avatarUrl).isNotEmpty
                              ? CachedNetworkImageProvider(mediaUrl(profile.avatarUrl)) as ImageProvider
                              : null),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.25)),
                        child: const Icon(Icons.add_a_photo_outlined, color: Colors.white70, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
