import 'dart:async';
import 'package:mkzik_app/models/track.dart';
import 'package:mkzik_app/player/core/audio_engine.dart';

/// Faux moteur audio pour les tests : enregistre les appels, échoue sur
/// commande, et permet de simuler fin de titre, erreur et position.
class FakeAudioEngine implements AudioEngine {
  final List<Track> loaded = [];
  int playCalls = 0;
  int pauseCalls = 0;
  final List<Duration> seeks = [];
  bool repeatOne = false;

  /// Faux : `canSeek` renvoie faux (rien de prêt).
  bool ready = true;

  /// Une entrée par appel à `load` : si non null, c'est l'erreur à lever.
  final List<Object?> loadOutcomes = [];

  /// Si non null, `load` attend ce Completer (simule un chargement lent).
  Completer<void>? loadGate;

  /// Voisins demandés par le notifier (dernier appel à `setNeighbors`).
  Track? neighborPrevious;
  Track? neighborNext;
  int setNeighborsCalls = 0;
  bool neighbors = false;

  bool _playing = false;
  final _movedC = StreamController<Track>.broadcast();
  final _playingC = StreamController<bool>.broadcast();
  final _completedC = StreamController<void>.broadcast();
  final _errorsC = StreamController<Object>.broadcast();
  final _positionC = StreamController<Duration>.broadcast();
  final _durationC = StreamController<Duration?>.broadcast();

  // ── Déclencheurs de test ──────────────────────────────────────────────────
  void finishTrack() => _completedC.add(null);
  void emitError(Object e) => _errorsC.add(e);
  void emitPosition(Duration d) => _positionC.add(d);
  void emitDuration(Duration d) => _durationC.add(d);

  /// Simule un changement de titre fait par le moteur (enchaînement ou bouton
  /// de notification) vers le voisin demandé.
  void moveToNext() => _movedC.add(neighborNext!);
  void moveToPrevious() => _movedC.add(neighborPrevious!);

  // ── AudioEngine ───────────────────────────────────────────────────────────
  @override
  Future<void> load(Track track) async {
    loaded.add(track);
    final i = loaded.length - 1;
    final gate = loadGate;
    if (gate != null) await gate.future;
    final outcome = i < loadOutcomes.length ? loadOutcomes[i] : null;
    if (outcome != null) throw outcome;
  }

  @override
  void play() {
    playCalls++;
    _playing = true;
    _playingC.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    _playingC.add(false);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setRepeatOne(bool value) async => repeatOne = value;

  @override
  bool get playing => _playing;

  @override
  bool get canSeek => ready;

  @override
  Stream<Duration> get positionStream => _positionC.stream;

  @override
  Stream<Duration?> get durationStream => _durationC.stream;

  @override
  Stream<Duration>? get bufferedStream => null;

  @override
  Stream<bool> get playingStream => _playingC.stream;

  @override
  Stream<void> get completedStream => _completedC.stream;

  @override
  Stream<Object> get errorStream => _errorsC.stream;

  @override
  bool get supportsNeighbors => neighbors;

  @override
  Future<void> setNeighbors({Track? previous, Track? next}) async {
    setNeighborsCalls++;
    neighborPrevious = previous;
    neighborNext = next;
  }

  @override
  Stream<Track> get movedToNeighbor => _movedC.stream;

  @override
  Future<void> dispose() async {
    await _movedC.close();
    await _playingC.close();
    await _completedC.close();
    await _errorsC.close();
    await _positionC.close();
    await _durationC.close();
  }
}
