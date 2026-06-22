import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/track.dart';
import '../models/search_user.dart';
import '../services/track_service.dart';

/// Feed "Dernière sortie" → `GET api/news` (aperçu section, limité).
final newsFeedProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await TrackService.getNewsFeed(limit: 20);
  if (tracks.isEmpty && ApiConfig.useDemoData) return kDemoTracks;
  return tracks;
});

/// "Historique" → `GET api/tracks/history` (aperçu section, limité).
final historyPlayProvider = FutureProvider<List<Track>>((ref) async {
  final tracks = await TrackService.getHistoryPlay(limit: 20);
  if (tracks.isEmpty && ApiConfig.useDemoData) return kDemoTracks;
  return tracks;
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
