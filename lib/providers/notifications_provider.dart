import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/notification.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// État de la liste de notifications (paginée au scroll).
class NotificationsState {
  final List<AppNotification> items;
  final int unreadCount;
  final bool initialLoading;
  final bool loadingMore;
  final bool hasMore;
  final bool error; // échec du 1er chargement

  const NotificationsState({
    this.items = const [],
    this.unreadCount = 0,
    this.initialLoading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error = false,
  });

  NotificationsState copyWith({
    List<AppNotification>? items,
    int? unreadCount,
    bool? initialLoading,
    bool? loadingMore,
    bool? hasMore,
    bool? error,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        unreadCount: unreadCount ?? this.unreadCount,
        initialLoading: initialLoading ?? this.initialLoading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error ?? this.error,
      );
}

const _kPageSize = 20;

/// Liste des notifications + compteur non-lues, avec actions optimistes
/// (marquer lu / tout lu / supprimer) et badge poll léger (60 s).
class NotificationsNotifier extends StateNotifier<NotificationsState> {
  Timer? _badgePoll;

  NotificationsNotifier() : super(const NotificationsState()) {
    refresh();
    // Badge : poll la route COUNT ultra-légère (pas la liste) toutes les 60 s.
    _badgePoll = Timer.periodic(const Duration(seconds: 60), (_) => refreshBadge());
  }

  @override
  void dispose() {
    _badgePoll?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    state = state.copyWith(initialLoading: state.items.isEmpty, error: false);
    final page = await NotificationService.list(limit: _kPageSize, offset: 0);
    if (!mounted) return;
    if (page == null) {
      state = state.copyWith(initialLoading: false, error: state.items.isEmpty, hasMore: false);
      return;
    }
    state = NotificationsState(
      items: page.notifications,
      unreadCount: page.unreadCount,
      initialLoading: false,
      hasMore: page.notifications.length >= _kPageSize,
    );
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.initialLoading) return;
    state = state.copyWith(loadingMore: true);
    final page = await NotificationService.list(limit: _kPageSize, offset: state.items.length);
    if (!mounted) return;
    if (page == null) {
      state = state.copyWith(loadingMore: false, hasMore: false);
      return;
    }
    state = state.copyWith(
      items: [...state.items, ...page.notifications],
      unreadCount: page.unreadCount,
      loadingMore: false,
      hasMore: page.notifications.length >= _kPageSize,
    );
  }

  /// Rafraîchit uniquement le compteur (badge cloche).
  Future<void> refreshBadge() async {
    if (!(ApiConfig.token?.isNotEmpty ?? false)) return;
    final count = await NotificationService.unreadCount();
    if (mounted && count != null && count != state.unreadCount) {
      state = state.copyWith(unreadCount: count);
    }
  }

  /// Marque [n] lue — optimiste (rollback si l'API échoue).
  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    _apply(n.id, read: true);
    final ok = await NotificationService.markRead(n.id);
    if (!ok && mounted) _apply(n.id, read: false);
  }

  Future<void> markAllRead() async {
    final before = state;
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(isRead: true)],
      unreadCount: 0,
    );
    final ok = await NotificationService.markAllRead();
    if (!ok && mounted) state = before;
  }

  Future<void> delete(AppNotification n) async {
    final before = state;
    state = state.copyWith(
      items: state.items.where((x) => x.id != n.id).toList(),
      unreadCount: n.isRead ? state.unreadCount : (state.unreadCount - 1).clamp(0, 1 << 30),
    );
    final ok = await NotificationService.delete(n.id);
    if (!ok && mounted) state = before;
  }

  void _apply(int id, {required bool read}) {
    state = state.copyWith(
      items: [for (final n in state.items) n.id == id ? n.copyWith(isRead: read) : n],
      unreadCount: (state.unreadCount + (read ? -1 : 1)).clamp(0, 1 << 30),
    );
  }
}

/// Recréé à chaque changement d'utilisateur (login/logout).
final notificationsProvider = StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  ref.watch(authProvider.select((s) => s.username)); // reset à la connexion
  return NotificationsNotifier();
});

/// Compteur non-lues seul (pour le badge cloche, rebuild minimal).
final unreadNotificationsProvider =
    Provider<int>((ref) => ref.watch(notificationsProvider.select((s) => s.unreadCount)));
