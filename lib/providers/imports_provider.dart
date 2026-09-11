import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import 'auth_provider.dart';
import 'paginated_tracks_provider.dart';

/// Imports de l'utilisateur connecté, paginés au scroll
/// → `GET api/me/imports?limit=&offset=`.
/// Se recharge si le token change (connexion/déconnexion).
final importsProvider = StateNotifierProvider<PagedTracksNotifier, PagedTracksState>((ref) {
  final username = ref.watch(authProvider.select((s) => s.username));
  return PagedTracksNotifier(
    ({required int limit, required int offset}) {
      if (username == null || username.isEmpty) return Future.value(const <Track>[]);
      return TrackService.getImports(limit: limit, offset: offset);
    },
  );
});

/// Imports paginés pour la vue "Voir tout" (TrackListScreen).
final importsPagedProvider =
    StateNotifierProvider.autoDispose<PagedTracksNotifier, PagedTracksState>((ref) {
  return PagedTracksNotifier(
    ({required int limit, required int offset}) => TrackService.getImports(limit: limit, offset: offset),
  );
});
