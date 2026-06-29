import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lyrics.dart';
import '../services/lyrics_service.dart';

/// Paroles d'une track par id — chargées à la demande et **cachées** par Riverpod
/// (un seul fetch par track tant que le provider reste en vie).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  return LyricsService.fetch(trackId);
});
