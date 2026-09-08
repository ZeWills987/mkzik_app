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

/// "Suggestions YouTube" → feed personnalisé si Google lié + token valide, générique sinon.
/// On ne peut pas savoir si le token YTMusic est valide sans appeler Python →
/// on tente personal (JWT si connecté), et on retombe sur home si vide (404/expiré).
final youtubeSuggestionsProvider = FutureProvider<List<Track>>((ref) async {
  final hasJwt = ApiConfig.token?.isNotEmpty ?? false;
  if (!hasJwt) return SuggestionService.youtubeHome(limit: 16);
  final personal = await SuggestionService.youtubePersonal(limit: 16);
  if (personal.isNotEmpty) return personal;
  return SuggestionService.youtubeHome(limit: 16);
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
