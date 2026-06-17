import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/profile.dart';
import '../models/track.dart';
import '../services/profile_service.dart';

/// Données agrégées d'une page profil.
class ProfileData {
  final Profile profile;
  final List<Track> tracks;

  const ProfileData({required this.profile, required this.tracks});

  /// Total des écoutes = somme des `listen` des Ziks.
  int get totalPlays => tracks.fold(0, (sum, t) => sum + t.listen);
}

/// Charge profil + Ziks en parallèle.
/// En production (DEMO=false), un profil introuvable lève une erreur (état d'erreur réel).
final profileProvider = FutureProvider.family<ProfileData, String>((ref, username) async {
  final profileFuture = ProfileService.getProfile(username);
  final tracksFuture = ProfileService.getUserTracks(username);

  final profile = await profileFuture;
  final tracks = await tracksFuture;

  if (profile == null) {
    if (ApiConfig.useDemoData) {
      return ProfileData(profile: _demoProfile(username), tracks: tracks.isEmpty ? kDemoTracks : tracks);
    }
    throw Exception('Profil introuvable');
  }

  return ProfileData(
    profile: profile,
    tracks: (tracks.isEmpty && ApiConfig.useDemoData) ? kDemoTracks : tracks,
  );
});

// Profil de secours (démo uniquement)
Profile _demoProfile(String username) => Profile(
      username: username,
      description: 'Mélomane chez Mkzik 🎧 — partage tes sons préférés.',
      nbFollowers: 1240,
      nbFollowing: 312,
    );
