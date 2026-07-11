import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyrics.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';
import 'player_provider.dart';

/// Paroles par id de track BD (tracks intégrées Symfony).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  return LyricsService.fetch(trackId);
});

/// Paroles d'une track en flux direct (sans entrée BD), résolues depuis le cache
/// stream yt-dlp. On passe `artist`+`title` quand on les a → plus rapide/fiable.
/// Keyé par Track (égalité fondée sur l'id) → un seul fetch par morceau.
///
/// On attend que la lecture ait réellement démarré (l'extraction yt-dlp est
/// alors terminée côté Python → cache chaud, résolution quasi-immédiate) au
/// lieu d'un délai fixe : si le titre joue déjà, le fetch part tout de suite.
/// Garde-fou 3 s max si le titre demandé n'est pas celui en lecture.
final lyricsUrlProvider = FutureProvider.family<Lyrics?, Track>((ref, track) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    final s = ref.read(playerProvider);
    if (s.currentTrack?.id == track.id && s.isPlaying) break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return LyricsService.fetchByUrl(track.pageUrl, artist: track.artist, title: track.title);
});
