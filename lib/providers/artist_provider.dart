import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/artist_service.dart';

/// Tracks + infos artiste externe (YouTube / SoundCloud) via Python.
/// Paramètre : URL du profil artiste (ex: https://www.youtube.com/@PNL).
final artistTracksProvider =
    FutureProvider.autoDispose.family<ArtistTracksResult, String>((ref, artistUrl) async {
  if (artistUrl.isEmpty) return const ArtistTracksResult(tracks: []);
  return ArtistService.artistTracks(artistUrl);
});
