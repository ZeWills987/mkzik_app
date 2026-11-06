import 'dart:async';
import '../../models/track.dart';
import '../../services/track_service.dart';

typedef StartPlay = Future<int?> Function(int trackId);
typedef CompletePlay = Future<void> Function(
  int playId, {
  required double listenedSeconds,
  required bool completed,
});

/// Suivi d'écoute d'UN titre à la fois : `POST /api/plays` au début, puis
/// `PATCH /api/plays/{id}/complete` à la fin avec les secondes écoutées (position
/// maximale atteinte) et si l'écoute est terminée (≥ 90 % de la durée).
///
/// Aucune dépendance au lecteur : le moteur lui envoie la position
/// ([onPosition]) et signale début / fin ([begin] / [finish]). Les appels réseau
/// sont injectables (par défaut [TrackService]).
class PlayTracker {
  PlayTracker({StartPlay? startPlay, CompletePlay? completePlay})
      : _startPlay = startPlay ?? TrackService.startPlay,
        _completePlay = completePlay ?? TrackService.completePlay;

  final StartPlay _startPlay;
  final CompletePlay _completePlay;

  /// Part de la durée à partir de laquelle l'écoute compte comme terminée.
  static const completedRatio = 0.9;

  int? _playId; // playId de l'écoute en cours (null tant que le backend n'a pas répondu)
  Track? _track; // titre suivi par cette écoute
  int _maxMs = 0; // position max atteinte → listenedSeconds

  /// Titre actuellement suivi (null si aucune écoute en cours).
  Track? get tracked => _track;

  /// À appeler à chaque tick de position du moteur.
  void onPosition(Duration position) {
    final ms = position.inMilliseconds;
    if (_track != null && ms > _maxMs) _maxMs = ms;
  }

  /// Démarre l'écoute de [t]. Une éventuelle écoute précédente doit avoir été
  /// clôturée avant ([finish]).
  Future<void> begin(Track t) async {
    _track = t;
    _maxMs = 0;
    _playId = null;
    if (t.apiId == null) return;
    final id = await _startPlay(t.apiId!);
    if (_track?.id == t.id) {
      _playId = id;
    } else if (id != null) {
      // Le titre a changé pendant l'await (skip rapide) : cette écoute ne sera
      // jamais clôturée par [finish] → on la clôt tout de suite à 0 s pour ne
      // pas laisser d'écoute orpheline côté backend.
      unawaited(_completePlay(id, listenedSeconds: 0, completed: false));
    }
  }

  /// Clôt l'écoute en cours : envoie les secondes écoutées et si elle est terminée.
  Future<void> finish() async {
    final id = _playId;
    final t = _track;
    final maxMs = _maxMs;
    _playId = null;
    _track = null;
    _maxMs = 0;
    if (id == null || t == null) return;
    final durMs = t.duration.inMilliseconds;
    final completed = durMs > 0 && maxMs >= durMs * completedRatio;
    await _completePlay(id, listenedSeconds: maxMs / 1000.0, completed: completed);
  }
}
