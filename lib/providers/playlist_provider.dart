import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../services/playlist_service.dart';
import 'auth_provider.dart';

/// Playlists de l'utilisateur connecté → `GET /api/playlist?username=`.
/// Se recharge automatiquement si l'username change (connexion/déconnexion).
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final username = ref.watch(authProvider.select((s) => s.username));
  if (username == null || username.isEmpty) return const <Playlist>[];
  return PlaylistService.getPlaylists(username);
});
