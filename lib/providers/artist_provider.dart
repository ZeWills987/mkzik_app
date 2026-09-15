import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/artist_service.dart';

/// Tracks d'un artiste externe (YouTube / SoundCloud) via Python SSE.
/// Paramètre : URL du profil artiste (ex: https://www.youtube.com/@PNL).
/// Émet des snapshots cumulatifs — la liste grandit au fur et à mesure.
final artistTracksProvider =
    StreamProvider.autoDispose.family<ArtistTracksResult, String>((ref, artistUrl) {
  if (artistUrl.isEmpty) return Stream.value(const ArtistTracksResult(tracks: []));
  return ArtistService.artistTracksStream(artistUrl);
});
