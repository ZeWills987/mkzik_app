import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Type d'icône d'une notice (bannière de confirmation transitoire).
enum NoticeIcon { queue, playNext, share, like, info }

/// Une notice transitoire affichée dans la bannière (ex: "Ajouté à la file").
class Notice {
  final int id;
  final String message;
  final NoticeIcon icon;
  const Notice({required this.id, required this.message, this.icon = NoticeIcon.info});
}

/// File de notices transitoires (confirmations rapides), façon bannière d'import.
class NoticeNotifier extends StateNotifier<List<Notice>> {
  NoticeNotifier() : super(const []);
  int _seq = 0;

  /// Affiche une notice qui disparaît seule au bout de quelques secondes.
  void show(String message, {NoticeIcon icon = NoticeIcon.info}) {
    final id = ++_seq;
    state = [...state, Notice(id: id, message: message, icon: icon)];
    Future.delayed(const Duration(milliseconds: 2600), () => dismiss(id));
  }

  void dismiss(int id) => state = state.where((n) => n.id != id).toList();
}

final noticeProvider = StateNotifierProvider<NoticeNotifier, List<Notice>>((ref) => NoticeNotifier());
