import '../../models/track.dart';

/// Boutons média du système (touches du clavier, panneau média de Windows).
enum MediaButton { playPause, next, previous }

/// Contrôles média fournis par le système d'exploitation, en dehors de la
/// notification Android / iOS déjà gérée par le moteur audio.
abstract class SystemMediaControls {
  /// Appuis sur les boutons média du système.
  Stream<MediaButton> get buttons;

  /// Affiche le titre en cours (titre, artiste, pochette).
  void showTrack(Track track);

  void setPlaying(bool playing);

  Future<void> dispose();
}

/// Plateformes sans contrôles média système à gérer (mobile : la notification
/// est déjà fournie par just_audio_background).
class NoopMediaControls implements SystemMediaControls {
  @override
  Stream<MediaButton> get buttons => const Stream.empty();

  @override
  void showTrack(Track track) {}

  @override
  void setPlaying(bool playing) {}

  @override
  Future<void> dispose() async {}
}
