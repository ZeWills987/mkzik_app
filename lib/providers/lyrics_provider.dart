import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyrics.dart';
import '../services/lyrics_service.dart';

/// Paroles par id de track BD (tracks intégrées Symfony).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  return LyricsService.fetch(trackId);
});

/// Paroles par URL de page (tracks en flux direct sans entrée BD).
/// `GET {pythonUrl}lyrics?url=<pageUrl>` — résolu depuis le cache stream yt-dlp.
final lyricsUrlProvider = FutureProvider.family<Lyrics?, String>((ref, pageUrl) async {
  return LyricsService.fetchByUrl(pageUrl);
});
