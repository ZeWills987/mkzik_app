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

/// "Suggestions YouTube" → top YouTube Music (charts), titres externes /stream.
/// Section pure (pas de mélange de plateformes — chaque source a sa rangée).
final youtubeSuggestionsProvider = FutureProvider<List<Track>>((ref) async {
  return SuggestionService.youtubeTop(limit: 16);
});

/// "Suggestions SoundCloud" → top SoundCloud (charts), titres externes /stream.
final soundcloudSuggestionsProvider = FutureProvider<List<Track>>((ref) async {
  return SuggestionService.soundcloudTop(limit: 16);
});

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
