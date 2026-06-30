import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';

/// Paroles par id de track BD (tracks intégrées Symfony).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  return LyricsService.fetch(trackId);
});

/// Paroles d'une track en flux direct (sans entrée BD), résolues depuis le cache
/// stream yt-dlp. On passe `artist`+`title` quand on les a → plus rapide/fiable.
/// Keyé par Track (égalité fondée sur l'id) → un seul fetch par morceau.
///
/// Le délai de 3 s laisse yt-dlp terminer l'extraction audio avant que Python
/// ne reçoive la requête lyrics — évite deux extractions concurrentes au démarrage.
/// À 3 s le cache /stream est chaud : la résolution lyrics est alors quasi-immédiate.
final lyricsUrlProvider = FutureProvider.family<Lyrics?, Track>((ref, track) async {
  await Future<void>.delayed(const Duration(seconds: 3));
  return LyricsService.fetchByUrl(track.pageUrl, artist: track.artist, title: track.title);
});

