import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/artist_service.dart';

/// Tracks d'un artiste externe (YouTube / SoundCloud) via Python.
/// Paramètre : URL du profil artiste (ex: https://www.youtube.com/@PNL).
final artistTracksProvider =
    FutureProvider.autoDispose.family<List<Track>, String>((ref, artistUrl) async {
  if (artistUrl.isEmpty) return const [];
  return ArtistService.artistTracks(artistUrl);
});
