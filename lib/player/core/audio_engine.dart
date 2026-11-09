import '../../models/track.dart';

/// Ce que le [PlayerCore] attend d'un moteur audio : lire UN titre à la fois.
///
/// Le moteur ne connaît ni la file ni les playlists. Il charge un titre déjà
/// résolu (`track.audioUrl` jouable), le lit, et expose son état en flux.
abstract class AudioEngine {
  /// Position de lecture, en continu.
  Stream<Duration> get positionStream;

  /// Durée du titre chargé (null tant qu'elle est inconnue).
  Stream<Duration?> get durationStream;

  /// Position mise en tampon. Null quand la plateforme ne la fournit pas (Windows).
  Stream<Duration>? get bufferedStream;

  /// `true` quand la lecture est demandée (même pendant la mise en tampon).
  Stream<bool> get playingStream;

  /// Émet une fois à chaque fin de titre.
  Stream<void> get completedStream;

  /// Erreurs survenant PENDANT la lecture (URL signée expirée, flux qui meurt…).
  Stream<Object> get errorStream;

  bool get playing;

  /// Faux tant qu'aucune source n'est prête (rien de chargé ou chargement en cours).
  bool get canSeek;

  /// Charge [track] (son `audioUrl` doit être jouable) et se place au début,
  /// SANS lancer la lecture. Lève `TimeoutException` si la source ne devient pas
  /// prête à temps, ou l'erreur du lecteur (réseau, 404…).
  Future<void> load(Track track);

  /// Lance la lecture sans attendre sa fin (l'état arrive par [playingStream]).
  void play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Répète le titre en boucle. Quand c'est faux, la fin du titre est signalée
  /// par [completedStream] et c'est l'appelant qui décide de la suite.
  Future<void> setRepeatOne(bool value);

  /// Le moteur sait-il tenir le titre précédent et le suivant prêts à côté du
  /// titre courant ? Cela donne les boutons suivant / précédent de la notification
  /// et l'enchaînement sans coupure. Faux sous Windows.
  bool get supportsNeighbors;

  /// Prépare les voisins du titre chargé (chacun avec un `audioUrl` jouable ;
  /// `null` = pas de voisin de ce côté), sans interrompre la lecture. Sans effet
  /// si [supportsNeighbors] est faux.
  Future<void> setNeighbors({Track? previous, Track? next});

  /// Émet le voisin atteint quand le MOTEUR change de titre de lui-même (fin
  /// enchaînée sans coupure, ou bouton de la notification). Le moteur joue alors
  /// déjà ce titre ; l'appelant doit mettre son état à jour puis fournir de
  /// nouveaux voisins.
  Stream<Track> get movedToNeighbor;

  Future<void> dispose();
}
