import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playlist_provider.dart';
import '../../services/playlist_import_service.dart';
import '../../services/track_resolve_service.dart';
import '../../theme/app_theme.dart';

/// Import d'une playlist collée ou partagée (`kind: "playlist"`).
/// SoundCloud : les titres sont listés (seule l'url est fiable, le vrai nom
/// arrive avec l'import). YouTube : Python ne lit pas le contenu, l'import
/// passe par le compte Google lié.
class PlaylistImportView extends ConsumerStatefulWidget {
  final ResolvePlaylist playlist;
  const PlaylistImportView({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistImportView> createState() => _PlaylistImportViewState();
}

class _PlaylistImportViewState extends ConsumerState<PlaylistImportView> {
  bool _loading = false;
  PlaylistImportSummary? _done;
  String? _error;
  bool _needsReconnect = false;

  ResolvePlaylist get _p => widget.playlist;

  Future<void> _import() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsReconnect = false;
    });
    final outcome = _p.isSoundcloud
        ? await PlaylistImportService.importSoundcloud(_p)
        : await PlaylistImportService.importYoutube(_p);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (outcome) {
        case PlaylistImportDone(:final summary):
          _done = summary;
          ref.invalidate(playlistsProvider);
        case PlaylistImportNeedsReconnect():
          _needsReconnect = true;
        case PlaylistImportFailed(:final message):
          _error = message;
      }
    });
  }

  String get _heading => _p.title.isNotEmpty ? _p.title : (_p.isSoundcloud ? 'Playlist SoundCloud' : 'Playlist YouTube');

  @override
  Widget build(BuildContext context) {
    final newCount = _p.tracks.where((t) => !t.inMkzik).length;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text(_heading,
            style: const TextStyle(color: kTextPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          [
            if (_p.artist.isNotEmpty) _p.artist,
            if (_p.isSoundcloud) '${_p.trackCount} titres' else 'YouTube',
          ].join(' · '),
          style: const TextStyle(color: kTextSecondary, fontSize: 13),
        ),
        if (_p.truncated)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Playlist très longue : seuls les 500 premiers titres seront importés.',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
          ),
        if (_p.isSoundcloud)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '$newCount à télécharger · ${_p.tracks.length - newCount} déjà sur Mkzik',
              style: const TextStyle(color: kTextSecondary, fontSize: 12.5),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('L\'import utilise ton compte Google lié.',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
          ),
        const SizedBox(height: 16),
        if (_done != null)
          Text('Importée : ${_done!.label}',
              style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w600))
        else
          FilledButton.icon(
            onPressed: _loading ? null : _import,
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            icon: _loading
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.playlist_add_rounded, size: 20),
            label: Text(_loading ? 'Import en cours…' : 'Importer la playlist'),
          ),
        if (_needsReconnect)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Ton compte Google n\'est plus relié. Reconnecte YouTube depuis ton profil, puis réessaie.',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          ),
        if (_p.isSoundcloud) ...[
          const SizedBox(height: 20),
          for (var i = 0; i < _p.tracks.length; i++) _TrackLine(index: i, track: _p.tracks[i]),
        ],
      ],
    );
  }
}

class _TrackLine extends StatelessWidget {
  final int index;
  final Track track;
  const _TrackLine({required this.index, required this.track});

  // Le titre est vide tant que le titre n'est pas lu : on affiche le dernier
  // segment de l'url (slug), à défaut « Titre N ».
  String get _label {
    final title = track.title;
    if (title.isNotEmpty) return title;
    final segs = Uri.tryParse(track.pageUrl)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    return segs.isNotEmpty ? segs.last.replaceAll('-', ' ') : 'Titre ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final inMkzik = track.inMkzik;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${index + 1}', style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(_label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kTextPrimary, fontSize: 14)),
          ),
          if (inMkzik)
            const Icon(Icons.check_circle_rounded, color: kAccent, size: 18),
        ],
      ),
    );
  }
}
