import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/track_visuals.dart';
import '../../providers/player_provider.dart';
import '../../providers/import_provider.dart';
import '../../providers/favourites_provider.dart';
import '../../services/track_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_cover.dart';
import '../../widgets/mini_player.dart';
import '../profile/profile_screen.dart';

/// Page détaillée d'une track (single zik). On y arrive en cliquant le titre.
class TrackPage extends ConsumerStatefulWidget {
  final Track track;
  const TrackPage({super.key, required this.track});

  static Future<void> open(BuildContext context, Track track) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackPage(track: track)));
  }

  @override
  ConsumerState<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends ConsumerState<TrackPage> {
  late bool _liked = widget.track.isFavoris;
  late int _likes = widget.track.likesCount;

  Track get track => widget.track;

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    if (track.apiId == null) return;
    final res = await TrackService.toggleLike(track.apiId!);
    if (!mounted) return;
    if (!res.ok) {
      // Rollback si l'API a échoué
      setState(() {
        _liked = !_liked;
        _likes += _liked ? 1 : -1;
      });
      return;
    }
    // Synchronise l'affichage avec les valeurs exactes du backend
    setState(() {
      _liked = res.isLiked;
      _likes = res.likes;
    });
    ref.invalidate(favouritesProvider); // la librairie se met à jour
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: kSurface, behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    final colors = track.gradientColors;
    final accent = colors.first;
    final accentLight = _lighten(accent, 0.18);
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentTrack != null));

    return Scaffold(
      backgroundColor: kBg,
      bottomNavigationBar: hasTrack ? const SafeArea(top: false, child: MiniPlayer()) : null,
      body: Stack(
        children: [
          // Fond dégradé + glow dérivés de la track
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_darken(accent, 0.30), kBg],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.8),
                  radius: 1.0,
                  colors: [accent.withValues(alpha: 0.35), Colors.transparent],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Barre retour
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Grande cover
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 2)],
                    ),
                    child: TrackCover(track: track, size: 230, radius: 20),
                  ),
                  const SizedBox(height: 26),

                  // Titre (dégradé)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: ShaderMask(
                      shaderCallback: (b) => LinearGradient(colors: [accentLight, Colors.white, accentLight]).createShader(b),
                      child: Text(
                        track.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Artiste cliquable
                  GestureDetector(
                    onTap: track.artist.isEmpty ? null : () => ProfileScreen.open(context, track.artist),
                    child: Text(track.artist,
                        style: TextStyle(color: accentLight, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 14),

                  // Badges plateformes
                  _PlatformBadges(track: track),

                  const SizedBox(height: 18),
                  // Stats : durée / écoutes / likes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatPill(icon: Icons.schedule, label: track.durationFormatted),
                      if (track.listen > 0) _StatPill(icon: Icons.play_arrow, label: formatCount(track.listen)),
                      _StatPill(icon: Icons.favorite, label: formatCount(_likes)),
                    ],
                  ),

                  const SizedBox(height: 28),
                  // Bouton Écouter
                  GestureDetector(
                    onTap: () => ref.read(playerProvider.notifier).playTrack(track, queue: [track]),
                    child: Container(
                      width: 200, height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [accentLight, accent]),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 1)],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow, color: Colors.white, size: 26),
                          SizedBox(width: 8),
                          Text('Écouter', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),
                  // Actions secondaires
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionCircle(
                        icon: _liked ? Icons.favorite : Icons.favorite_border,
                        color: _liked ? accent : Colors.white,
                        label: 'J\'aime',
                        onTap: _toggleLike,
                      ),
                      _ActionCircle(
                        icon: Icons.playlist_add,
                        label: 'File',
                        onTap: () {
                          ref.read(playerProvider.notifier).addToList(track);
                          _toast('Ajouté à la file');
                        },
                      ),
                      _ActionCircle(
                        icon: Icons.ios_share,
                        label: 'Partager',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: track.pageUrl.isNotEmpty ? track.pageUrl : track.title));
                          _toast('Lien copié');
                        },
                      ),
                      if (track.isExternal)
                        _ActionCircle(
                          icon: Icons.cloud_upload,
                          label: 'Importer',
                          color: accent,
                          onTap: () {
                            ref.read(importProvider.notifier).startAndWait(track);
                            _toast('Import lancé — suis la progression en bas');
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Badges YouTube / SoundCloud
class _PlatformBadges extends StatelessWidget {
  final Track track;
  const _PlatformBadges({required this.track});

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[];
    final p = track.platforms.map((e) => e.toLowerCase()).join(' ');
    final isYt = p.contains('youtube') || track.source == 'ytm';
    final isSc = p.contains('soundcloud') || track.source == 'sc';

    if (isYt) tags.add(_badge('YouTube', const Color(0xFFFF0000), Icons.smart_display));
    if (isSc) tags.add(_badge('SoundCloud', const Color(0xFFFF7700), Icons.cloud));
    if (tags.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: tags,
    );
  }

  Widget _badge(String label, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 15),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCircle({required this.icon, required this.label, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: kTextSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}
