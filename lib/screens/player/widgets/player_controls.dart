import 'package:flutter/material.dart';

/// Barre supérieure du player : poignée de glissement + fermeture + file d'attente.
class PlayerTopBar extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onQueue;
  const PlayerTopBar({super.key, required this.onClose, required this.onQueue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          // Poignée de glissement
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 28),
              ),
              const Spacer(),
              // Ouvre la file d'attente (titres à venir)
              IconButton(
                onPressed: onQueue,
                icon: const Icon(Icons.queue_music, color: Colors.white70, size: 24),
                tooltip: 'File d\'attente',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barre d'actions du player : LIKE / LYRICS / SHARE / MORE.
class PlayerActionsRow extends StatelessWidget {
  final bool isLiked;
  final String likes;
  final Color accent;
  final bool hasLyrics;
  final bool lyricsActive;
  final VoidCallback onLyrics;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onMore;

  const PlayerActionsRow({
    super.key,
    required this.isLiked,
    required this.likes,
    required this.accent,
    required this.hasLyrics,
    required this.lyricsActive,
    required this.onLyrics,
    required this.onLike,
    required this.onShare,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          label: 'LIKE',
          sublabel: likes,
          color: isLiked ? accent : Colors.white,
          onTap: onLike,
        ),
        // LYRICS : actif → accent ; pas de paroles → grisé/inerte.
        _ActionItem(
          icon: Icons.mic_none,
          label: 'LYRICS',
          color: !hasLyrics ? Colors.white24 : (lyricsActive ? accent : Colors.white),
          onTap: hasLyrics ? onLyrics : () {},
        ),
        _ActionItem(icon: Icons.ios_share, label: 'SHARE', onTap: onShare),
        _ActionItem(icon: Icons.more_horiz, label: 'MORE', onTap: onMore),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    this.sublabel,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          if (sublabel != null) ...[
            const SizedBox(height: 2),
            Text(sublabel!, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

/// Bouton de saut (prev/next) — grisé quand désactivé.
class PlayerControlButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const PlayerControlButton({super.key, required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 34),
    );
  }
}

/// Bouton play/pause central : pastille à dégradé + halo coloré.
class PlayerPlayButton extends StatelessWidget {
  final bool isPlaying;
  final List<Color> colors;
  final VoidCallback onTap;

  const PlayerPlayButton({super.key, required this.isPlaying, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(color: colors.last.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 2),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 38,
        ),
      ),
    );
  }
}
