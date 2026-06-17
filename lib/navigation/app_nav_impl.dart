import 'package:flutter/widgets.dart';
import '../models/track.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/track/track_page.dart';
import '../screens/player/player_modal.dart';
import 'app_nav.dart';

/// Implémentation concrète : c'est le **seul** point (hors écrans) qui connaît
/// les écrans. Les widgets passent par l'abstraction [AppNav].
class AppNavImpl implements AppNav {
  const AppNavImpl();

  @override
  Future<void> openProfile(BuildContext context, String username) =>
      ProfileScreen.open(context, username);

  @override
  Future<void> openTrack(BuildContext context, Track track) => TrackPage.open(context, track);

  @override
  Future<void> openPlayer(BuildContext context) => PlayerModal.open(context);
}
