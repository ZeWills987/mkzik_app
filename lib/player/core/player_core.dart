import 'dart:async';
import '../../models/track.dart';
import '../../utils/logger.dart';
import 'audio_engine.dart';
import 'playback_error.dart';
import 'track_resolver.dart';

/// Pourquoi un titre n'a pas pu démarrer.
enum LoadFailureKind {
  /// Requête annulée côté serveur (409, client parti) : à ignorer en silence.
  cancelledByServer,

  /// Titre réellement mort (404, supprimé, privé, géo-bloqué, format non supporté).
  unavailable,

  /// Flux Python pas encore prêt (lent, surcharge, anti-bot) : inutile d'attendre,
  /// l'appelant peut enchaîner et revenir plus tard.
  streamNotReady,

  /// Le chargement n'a pas abouti dans le délai, même après une nouvelle tentative.
  timeout,

  /// Erreur réseau ou lecteur, même après une nouvelle tentative.
  network,
}

/// Résultat de [PlayerCore.load]. C'est à l'appelant (la file) de décider quoi
/// faire d'un échec : sauter le titre, le différer, afficher un message.
sealed class LoadResult {
  const LoadResult();
}

/// Le titre joue. [track] est le titre résolu (avec son `audioUrl` jouable).
class LoadStarted extends LoadResult {
  final Track track;
  const LoadStarted(this.track);
}

/// Une demande plus récente a remplacé celle-ci : rien à faire.
class LoadStale extends LoadResult {
  const LoadStale();
}

/// Aucune URL jouable pour ce titre (ni flux Python, ni URL signée).
class LoadNoSource extends LoadResult {
  const LoadNoSource();
}

class LoadFailed extends LoadResult {
  final LoadFailureKind kind;

  /// Code HTTP lu dans l'erreur, si le lecteur en expose un.
  final int? status;
  const LoadFailed(this.kind, {this.status});
}

/// « Jouer un titre » : résout son URL, le charge dans le moteur et le lance.
///
/// Ne connaît ni la file, ni les playlists, ni l'interface. Il garde la
/// responsabilité technique (une nouvelle tentative sur erreur transitoire) et
/// laisse la politique à l'appelant via [LoadResult].
class PlayerCore {
  PlayerCore({required this.engine, required this.resolver});

  final AudioEngine engine;
  final TrackResolver resolver;

  /// Nombre d'essais pour charger un titre (les flux externes échouent parfois
  /// de façon transitoire : un nouvel essai immédiat suffit souvent).
  static const maxAttempts = 2;

  /// Résout [track], le charge et lance la lecture.
  ///
  /// [isStale] : l'appelant dit si la demande a été remplacée entre-temps (taps
  /// rapides) ; vérifié après chaque attente. [onResolved] est appelé une fois
  /// l'URL connue, avant le chargement dans le moteur (l'import a pu transformer
  /// le titre : l'appelant met sa file à jour). [repeatOne] : répéter ce titre.
  Future<LoadResult> load(
    Track track, {
    bool Function()? isStale,
    void Function(Track resolved)? onResolved,
    bool repeatOne = false,
  }) async {
    bool stale() => isStale?.call() ?? false;

    final current = await resolver.resolvePlayable(track);
    if (stale()) return const LoadStale();
    if (current == null || current.audioUrl.isEmpty) return const LoadNoSource();
    onResolved?.call(current);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await engine.load(current);
        if (stale()) return const LoadStale();
        await engine.setRepeatOne(repeatOne);
        engine.play();
        return LoadStarted(current);
      } catch (e) {
        mkLog('Mkzik ▶ erreur lecture "${track.title}" (tentative $attempt/$maxAttempts) : $e');
        if (stale()) return const LoadStale();
        final failure = _classify(e, current, attempt);
        if (failure != null) return failure;
        // Erreur transitoire sur un titre non-flux : on retente.
      }
    }
    // Inatteignable : la dernière tentative renvoie toujours un échec.
    return const LoadFailed(LoadFailureKind.network);
  }

  /// Échec définitif, ou null s'il vaut la peine de réessayer.
  LoadFailed? _classify(Object e, Track track, int attempt) {
    final status = httpStatusIn(e);
    final timedOut = e is TimeoutException;
    final unavailable = isTrackUnavailable(e);
    // Requête annulée côté serveur (client parti) → silencieux.
    if (status == 409) return LoadFailed(LoadFailureKind.cancelledByServer, status: status);
    // Flux Python lent / anti-bot / surcharge : on n'attend pas.
    final transient = timedOut || transientHttpStatuses.contains(status);
    if (track.needsStream && transient && !unavailable) {
      return LoadFailed(LoadFailureKind.streamNotReady, status: status);
    }
    // Titre mort : inutile de réessayer.
    if (unavailable) return LoadFailed(LoadFailureKind.unavailable, status: status);
    if (attempt >= maxAttempts) {
      return LoadFailed(timedOut ? LoadFailureKind.timeout : LoadFailureKind.network, status: status);
    }
    return null;
  }

  bool get isPlaying => engine.playing;

  void play() => engine.play();

  Future<void> pause() => engine.pause();

  Future<void> togglePlayPause() async {
    if (engine.playing) {
      await engine.pause();
    } else {
      engine.play();
    }
  }

  /// Pas de seek tant que la source n'est pas prête (résolution yt-dlp en cours) :
  /// just_audio peut lever ou se placer sur la mauvaise source.
  Future<void> seek(Duration position) async {
    if (!engine.canSeek) return;
    try {
      await engine.seek(position);
    } catch (e) {
      mkLog('Mkzik ▶ seek impossible : $e');
    }
  }

  /// Reprend le titre chargé depuis le début. Faux si le moteur n'est pas prêt
  /// ou si la reprise échoue : l'appelant doit alors recharger.
  Future<bool> restart() async {
    if (!engine.canSeek) return false;
    try {
      await engine.seek(Duration.zero);
      engine.play();
      return true;
    } catch (e) {
      mkLog('Mkzik ▶ reprise au début impossible, rechargement : $e');
      return false;
    }
  }

  Future<void> setRepeatOne(bool value) => engine.setRepeatOne(value);

  Future<void> dispose() => engine.dispose();
}
