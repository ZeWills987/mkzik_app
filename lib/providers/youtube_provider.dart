import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/yt_playlist.dart';
import '../services/youtube_service.dart';

final ytConnectedProvider = FutureProvider<bool>((ref) async {
  return YoutubeService.isConnected();
});

/// `true` si la connexion a été faite avec OAuth v2 (scopes complets).
/// Invalidé après reconnexion réussie pour masquer le bandeau.
final ytOauthV2Provider = FutureProvider<bool>((ref) async {
  return YoutubeService.isOauthV2();
});

final ytPlaylistsProvider = FutureProvider<List<YtPlaylist>>((ref) async {
  final connected = await ref.watch(ytConnectedProvider.future);
  if (!connected) return const [];
  return YoutubeService.playlists();
});
