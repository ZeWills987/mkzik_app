import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notice_provider.dart';
import '../theme/app_theme.dart';
import 'import_banner.dart';

/// Bannière des notices transitoires (confirmations rapides : file, partage…).
/// Même style visuel que la bannière d'import.
class NoticeBanner extends ConsumerWidget {
  const NoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticeProvider);
    if (notices.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final n in notices) _NoticeRow(notice: n)],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  final Notice notice;
  const _NoticeRow({required this.notice});

  IconData get _icon => switch (notice.icon) {
        NoticeIcon.queue => Icons.queue_music,
        NoticeIcon.playNext => Icons.playlist_play,
        NoticeIcon.share => Icons.link,
        NoticeIcon.like => Icons.favorite,
        NoticeIcon.info => Icons.check_circle,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: kSheetBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(_icon, color: kAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(notice.message,
                style: const TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Pile des bannières (imports + notices) à poser au-dessus du mini-player.
/// À inclure sur chaque surface (shell + routes poussées) pour que les
/// notifications restent visibles même au-dessus d'une page poussée.
class BottomBanners extends StatelessWidget {
  const BottomBanners({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [ImportBanner(), NoticeBanner()],
    );
  }
}
