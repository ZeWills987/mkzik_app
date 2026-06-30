import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/yt_playlist.dart';
import '../../providers/youtube_provider.dart';
import '../../services/api_client.dart';
import '../../services/youtube_service.dart' show YoutubeService, YoutubeNeedsReconnectException;
import '../../theme/app_theme.dart';

class YoutubeScreen extends ConsumerStatefulWidget {
  const YoutubeScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const YoutubeScreen()),
      );

  @override
  ConsumerState<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends ConsumerState<YoutubeScreen> with WidgetsBindingObserver {
  bool _connectLoading = false;
  bool _likesLoading = false;
  String? _likesResult;
  String? _likesError;
  final Map<String, bool> _playlistLoading = {};
  final Map<String, String> _playlistResult = {};
  final Map<String, String> _playlistError = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Retour dans l'app après le browser OAuth → on recheck la connexion
      ref.invalidate(ytConnectedProvider);
      ref.invalidate(ytPlaylistsProvider);
    }
  }

  Future<void> _connect() async {
    setState(() => _connectLoading = true);
    try {
      final url = await YoutubeService.connectUrl();
      if (url == null || url.isEmpty) {
        if (mounted) _showError("Impossible d'obtenir l'URL de connexion");
        return;
      }
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) _showError('Impossible d\'ouvrir le navigateur');
      }
    } finally {
      if (mounted) setState(() => _connectLoading = false);
    }
  }

  Future<void> _importLikes() async {
    setState(() { _likesLoading = true; _likesResult = null; _likesError = null; });
    final res = await YoutubeService.importLikes();
    if (!mounted) return;
    switch (res) {
      case Ok(:final data):
        setState(() => _likesResult = _importLabel(data));
      case Err(:final message, :final statusCode):
        if (statusCode == 403) {
          ref.invalidate(ytConnectedProvider);
          ref.invalidate(ytPlaylistsProvider);
        } else {
          setState(() => _likesError = message);
        }
    }
    setState(() => _likesLoading = false);
  }

  Future<void> _importPlaylist(YtPlaylist playlist) async {
    setState(() {
      _playlistLoading[playlist.id] = true;
      _playlistResult.remove(playlist.id);
      _playlistError.remove(playlist.id);
    });
    final res = await YoutubeService.importPlaylist(playlist.id);
    if (!mounted) return;
    switch (res) {
      case Ok(:final data):
        setState(() => _playlistResult[playlist.id] = _importLabel(data));
      case Err(:final message, :final statusCode):
        if (statusCode == 403) {
          ref.invalidate(ytPlaylistsProvider);
        } else {
          setState(() => _playlistError[playlist.id] = message);
        }
    }
    setState(() => _playlistLoading[playlist.id] = false);
  }

  static String _importLabel(dynamic data) {
    if (data is! Map) return 'Importé';
    final matched = data['matched'];
    final total = data['total'];
    final notFound = (data['not_found'] as List?)?.length ?? 0;
    if (matched == null || total == null) return 'Importé';
    return '$matched/$total titres importés'
        '${notFound > 0 ? ' · $notFound non trouvés' : ''}';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectedAsync = ref.watch(ytConnectedProvider);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Image.network(
              'https://www.youtube.com/favicon.ico',
              width: 20,
              height: 20,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.music_video, color: Color(0xFFFF0000), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('YouTube Music', style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: connectedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: kAccent)),
        error: (_, _) => _ErrorView(onRetry: () => ref.invalidate(ytConnectedProvider)),
        data: (connected) => connected ? _ConnectedView(this) : _DisconnectedView(this),
      ),
    );
  }
}

// ── Vue non connecté ──────────────────────────────────────────────────────────

