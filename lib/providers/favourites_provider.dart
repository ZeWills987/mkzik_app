import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import 'auth_provider.dart';
import 'paginated_tracks_provider.dart';

/// Ziks likés de l'utilisateur connecté, paginés au scroll
/// → `GET api/{username}/favourites?limit=&offset=`.
/// Se recharge si l'username change (connexion/déconnexion), et
/// `ref.invalidate(favouritesProvider)` recrée le notifier → refetch complet
/// (les call-sites existants du like/unlike restent valides tels quels).
final favouritesProvider = StateNotifierProvider<PagedTracksNotifier, PagedTracksState>((ref) {
  final username = ref.watch(authProvider.select((s) => s.username));
  return PagedTracksNotifier(
    ({required int limit, required int offset}) {
      if (username == null || username.isEmpty) return Future.value(const <Track>[]);
      return TrackService.getFavourites(username, limit: limit, offset: offset);
    },
  );
});
