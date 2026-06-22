import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/playlist_service.dart';
import 'auth_provider.dart';

/// Playlists de l'utilisateur connecté → `GET /api/playlists?username=`.
/// Se recharge automatiquement si l'username change (connexion/déconnexion).
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final username = ref.watch(authProvider.select((s) => s.username));
  if (username == null || username.isEmpty) return const <Playlist>[];
  return PlaylistService.getPlaylists(username);
});

/// Titres d'une playlist → `GET /api/playlists/{id}/tracks`.
final playlistTracksProvider = FutureProvider.family<List<Track>, int>((ref, id) async {
  return PlaylistService.getTracks(id);
});
