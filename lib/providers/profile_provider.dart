import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';
import 'paginated_tracks_provider.dart';

/// Charge le profil d'un utilisateur.
/// En production (DEMO=false), un profil introuvable lève une erreur.
final profileProvider = FutureProvider.family<Profile, String>((ref, username) async {
  final profile = await ProfileService.getProfile(username);
  if (profile == null) {
    if (ApiConfig.useDemoData) return _demoProfile(username);
    throw Exception('Profil introuvable');
  }
  return profile;
});

/// Ziks d'un profil, paginés au scroll.
/// autoDispose → libéré quand on quitte l'écran profil.
final profileTracksProvider =
    StateNotifierProvider.autoDispose.family<PagedTracksNotifier, PagedTracksState, String>((ref, username) {
  int? total;
  return PagedTracksNotifier(
    ({required int limit, required int offset}) async {
      final (tracks, t) = await ProfileService.getUserTracks(username, limit: limit, offset: offset);
      if (t != null) total = t;
      return tracks;
    },
    pageSize: 20,
    totalGetter: () => total,
  );
});

// Profil de secours (démo uniquement)
Profile _demoProfile(String username) => Profile(
      username: username,
      description: 'Mélomane chez Mkzik 🎧 — partage tes sons préférés.',
      nbFollowers: 1240,
      nbFollowing: 312,
    );
