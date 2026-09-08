import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/notice_provider.dart';
import '../../services/album_service.dart';
import '../../services/track_upload_service.dart';
import '../../theme/app_theme.dart';

const _kGenres = [
  'Rap', 'Trap', 'Afro', 'Zouk', 'Kompa', 'R&B', 'Pop', 'Soul',
  'Reggae', 'Dancehall', 'Electronic', 'Jazz', 'Rock', 'Variété',
];

class _AlbumTrack {
  String title;
  String audioPath;
  String audioName;
  _AlbumTrack({required this.title, required this.audioPath, required this.audioName});
}

class UploadAlbumScreen extends ConsumerStatefulWidget {
  const UploadAlbumScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UploadAlbumScreen()),
      );

  @override
  ConsumerState<UploadAlbumScreen> createState() => _UploadAlbumScreenState();
}

class _UploadAlbumScreenState extends ConsumerState<UploadAlbumScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  String? _coverPath;
  final Set<String> _selectedGenres = {};
  String _status = 'PUBLIC';
  final List<_AlbumTrack> _tracks = [];
  bool _loading = false;
  String? _error;
  // Progression : null = pas commencé, sinon "Track 2/5…"
  String? _progress;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _coverPath = picked.path);
  }

  Future<void> _addTrack() async {
    final file = await FilePickerPlatform.instance.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'mp4', 'ogg', 'wav', 'flac'],
    );
    if (file == null) return;
    final path = file.path;
    if (path == null) return;
    final title = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    setState(() => _tracks.add(_AlbumTrack(title: title, audioPath: path, audioName: file.name)));
  }

  void _removeTrack(int i) => setState(() => _tracks.removeAt(i));

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    setState(() { _error = null; _progress = null; });

    if (title.isEmpty) { setState(() => _error = "Le titre de l'album est obligatoire"); return; }
    if (_dateCtrl.text.trim().isEmpty) { setState(() => _error = 'La date de sortie est obligatoire'); return; }
    if (_tracks.isEmpty) { setState(() => _error = 'Ajoute au moins une track'); return; }

    setState(() => _loading = true);
    try {
      setState(() => _progress = "Création de l'album…");
      final albumId = await AlbumService.create(
        title: title,
        releaseDate: _dateCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        coverPath: _coverPath,
        genres: _selectedGenres.toList(),
        status: _status,
      );

      for (var i = 0; i < _tracks.length; i++) {
        final t = _tracks[i];
        setState(() => _progress = 'Track ${i + 1}/${_tracks.length} : ${t.title}…');
        await TrackUploadService.upload(
          title: t.title,
          audioPath: t.audioPath,
          genres: _selectedGenres.toList(),
          status: _status,
          albumId: albumId,
        );
      }

      if (!mounted) return;
      ref.read(noticeProvider.notifier).show('Album publié !');
      Navigator.of(context).maybePop();
    } on AlbumUploadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TrackUploadException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() { _loading = false; _progress = null; });
    }
  }

  // ── UI helpers ───────────────────────────────────────────────────────────────

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
            style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      );

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
        title: const Text('Publier un album',
            style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Titre album ────────────────────────────────────────────────
            _sectionLabel("Titre de l'album *"),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              textInputAction: TextInputAction.next,
              decoration: _inputDec("Titre de l'album", Icons.album_outlined),
            ),
            const SizedBox(height: 20),

            // ── Date de sortie ─────────────────────────────────────────────
            _sectionLabel('Date de sortie *'),
            TextField(
              controller: _dateCtrl,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              readOnly: true,
              decoration: _inputDec('AAAA-MM-JJ', Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1950),
                  lastDate: DateTime(2100),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(primary: kAccent, surface: kSurface),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  _dateCtrl.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              },
            ),
            const SizedBox(height: 20),

            // ── Description ────────────────────────────────────────────────
            _sectionLabel('Description'),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              maxLines: 3,
              decoration: _inputDec('Description (facultatif)', Icons.notes),
            ),
            const SizedBox(height: 20),

            // ── Genres ─────────────────────────────────────────────────────
            _sectionLabel('Genres'),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _kGenres.map((g) {
                final sel = _selectedGenres.contains(g);
                return GestureDetector(
                  onTap: () => setState(() { sel ? _selectedGenres.remove(g) : _selectedGenres.add(g); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? kAccent.withValues(alpha: 0.18) : kSurface,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: sel ? kAccent : kBorder, width: sel ? 1.5 : 1),
                    ),
                    child: Text(g,
                        style: TextStyle(
                          color: sel ? kAccent : kTextSecondary,
                          fontSize: 12.5,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Pochette ───────────────────────────────────────────────────
            _sectionLabel('Pochette'),
            GestureDetector(
              onTap: _loading ? null : _pickCover,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _coverPath != null ? kAccent.withValues(alpha: 0.5) : kBorder),
                ),
                child: _coverPath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Row(children: [
                          SizedBox(width: 80, child: Image.file(File(_coverPath!), fit: BoxFit.cover)),
                          const SizedBox(width: 14),
                          const Expanded(child: Text('Image sélectionnée',
                              style: TextStyle(color: kTextPrimary, fontSize: 13.5))),
                          GestureDetector(
                            onTap: () => setState(() => _coverPath = null),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 14),
                              child: Icon(Icons.close, color: kTextSecondary, size: 20),
                            ),
                          ),
                        ]),
                      )
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: kTextSecondary, size: 24),
                        SizedBox(width: 10),
                        Text('Ajouter une pochette', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                      ]),
              ),
            ),
            const SizedBox(height: 20),

            // ── Visibilité ─────────────────────────────────────────────────
            _sectionLabel('Visibilité'),
            Row(children: [
              _StatusChip(label: 'Public', icon: Icons.public, value: 'PUBLIC',
                  current: _status, onTap: () => setState(() => _status = 'PUBLIC')),
              const SizedBox(width: 10),
              _StatusChip(label: 'Privé', icon: Icons.lock_outline, value: 'PRIVATE',
                  current: _status, onTap: () => setState(() => _status = 'PRIVATE')),
            ]),
            const SizedBox(height: 28),

            // ── Tracks ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _sectionLabel('Tracks${_tracks.isEmpty ? '' : ' (${_tracks.length})'}')),
                TextButton.icon(
                  onPressed: _loading ? null : _addTrack,
                  icon: const Icon(Icons.add, size: 18, color: kAccent),
                  label: const Text('Ajouter', style: TextStyle(color: kAccent, fontSize: 13)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ),
            if (_tracks.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: const Center(
                  child: Text('Aucune track ajoutée',
                      style: TextStyle(color: kTextSecondary, fontSize: 13)),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tracks.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final t = _tracks.removeAt(oldIndex);
                    _tracks.insert(newIndex, t);
                  });
                },
                itemBuilder: (ctx, i) {
                  final t = _tracks[i];
                  return _TrackItem(
                    key: ValueKey('${t.audioPath}_$i'),
                    index: i,
                    track: t,
                    onTitleChanged: (v) => setState(() => t.title = v),
                    onRemove: () => _removeTrack(i),
                  );
                },
              ),
            const SizedBox(height: 28),

            // ── Progression ────────────────────────────────────────────────
            if (_progress != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: kAccent, strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_progress!,
                      style: const TextStyle(color: kAccent, fontSize: 12.5))),
                ]),
              ),
            ],

            // ── Erreur ─────────────────────────────────────────────────────
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
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: kErrorText, fontSize: 12.5))),
                ]),
              ),
            ],

            // ── Publier ────────────────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  disabledBackgroundColor: kAccent.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.album, size: 20),
                        SizedBox(width: 10),
                        Text('Publier l\'album',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item track dans la liste ──────────────────────────────────────────────────

class _TrackItem extends StatefulWidget {
  final int index;
  final _AlbumTrack track;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onRemove;

  const _TrackItem({
    super.key,
    required this.index,
    required this.track,
    required this.onTitleChanged,
    required this.onRemove,
  });

  @override
  State<_TrackItem> createState() => _TrackItemState();
}

class _TrackItemState extends State<_TrackItem> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.track.title);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_handle, color: kTextSecondary, size: 20),
          const SizedBox(width: 10),
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${widget.index + 1}',
                style: const TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onTitleChanged,
              style: const TextStyle(color: kTextPrimary, fontSize: 13),
              cursorColor: kAccent,
              decoration: InputDecoration(
                hintText: widget.track.audioName,
                hintStyle: const TextStyle(color: kTextSecondary, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: kTextSecondary, size: 18),
            onPressed: widget.onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Chip visibilité ───────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String current;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.icon, required this.value,
      required this.current, required this.onTap});

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
          border: Border.all(color: selected ? kAccent : kBorder, width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? kAccent : kTextSecondary, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: selected ? kAccent : kTextSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          )),
        ]),
      ),
    );
  }
}