class _DisconnectedView extends StatelessWidget {
  final _YoutubeScreenState s;
  const _DisconnectedView(this.s);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_video_outlined, size: 72, color: kTextSecondary),
            const SizedBox(height: 20),
            const Text(
              'Connecte ton compte YouTube Music\npour importer tes playlists et tes likes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: s._connectLoading ? null : s._connect,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: s._connectLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.link),
              label: Text(s._connectLoading ? 'Ouverture...' : 'Connecter YouTube Music'),
            ),
            const SizedBox(height: 16),
            Text(
              'Tu seras redirigé vers Google pour autoriser l\'accès en lecture seule à tes données YouTube.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary.withValues(alpha: 0.6), fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Vue connecté ──────────────────────────────────────────────────────────────

class _ConnectedView extends ConsumerWidget {
  final _YoutubeScreenState s;
  const _ConnectedView(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(ytPlaylistsProvider);

    return RefreshIndicator(
      color: kAccent,
      backgroundColor: kSurface,
      onRefresh: () async {
        ref.invalidate(ytPlaylistsProvider);
        await ref.read(ytPlaylistsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _LikesSection(s),
          const Divider(color: kSurface, height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Mes playlists',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: kTextPrimary),
            ),
          ),
          const SizedBox(height: 8),
          playlistsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: kAccent)),
            ),
            error: (err, _) => err is YoutubeNeedsReconnectException
                ? _NeedsReconnectView(s)
                : _ErrorView(onRetry: () => ref.invalidate(ytPlaylistsProvider)),
            data: (playlists) => playlists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Aucune playlist trouvée', style: TextStyle(color: kTextSecondary)),
                    ),
                  )
                : Column(
                    children: playlists
                        .map((p) => _PlaylistTile(playlist: p, s: s))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Section Likes ─────────────────────────────────────────────────────────────

class _LikesSection extends StatelessWidget {
  final _YoutubeScreenState s;
  const _LikesSection(this.s);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Likes YouTube', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: kTextPrimary)),
          const SizedBox(height: 4),
          const Text(
            'Importe les titres que tu as aimés sur YouTube en favoris Mkzik.',
            style: TextStyle(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (s._likesResult != null)
            _ResultChip(text: s._likesResult!, success: true)
          else if (s._likesError != null)
            _ResultChip(text: s._likesError!, success: false),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: s._likesLoading ? null : s._importLikes,
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              disabledBackgroundColor: kAccent.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: s._likesLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.favorite_border, size: 18),
            label: Text(s._likesLoading ? 'Import en cours...' : 'Importer mes likes'),
          ),
        ],
      ),
    );
  }
}

// ── Tile Playlist ─────────────────────────────────────────────────────────────

class _PlaylistTile extends StatelessWidget {
  final YtPlaylist playlist;
  final _YoutubeScreenState s;
  const _PlaylistTile({required this.playlist, required this.s});

  @override
  Widget build(BuildContext context) {
    final loading = s._playlistLoading[playlist.id] ?? false;
    final result = s._playlistResult[playlist.id];
    final error = s._playlistError[playlist.id];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _PlaylistCover(url: playlist.thumbnailUrl),
          title: Text(
            playlist.title,
            style: const TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (playlist.trackCount != null)
                Text('${playlist.trackCount} titres', style: const TextStyle(color: kTextSecondary, fontSize: 12)),
              if (result != null) _ResultChip(text: result, success: true),
              if (error != null) _ResultChip(text: error, success: false),
            ],
          ),
          trailing: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
              : result != null
                  ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22)
                  : IconButton(
                      icon: const Icon(Icons.download_for_offline_outlined, color: kAccent),
                      tooltip: 'Importer dans Mkzik',
                      onPressed: () => s._importPlaylist(playlist),
                    ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final String? url;
  const _PlaylistCover({this.url});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipRoundedRect(
        radius: 8,
        child: Image.network(url!, width: 48, height: 48, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder()),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: kSurface.withValues(alpha: 1.5), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.queue_music, color: kTextSecondary, size: 24),
      );
}

class ClipRoundedRect extends StatelessWidget {
  final double radius;
  final Widget child;
  const ClipRoundedRect({super.key, required this.radius, required this.child});
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
}

// ── Composants utilitaires ────────────────────────────────────────────────────

class _ResultChip extends StatelessWidget {
  final String text;
  final bool success;
  const _ResultChip({required this.text, required this.success});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: TextStyle(
            color: success ? Colors.greenAccent : Colors.redAccent,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

class _NeedsReconnectView extends StatelessWidget {
  final _YoutubeScreenState s;
  const _NeedsReconnectView(this.s);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 40, color: kTextSecondary),
            const SizedBox(height: 12),
            const Text(
              'Ta connexion YouTube a expiré.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: s._connectLoading ? null : s._connect,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reconnecter YouTube'),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Erreur de chargement', style: TextStyle(color: kTextSecondary)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      );
}
