import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/track.dart';
import '../models/search_user.dart';
import '../services/track_service.dart';
import '../services/suggestion_service.dart';

/// Feed "Dernière sortie" → `GET api/news` (aperçu section, limité).
final newsFeedProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await TrackService.getNewsFeed(limit: 20);
  if (tracks.isEmpty && ApiConfig.useDemoData) return kDemoTracks;
  return tracks;
});

/// "Historique" → `GET api/history/tracks` (aperçu section, limité).
final historyPlayProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await TrackService.getHistoryPlay(limit: 20);
  if (tracks.isEmpty && ApiConfig.useDemoData) return kDemoTracks;
  return tracks;
});

/// "Suggestions" → mix top YouTube Music + top SoundCloud (suggestions globales,
/// titres externes jouables via `/stream`).
final globalSuggestionsProvider = FutureProvider<List<Track>>((ref) async {
  final results = await Future.wait([
    SuggestionService.youtubeTop(limit: 12),
    SuggestionService.soundcloudTop(limit: 12),
  ]);
  return _interleaveDedup(results[0], results[1], max: 16);
});

/// Alterne deux listes (a, b, a, b…) en supprimant les doublons (clé url/id).
List<Track> _interleaveDedup(List<Track> a, List<Track> b, {int max = 16}) {
  final out = <Track>[];
  final seen = <String>{};
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n && out.length < max; i++) {
    for (final t in [if (i < a.length) a[i], if (i < b.length) b[i]]) {
      final key = t.pageUrl.isNotEmpty ? t.pageUrl : t.id;
      if (seen.add(key) && out.length < max) out.add(t);
    }
  }
  return out;
}

/// "Artistes recommandés" → `GET api/trending`.
final trendingUsersProvider = FutureProvider<List<SearchUser>>((ref) async {
  final users = await TrackService.getTrendingUsers(limit: 12);
  if (users.isEmpty && ApiConfig.useDemoData) return _demoArtistsAsUsers();
  return users;
});

// Conversion des artistes démo en SearchUser (repli homogène, démo uniquement)
List<SearchUser> _demoArtistsAsUsers() => kDemoArtists
    .map((a) => SearchUser(id: a.id.hashCode, username: a.name, nbFollowers: 0))
    .toList();
