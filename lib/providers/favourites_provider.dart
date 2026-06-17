import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/track_service.dart';
import 'auth_provider.dart';

/// Ziks likés de l'utilisateur connecté → `GET api/{username}/favourites`.
/// Se recharge automatiquement si l'username change (connexion/déconnexion).
final favouritesProvider = FutureProvider<List<Track>>((ref) async {
  final username = ref.watch(authProvider.select((s) => s.username));
  if (username == null || username.isEmpty) return const <Track>[];
  return TrackService.getFavourites(username);
});
