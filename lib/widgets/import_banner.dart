import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/import_provider.dart';
import '../theme/app_theme.dart';

/// Bannière empilée des imports externes en cours / terminés.
/// Placée au-dessus du mini-player. Disparaît quand aucun import.
class ImportBanner extends ConsumerWidget {
  const ImportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importProvider);
    // Les jobs `streaming` sont silencieux pendant la résolution du flux —
    // on n'affiche que les imports réels et les erreurs de stream.
    final visible = jobs.where((j) => j.status != ImportStatus.streaming).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    // Une seule notification à la fois : erreur > en cours > terminé,
    // parmi les ex-æquo le plus récent (last dans la liste).
    final job = visible.lastWhere(
      (j) => j.status == ImportStatus.error,
      orElse: () => visible.lastWhere(
        (j) => !j.isDone,
        orElse: () => visible.last,
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _ImportRow(
        key: ValueKey(job.id),
        job: job,
        onDismiss: () => ref.read(importProvider.notifier).dismiss(job.id),
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  final ImportJob job;
  final VoidCallback onDismiss;
  const _ImportRow({super.key, required this.job, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (job.status) {
      ImportStatus.completed => (Icons.check_circle, kAccent),
      ImportStatus.error => (Icons.error_outline, kErrorText),
      _ => (null, kAccent), // en cours → spinner
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kSheetBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: job.status == ImportStatus.error
              ? kError.withValues(alpha: 0.4)
              : kAccent.withValues(alpha: 0.3),
        ),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          // Icône d'état (spinner pendant l'import)
          SizedBox(
            width: 22,
            height: 22,
            child: icon == null
                ? const CircularProgressIndicator(strokeWidth: 2.4, color: kAccent)
                : Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(job.title,
                    style: const TextStyle(color: kTextPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(job.label,
                    style: TextStyle(
                      color: job.status == ImportStatus.error ? kErrorText : kTextSecondary,
                      fontSize: 11.5,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Fermer (pour les imports terminés/échoués)
          if (job.isDone)
            GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, color: kTextSecondary, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
