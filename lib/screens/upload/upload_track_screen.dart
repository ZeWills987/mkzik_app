import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/notice_provider.dart';
import '../../services/track_upload_service.dart';
import '../../theme/app_theme.dart';

const _kGenres = [
  'Rap', 'Trap', 'Afro', 'Zouk', 'Kompa', 'R&B', 'Pop', 'Soul',
  'Reggae', 'Dancehall', 'Electronic', 'Jazz', 'Rock', 'Variété',
];

class UploadTrackScreen extends ConsumerStatefulWidget {
  const UploadTrackScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UploadTrackScreen()),
      );

  @override
  ConsumerState<UploadTrackScreen> createState() => _UploadTrackScreenState();
}

class _UploadTrackScreenState extends ConsumerState<UploadTrackScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _audioPath;
  String? _audioName;
  String? _coverPath;
  final Set<String> _selectedGenres = {};
  String _status = 'PUBLIC';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final file = await FilePickerPlatform.instance.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'mp4', 'ogg', 'wav', 'flac'],
    );
    if (file == null) return;
    final path = file.path;
    if (path == null) return;
    setState(() {
      _audioPath = path;
      _audioName = file.name;
      if (_titleCtrl.text.isEmpty) {
        // Auto-remplir le titre depuis le nom de fichier (retire l'extension)
        _titleCtrl.text = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _coverPath = picked.path);
  }

  Future<void> _upload() async {
    final title = _titleCtrl.text.trim();
    setState(() => _error = null);
    if (_audioPath == null) {
      setState(() => _error = 'Sélectionne un fichier audio');
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = 'Le titre est obligatoire');
      return;
    }
    setState(() => _loading = true);
    try {
      await TrackUploadService.upload(
        title: title,
        audioPath: _audioPath!,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        thumbnailPath: _coverPath,
        genres: _selectedGenres.toList(),
        status: _status,
      );
      if (!mounted) return;
      ref.read(noticeProvider.notifier).show('Zik publiée !');
      Navigator.of(context).maybePop();
    } on TrackUploadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers UI ───────────────────────────────────────────────────────────────

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
        filled: true,
        fillColor: kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      );

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Publier une zik',
            style: TextStyle(
                color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Fichier audio ──────────────────────────────────────────────
            _sectionLabel('Fichier audio *'),
            GestureDetector(
              onTap: _loading ? null : _pickAudio,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _audioPath != null
                        ? kAccent.withValues(alpha: 0.5)
                        : kBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _audioPath != null ? Icons.audio_file : Icons.upload_file,
                      color: _audioPath != null ? kAccent : kTextSecondary,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _audioName ?? 'Sélectionner un fichier audio…',
                        style: TextStyle(
                          color: _audioPath != null ? kTextPrimary : kTextSecondary,
                          fontSize: 13.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_audioPath != null)
                      const Icon(Icons.check_circle, color: kAccent, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'mp3, m4a, ogg, wav, flac acceptés',
              style: TextStyle(color: kTextSecondary, fontSize: 11),
            ),
            const SizedBox(height: 20),

            // ── Titre ─────────────────────────────────────────────────────
            _sectionLabel('Titre *'),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              textInputAction: TextInputAction.next,
              decoration: _inputDec('Titre de la track', Icons.title),
            ),
            const SizedBox(height: 20),

            // ── Description ───────────────────────────────────────────────
            _sectionLabel('Description'),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              maxLines: 3,
              decoration: _inputDec('Description (facultatif)', Icons.notes),
            ),
            const SizedBox(height: 20),

            // ── Genres ────────────────────────────────────────────────────
            _sectionLabel('Genres'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kGenres.map((g) {
                final selected = _selectedGenres.contains(g);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedGenres.remove(g);
                    } else {
                      _selectedGenres.add(g);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? kAccent.withValues(alpha: 0.18) : kSurface,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: selected ? kAccent : kBorder,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: selected ? kAccent : kTextSecondary,
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Pochette ─────────────────────────────────────────────────
            _sectionLabel('Pochette'),
            GestureDetector(
              onTap: _loading ? null : _pickCover,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _coverPath != null
                        ? kAccent.withValues(alpha: 0.5)
                        : kBorder,
                  ),
                ),
                child: _coverPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: Image.file(File(_coverPath!), fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text('Image sélectionnée',
                                  style: TextStyle(color: kTextPrimary, fontSize: 13.5)),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _coverPath = null),
                              child: const Padding(
                                padding: EdgeInsets.only(right: 14),
                                child: Icon(Icons.close, color: kTextSecondary, size: 20),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: kTextSecondary, size: 24),
                          SizedBox(width: 10),
                          Text('Ajouter une pochette',
                              style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Visibilité ────────────────────────────────────────────────
            _sectionLabel('Visibilité'),
            Row(
              children: [
                _StatusChip(
                  label: 'Public',
                  icon: Icons.public,
                  value: 'PUBLIC',
                  current: _status,
                  onTap: () => setState(() => _status = 'PUBLIC'),
                ),
                const SizedBox(width: 10),
                _StatusChip(
                  label: 'Privé',
                  icon: Icons.lock_outline,
                  value: 'PRIVATE',
                  current: _status,
                  onTap: () => setState(() => _status = 'PRIVATE'),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Erreur ────────────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kError.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kError.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: kErrorText, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(color: kErrorText, fontSize: 12.5)),
                  ),
                ]),
              ),
            ],

            // ── Bouton publier ────────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  disabledBackgroundColor: kAccent.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Publier',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String current;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kAccent.withValues(alpha: 0.18) : kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kAccent : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? kAccent : kTextSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? kAccent : kTextSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
